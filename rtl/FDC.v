//============================================================================
//  FM-7 floppy disk controller: MB8877 + the FM-7's own $fd1c-$fd1f registers
//
//  The MB8877 is register- and command-compatible with the WD1793 (MAME's own
//  compatibility table, refs/mame/src/devices/machine/wd_fdc.h:31, lists it as
//  "fd1793 compatible" with a NORMAL, non-inverted data bus -- unlike its
//  MB8876/MB8866 siblings). MAME instantiates it for every FM-7 variant and
//  never calls dden_w(), so it runs permanently in MFM / double density, which
//  is what FM-7 2D media needs.
//
//  rtl/wd1793.sv is vendored from refs/fdc/spectrum-wd1793 with one local
//  change, marked LOCAL CHANGE in that file (a declaration moved out of a
//  generate block so Verilator will elaborate it). This file is the glue:
//
//    * $fd18-$fd1b (FD_RS 0-3) go straight to the WD1793 core.
//    * $fd1c-$fd1f (FD_RS 4-7) do NOT exist in the chip -- on real hardware
//      they are board logic, and MAME models them in C++ (fm7.cpp fdc_r/fdc_w).
//      They are implemented here.
//    * MFD.v drives FD_WEn/FD_REn from the 6809's E/Q overlap, a ~200 ns
//      window. The core samples on a 1 MHz ce, so an access has to be latched
//      and stretched to survive the crossing -- see "Crossing from the bus into
//      the controller's clock enable" below. This is not cosmetic: without it
//      no register write reaches the chip at all.
//    * The core's drq/intrq are ACTIVE HIGH (real WD179x pins); MFD.v wants
//      active low. Inverted below. Getting this backwards gives either an
//      interrupt storm or a permanently busy-looking controller.
//
//  The MiSTer block-device interface (sd_lba/sd_rd/sd_wr/sd_buff_*) is brought
//  out to the top level, so images reach the core over hps_io on hardware and
//  over SimBlockDevice in vsim.
//
//  .d77 images are understood: wd1793.sv reads the whole image once at mount
//  time and builds a sector table from it (see the .D77 block in that file, and
//  refs/fdc/d77-format.md). Geometry is therefore per-track and per-sector, not
//  assumed, which .d77 requires -- the format interleaves a 16-byte header
//  before every sector, and real images have tracks with differing sector
//  counts.
//
//  `ready` is held low while that scan runs, so the drive reports not-ready
//  rather than answering out of a half-built table.
//============================================================================

module FDC(
  input CLKSYS,
  input FD_MRn,          // master reset, active low
  input [7:0] FD_Din,    // data from the CPU
  output [7:0] FD_Dout,  // data to the CPU
  input [2:0] FD_RS,     // register select, $fd18 + FD_RS
  output FD_DRQn,
  output FD_INTRQn,
  input FD_CSn,
  input FD_WEn,
  input FD_REn,

  // MiSTer block-device interface (hps_io on hardware, SimBlockDevice in vsim).
  // The FM-7 has one MB8877 controller serving two independently mounted
  // drives. Each drive gets its own WD core so its D77 sector table survives
  // while the other drive is selected.
  input  [1:0]  img_mounted,
  input         img_readonly,
  input  [63:0] img_size,
  output [31:0] sd_lba [2],
  output [1:0]  sd_rd,
  output [1:0]  sd_wr,
  input  [1:0]  sd_ack,
  input   [8:0] sd_buff_addr,
  input   [7:0] sd_buff_dout,
  output  [7:0] sd_buff_din [2],
  input         sd_buff_wr
);

wire reset = ~FD_MRn;

//----------------------------------------------------------------------------
// Clock enable
//
// MAME clocks the MB8877 at 8_MHz_XTAL/8 = 1 MHz (fm7.cpp). CLKSYS is 48 MHz,
// so a 1-in-48 enable gives the chip its real rate.
//----------------------------------------------------------------------------

reg [5:0] ce_cnt = 6'd0;
reg       ce = 1'b0;
always @(posedge CLKSYS) begin
  ce <= 1'b0;
  if (ce_cnt == 6'd47) begin
    ce_cnt <= 6'd0;
    ce     <= 1'b1;
  end
  else ce_cnt <= ce_cnt + 6'd1;
end

// The mount-time scan replays the whole image through the controller one byte
// per 8 ce ticks. At the MB8877's real 1 MHz that is 8us a byte -- about 2.8
// seconds for a 345 KB 2D image, which is long enough to look like a hang and
// long enough that a boot ROM already polling the drive gives up before the
// table exists.
//
// So free-run ce while the scan is in progress. Nothing else is happening: the
// command FSM sits in STATE_IDLE for the whole scan, and `ready` is low, so a
// command that does arrive is rejected on the spot rather than being run at the
// wrong rate. What is left is the byte replay, which goes as fast as the blocks
// arrive -- on hardware that means the SD reads set the pace, which is right.
wire prepare0, prepare1;
wire ce_wd = ce | prepare0 | prepare1;

//----------------------------------------------------------------------------
// Host strobes
//
// FD_WEn/FD_REn are active low and stay low for as long as the 6809's E/Q
// overlap lasts. Turn each into a one-CLKSYS pulse on its falling edge so a
// single CPU access is registered exactly once; the pulse is then stretched
// into the controller's clock domain below.
//----------------------------------------------------------------------------

reg wen_d = 1'b1, ren_d = 1'b1;
always @(posedge CLKSYS) begin
  wen_d <= FD_WEn;
  ren_d <= FD_REn;
end

wire sel      = ~FD_CSn;
wire core_sel = sel & ~FD_RS[2];          // $fd18-$fd1b
wire aux_sel  = sel &  FD_RS[2];          // $fd1c-$fd1f
wire wr_stb   = ~FD_WEn & wen_d;          // falling edge of FD_WEn
wire rd_stb   = ~FD_REn & ren_d;          // falling edge of FD_REn

//----------------------------------------------------------------------------
// Crossing from the bus into the controller's clock enable
//
// The WD1793 core samples rd/wr/addr/din only on `ce` ticks and does its own
// edge detection there, so an access has to stay visible for a whole ce period
// to be seen at all. The 6809's E/Q write window is about 200 ns and CLKSYS is
// 48 MHz, so a single-cycle bus strobe is 1/48th of a 1 MHz ce period wide and
// is essentially never sampled. Measured, before this was here: the DOS boot
// ROM issued 11 register writes and the controller received none of them, so
// every command byte it thought it had sent was simply dropped.
//
// So latch the access -- address, data, direction -- on the bus edge and hold
// the strobe until one ce tick has consumed it. The core then sees a clean
// 0->1->0 across consecutive ce ticks, which is also what its end-of-transfer
// detection needs (`old_rd && !rde` on a data read is how it advances a byte).
//
// The latched address feeds the core's read mux too, so it stays pointed at the
// register being read for the whole bus cycle rather than following the bus.
//
// LOCAL CHANGE: an earlier version of this comment claimed two accesses could
// not land inside one ce period, because consecutive FDC accesses are "several
// bus cycles apart". That holds for the boot ROM's driver and is false in
// general -- see the write-strobe discussion below, which is where the real
// constraint lives.
//
// Reads are deliberately NOT held back: `dout` is combinational and the CPU
// latches it inside the same bus cycle, so a read strobe has to take effect on
// the bus edge. `acc_addr` is a single "address of the last access" register
// shared by both directions, as it always was.
//----------------------------------------------------------------------------

// What actually gets lost, and why it is not simply "two writes at once".
//
// The core only accepts a write on a rising edge *as it samples it*, on ce
// ticks: `if (!old_wr & wre)`. A held-high strobe is therefore not the problem
// by itself -- the problem is a strobe that goes low and back high entirely
// *between* two ce ticks. The core samples high at tick N, high again at tick
// N+1, and never observes the low in between, so the second write is not an
// edge and is silently discarded.
//
// That is exactly what Ys's driver produces: it sets track and sector with one
// 16-bit store to $fd19, so the two writes are one bus cycle (814 ns) apart --
// shorter than a ce period. The track write ($00 over an already-zero register)
// landed, the sector write vanished, and every later READ SECTOR reused the
// previous sector number. Ys asked for side 1 sectors 1, 2 and 3 and got sector
// 3 three times, into three different buffers, each read completing with status
// $00 and byte-perfect data. Nothing downstream could see it was wrong.
//
// Testing `acc_wr` at the bus edge does NOT detect this: by then a ce tick has
// usually already cleared it. The condition that matters is whether the core
// has *sampled* the strobe low since the last write was handed over, which is
// what `gap_done` tracks.
//
// Isolated writes must keep their original timing. Delaying every write by a ce
// tick leaves the FDC provably correct -- measured: no lost writes, no rejected
// commands, no register writes dropped on BUSY -- and still blanks Thexder,
// whose main/sub byte pump is timing-marginal. So the held slot engages only
// when a write really would be lost.
reg [1:0] acc_addr = 2'd0;
reg [7:0] acc_din  = 8'd0;
reg       acc_wr   = 1'b0;
reg       acc_rd   = 1'b0;

reg [1:0] pnd_addr = 2'd0;
reg [7:0] pnd_din  = 8'd0;
reg       pnd      = 1'b0;
reg       gap_done = 1'b1;   // the core has sampled `wr` low since the last write

always @(posedge CLKSYS) begin
  if (reset) begin
    acc_wr   <= 1'b0;
    acc_rd   <= 1'b0;
    pnd      <= 1'b0;
    gap_done <= 1'b1;
  end
  else begin
    if (core_sel & wr_stb) begin
      if (gap_done & ~acc_wr & ~pnd) begin
        acc_addr <= FD_RS[1:0];
        acc_din  <= FD_Din;
        acc_wr   <= 1'b1;
        gap_done <= 1'b0;
      end
      else begin
        pnd_addr <= FD_RS[1:0];
        pnd_din  <= FD_Din;
        pnd      <= 1'b1;
`ifdef DEBUG_FDC_SCAN
        $display("FDCP  reg%0d <- %02x held (would have been lost)", FD_RS[1:0], FD_Din);
`endif
      end
    end
    else if (ce_wd) begin
      if (acc_wr) acc_wr <= 1'b0;   // the core sampled it high this tick
      else begin
        gap_done <= 1'b1;           // the core sampled it low this tick
        if (pnd) begin              // safe to raise again: the low was observed
          acc_addr <= pnd_addr;
          acc_din  <= pnd_din;
          acc_wr   <= 1'b1;
          pnd      <= 1'b0;
          gap_done <= 1'b0;
        end
      end
    end

    if (core_sel & rd_stb) begin
      acc_addr <= FD_RS[1:0];
      acc_rd   <= 1'b1;
    end
    else if (ce_wd) acc_rd <= 1'b0;
  end
end

`ifdef DEBUG_FDC_SCAN
always @(posedge CLKSYS) begin
  if (core_sel & wr_stb) $display("FDCW reg%0d <- %02x", FD_RS[1:0], FD_Din);
end
`endif

//----------------------------------------------------------------------------
// FM-7 board registers, $fd1c-$fd1f (MAME fm7.cpp fdc_r/fdc_w cases 4-7)
//
//   4  side select   write bit 0; reads back as side | $fe
//   5  drive/motor   write: bits 1:0 drive, bit 7 motor. See below -- this one
//                    follows CSP, NOT MAME.
//   6  mode          FM-7 always reads $ff; writes only matter on FM77AV+
//   7  status        bit 7 = DRQ, bit 6 = INTRQ, rest 0
//
// $fd1d USED TO FOLLOW MAME AND THAT WAS WRONG. MAME's fdc_w case 5 is
//
//     m_fdc_drive = data;
//     if((data & 0x03) > 0x01) { m_fdc_drive = 0; }
//
// i.e. a drive number above 1 zeroes the WHOLE register, motor bit and all, and
// fdc_r case 5 hands that latch straight back. This core copied that.
//
// CSP does something quite different, and CSP is the primary authority for FM-7
// behaviour (TODO.md, "working practices" -- MAME's FM-7 driver is unreliable).
// Its write path takes the motor bit BEFORE any drive validation and never
// zeroes the register (floppy.cpp:221 `set_fdc_fd1d`), and its read path
// (floppy.cpp:178 `get_fdc_motor`) builds the value rather than echoing it:
//
//     uint8_t val = 0x3c;                 // bits 5:2 always set
//     val |= (fdc_drvsel & 0x03);         // drive number
//     fdc_motor = (fdc->read_signal(SIG_MB8877_MOTOR) != 0);
//     fdc_motor &= (fdc->get_drive_type(drv) != DRIVE_TYPE_UNK);
//     if(fdc_motor) val |= 0x80;          // bit 7 = LIVE motor state
//
// So bit 7 reports whether the motor is actually running, gated on a drive
// being present -- it is not an echo of what was written.
//
// This matters for real software. Ys writes $82 and $83 to $fd1d, i.e. drive 2
// and 3 with the motor bit set. Under the MAME rule the register became $00 and
// the motor bit vanished. Ys then polls a boot-ROM routine at $fef0 that copies
// $fd1d into $ffe5 and waits for bit 7:
//
//     $fef0  LDB  <$1d      DP=$fd, so $fd1d
//     $fef2  STB  $ffe5
//     ...
//     $1113  TST  $ffe5     Ys's wait loop
//     $1116  BMI  $1120     leave when the motor is running
//
// With bit 7 always zero that loop never exits -- 662045 iterations over 2000
// frames, and P4-8's "never enters its loaded program".
//
// `ready` is the drive-present term: it is the mount-and-scan-complete signal
// used everywhere else in this file, which is the closest thing here to CSP's
// `get_drive_type(drv) != DRIVE_TYPE_UNK`.
//----------------------------------------------------------------------------

reg       fdc_side  = 1'b0;
reg       fdc_motor = 1'b0;
reg [1:0] fdc_drv   = 2'd0;

wire drive0_sel = (fdc_drv == 2'd0);
wire drive1_sel = (fdc_drv == 2'd1);
wire ready0, ready1;
wire drq0, drq1, intrq0, intrq1;
wire ready_sel = drive0_sel ? ready0 : drive1_sel ? ready1 : 1'b0;
wire drq_sel   = drive0_sel ? drq0   : drive1_sel ? drq1   : 1'b0;
wire intrq_sel = drive0_sel ? intrq0 : drive1_sel ? intrq1 : 1'b0;

always @(posedge CLKSYS) begin
  if (reset) begin
    fdc_side  <= 1'b0;
    fdc_motor <= 1'b0;
    fdc_drv   <= 2'd0;
  end
  else if (aux_sel & wr_stb) begin
    case (FD_RS[1:0])
      2'd0: fdc_side <= FD_Din[0];
      2'd1: begin
        fdc_motor <= FD_Din[7];    // taken before any drive validation, per CSP
        fdc_drv   <= FD_Din[1:0];
      end
      default: ;
    endcase
  end
end

wire [7:0] aux_dout =
  (FD_RS[1:0] == 2'd0) ? { 7'h7f, fdc_side } :   // side | $fe
  // { motor&ready, 0, 1111, drive } == CSP's 0x3c | drive | (motor ? 0x80 : 0)
  (FD_RS[1:0] == 2'd1) ? { fdc_motor & ready_sel, 1'b0, 4'b1111, fdc_drv } :
  (FD_RS[1:0] == 2'd2) ? 8'hff :                 // mode: FM-7 always $ff
                         { drq_sel, intrq_sel, 6'd0 }; // status flags

//----------------------------------------------------------------------------
// The controller
//----------------------------------------------------------------------------

wire [7:0] core_dout0, core_dout1;
wire [31:0] sd_lba0, sd_lba1;
wire sd_rd0, sd_rd1, sd_wr0, sd_wr1;
wire [7:0] sd_buff_din0, sd_buff_din1;

// The drive is ready once an image is mounted AND the mount-time scan of that
// image has finished -- until then the sector table is still being built, and a
// seek would search a half-filled table. `prepare` is the controller's own
// "scan in progress"; it goes high a little after img_mounted falls, so the
// scan is tracked from the mount rather than from prepare alone.
//
// Write protect follows the OSD's read-only flag ONLY.
//
// A .d77 also carries its own write-protect byte at header offset $1a, and the
// scanner lifts it out as fmt_wp -- but it is deliberately NOT applied here.
// Neither reference emulator enforces it: MAME's d88 loader reads it into
// `tag->write_protect` (refs/mame/src/lib/formats/d88_dsk.cpp:351) and never
// looks at it again, and common-source-project does not read it at all.
//
// Enforcing it breaks real software. Thexder's image has $1a = $10, and its
// boot sector asks the boot ROM for a disk write; with write protect forced on,
// the ROM's error decoder at $ffad reads status $60, takes the "bit 6 -> error
// 11" branch, and the boot sector halts on `BRA $0340`. The disk is simply
// unbootable. fmt_wp is left exported in case it should one day become a
// default for an OSD toggle, but the byte records how the physical disk was
// dumped, not whether the emulated drive should refuse writes.
reg [1:0] mounted         = 2'b00;
reg [1:0] scanning        = 2'b00;
reg [1:0] prepare_seen    = 2'b00;
reg [1:0] wp_r            = 2'b11;
reg [1:0] old_img_mounted = 2'b00;
integer mount_i;

always @(posedge CLKSYS) begin
  if (reset) begin
    mounted         <= 2'b00;
    scanning        <= 2'b00;
    prepare_seen    <= 2'b00;
    wp_r            <= 2'b11;
    old_img_mounted <= 2'b00;
  end
  else begin
    old_img_mounted <= img_mounted;
    for (mount_i = 0; mount_i < 2; mount_i = mount_i + 1) begin
      if (img_mounted[mount_i]) begin
        mounted[mount_i]      <= |img_size;
        scanning[mount_i]     <= |img_size;
        prepare_seen[mount_i] <= 1'b0;
        if (~old_img_mounted[mount_i]) wp_r[mount_i] <= img_readonly;
      end
      else begin
        if ((mount_i == 0) ? prepare0 : prepare1)
          prepare_seen[mount_i] <= 1'b1;
        if (prepare_seen[mount_i] && ~((mount_i == 0) ? prepare0 : prepare1)) begin
          scanning[mount_i]     <= 1'b0;
          prepare_seen[mount_i] <= 1'b0;
        end
      end
    end
  end
end

assign ready0 = mounted[0] & ~scanning[0];
assign ready1 = mounted[1] & ~scanning[1];

// EDSK=1 compiles in the mount-time sector-table scanner, which is where the
// .d77 parser lives -- it fills the same edsk[]/spt[] structures the EDSK parser
// does, so the runtime path is shared. It must stay 1: with EDSK=0 there is no
// table at all, and Verilator additionally rejects the file (`spt_addr` is
// declared inside the generate block yet referenced outside it).
wd1793 #(.RWMODE(1), .EDSK(1)) u_wd1793_0
(
  .clk_sys      ( CLKSYS            ),
  .ce           ( ce_wd             ),
  .reset        ( reset             ),
  // io_en is folded into acc_rd/acc_wr, which are only ever set for a selected
  // access to $fd18-$fd1b.
  .io_en        ( 1'b1              ),
  .rd           ( acc_rd & drive0_sel ),
  .wr           ( acc_wr & drive0_sel ),
  .addr         ( acc_addr          ),
  .din          ( acc_din           ),
  .dout         ( core_dout0        ),
  .drq          ( drq0              ),
  .intrq        ( intrq0            ),
  .busy         (                   ),

  .wp           ( wp_r[0]           ),
  .fmt_wp       (                   ),
  .size_code    ( 3'd1              ),  // 256-byte sectors, the FM-7 2D norm
  .layout       ( 1'b0              ),  // Track-Side-Sector
  .side         ( fdc_side          ),
  .ready        ( ready0            ),

  // SD block interface (RWMODE 1). img_size is 20 bits in the core: 1 MB max,
  // which covers 2D (320-360 KB) and 2DD .d77 images comfortably.
  .img_mounted  ( img_mounted[0]    ),
  .img_size     ( img_size[19:0]    ),
  .prepare      ( prepare0          ),
  .sd_lba       ( sd_lba0           ),
  .sd_rd        ( sd_rd0            ),
  .sd_wr        ( sd_wr0            ),
  .sd_ack       ( sd_ack[0]         ),
  .sd_buff_addr ( sd_buff_addr      ),
  .sd_buff_dout ( sd_buff_dout      ),
  .sd_buff_din  ( sd_buff_din0      ),
  .sd_buff_wr   ( sd_buff_wr        ),

  // RAM buffer interface: unused with RWMODE 1.
  .input_active ( 1'b0              ),
  .input_addr   ( 20'd0             ),
  .input_data   ( 8'd0              ),
  .input_wr     ( 1'b0              ),
  .buff_addr    (                   ),
  .buff_read    (                   ),
  .buff_din     ( 8'd0              )
);

wd1793 #(.RWMODE(1), .EDSK(1)) u_wd1793_1
(
  .clk_sys      ( CLKSYS            ),
  .ce           ( ce_wd             ),
  .reset        ( reset             ),
  .io_en        ( 1'b1              ),
  .rd           ( acc_rd & drive1_sel ),
  .wr           ( acc_wr & drive1_sel ),
  .addr         ( acc_addr          ),
  .din          ( acc_din           ),
  .dout         ( core_dout1        ),
  .drq          ( drq1              ),
  .intrq        ( intrq1            ),
  .busy         (                   ),
  .wp           ( wp_r[1]           ),
  .fmt_wp       (                   ),
  .size_code    ( 3'd1              ),
  .layout       ( 1'b0              ),
  .side         ( fdc_side          ),
  .ready        ( ready1            ),
  .img_mounted  ( img_mounted[1]    ),
  .img_size     ( img_size[19:0]    ),
  .prepare      ( prepare1          ),
  .sd_lba       ( sd_lba1           ),
  .sd_rd        ( sd_rd1            ),
  .sd_wr        ( sd_wr1            ),
  .sd_ack       ( sd_ack[1]         ),
  .sd_buff_addr ( sd_buff_addr      ),
  .sd_buff_dout ( sd_buff_dout      ),
  .sd_buff_din  ( sd_buff_din1      ),
  .sd_buff_wr   ( sd_buff_wr        ),
  .input_active ( 1'b0              ),
  .input_addr   ( 20'd0             ),
  .input_data   ( 8'd0              ),
  .input_wr     ( 1'b0              ),
  .buff_addr    (                   ),
  .buff_read    (                   ),
  .buff_din     ( 8'd0              )
);

assign sd_lba[0]      = sd_lba0;
assign sd_lba[1]      = sd_lba1;
assign sd_rd[0]       = sd_rd0;
assign sd_rd[1]       = sd_rd1;
assign sd_wr[0]       = sd_wr0;
assign sd_wr[1]       = sd_wr1;
assign sd_buff_din[0] = sd_buff_din0;
assign sd_buff_din[1] = sd_buff_din1;

wire [7:0] core_dout = drive0_sel ? core_dout0 :
                       drive1_sel ? core_dout1 : 8'hff;
wire drq = drq_sel;
wire intrq = intrq_sel;

assign FD_Dout   = FD_RS[2] ? aux_dout : core_dout;
assign FD_DRQn   = ~drq;
assign FD_INTRQn = ~intrq;

endmodule
