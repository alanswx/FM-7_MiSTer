// FM77AV main-memory front end.
//
// The AV presents a 256 KB physical space through a 64 KB 6809 address bus.
// At reset MMR is disabled and the FM-7 machine lives at physical $30000. The
// initiator and F-BASIC ROM overlays are selected by ROMS.v; this block owns
// the RAM, boot-RAM seed, MMR registers, and TWR window.

module AVMEM(
  input        CLKSYS,
  input        RESETBn,
  input        machine_av,
  input  [1:0] bootrom_sel,
  input        FBASIC_ROM_SEL,
  input [15:0] MADDRBUS,
  input  [7:0] DIN,
  input        RWBn,
  input        WTQEn,
  input        RDQEn,
  input  [13:0] VRAM_OFFSET,
  input  [7:0] VRAM_DOUT,
  input  [7:0] SHARED_DOUT,
  input  [12:0] SUBRAM_ADDR,
  input        SUBRAM_WRITE,
  input  [7:0] SUBRAM_DIN,
  input        SUBMON_STATUS_CLEAR,
  input        SHALTn,
  input        SVSYNCn,
  input        SBLANKn,
  input        VBLANKn,
  output [7:0] SUBRAM_DOUT,
  output [7:0] DOUT,
  output reg [7:0] IODOUT,
  output       IOSEL,
  output       TWRSEL,
  output       INITROM_EN,
  output [1:0] SUBMON_SEL,
  output       SUBMON_RESET,
  output       SUBMON_STATUS,
  output       AV_MODE_320,
  output       VRAM_SEL,
  output [1:0] VRAM_PLANE,
  output [13:0] VRAM_ADDR,
  output       VRAM_WRITE,
  output       VRAM_READ,
  output [7:0] VRAM_DIN,
  output       SHARED_SEL,
  output [9:0] SHARED_ADDR,
  output       SHARED_WRITE,
  output [7:0] SHARED_DIN,
  output       SUBIO_SEL,
  output [7:0] SUBIO_ADDR,
  output       SUBIO_WRITE,
  output [7:0] SUBIO_DIN,
  input  [7:0] SUBIO_DOUT,
  output        FM7PAGE_SEL,
  output [15:0] FM7PAGE_ADDR,
  output        FM7PAGE_WRITE,
  input   [7:0] FM7PAGE_DOUT,
  // For the clock mux: the AV main CPU drops from 2 MHz to 1.6 MHz while MMR
  // is enabled (FM-Techknow p.334).
  output        MMR_ENABLED
);

reg av_mode_320;
wire mode_io_sel = machine_av && (MADDRBUS == 16'hfd12);
wire io_sel = machine_av && (((MADDRBUS >= 16'hfd80) && (MADDRBUS <= 16'hfd93)) ||
                             mode_io_sel);
wire submon_io_sel = machine_av && (MADDRBUS == 16'hfd13);
// $FD10 bit 1 = 1 removes the initiator ROM overlay from $6000-$7FFF (and the
// reset-vector bytes), leaving RAM there. It is write-only -- neither CSP nor
// 77AVEMU has a read handler -- so it is deliberately NOT part of io_sel,
// which drives the $FDxx read mux.
wire initrom_io_sel = machine_av && (MADDRBUS == 16'hfd10);
assign IOSEL = io_sel;
assign AV_MODE_320 = av_mode_320;

wire bootram_sel = machine_av &&
                   (MADDRBUS >= 16'hfe00) && (MADDRBUS < 16'hffe0);

// Base AV has four MMR segments and 16 six-bit bank registers per segment.
// The register value is physical A17:A12. Reset values are irrelevant while
// MMR is disabled, but are defined as zero to match 77AVEMU/CSP.
reg [5:0] mmr [0:3][0:15];
reg [1:0] mmr_segment;
reg [7:0] twr_address;
reg       mmr_enable;
assign MMR_ENABLED = mmr_enable;

`ifdef DEBUG_MMR
// Dump all four segment maps whenever one changes. The counterpart of
// FM77AV_MMR_DUMP in tools/77avemu_headless.cpp.
//
// A $FD8x write lands in whichever segment $FD90 currently selects, so two
// machines can emit identical $FD8x and $FD90 VALUE sequences and still end
// up with different segment maps if the interleaving differs. Comparing the
// write streams cannot see that; only the maps can. Luxsor disk 1 is the case
// -- its logical $6xxx points at the loader here and at never-written physical
// RAM on the reference, with every register value sequence agreeing.
integer dbg_s, dbg_p;
reg [5:0] dbg_prev [0:3][0:15];
reg dbg_diff;
always @(posedge CLKSYS) begin
  dbg_diff = 1'b0;
  for (dbg_s = 0; dbg_s < 4; dbg_s = dbg_s + 1)
    for (dbg_p = 0; dbg_p < 16; dbg_p = dbg_p + 1)
      if (mmr[dbg_s][dbg_p] !== dbg_prev[dbg_s][dbg_p]) dbg_diff = 1'b1;
  if (dbg_diff) begin
    $write("MMRMAP en=%0d seg=%0d", mmr_enable, mmr_segment);
    for (dbg_s = 0; dbg_s < 4; dbg_s = dbg_s + 1) begin
      $write(" | s%0d:", dbg_s);
      for (dbg_p = 0; dbg_p < 16; dbg_p = dbg_p + 1) $write(" %02x", mmr[dbg_s][dbg_p]);
    end
    $display("");
  end
  for (dbg_s = 0; dbg_s < 4; dbg_s = dbg_s + 1)
    for (dbg_p = 0; dbg_p < 16; dbg_p = dbg_p + 1)
      dbg_prev[dbg_s][dbg_p] <= mmr[dbg_s][dbg_p];
end
`endif
reg       twr_enable;
reg       bootram_write_enable;
reg [1:0] submon_sel;
reg [7:0] submon_reset_count;
reg       submon_status;
// The initiator ROM overlay. On at reset (77AVEMU fm77avmemory.cpp:471
// `state.avBootROM=true` for MACHINETYPE_FM77AV and up; CSP's initiator_enabled
// likewise), removed by $FD10 bit 1.
//
// It used to be permanently on, which is invisible until a title loads code
// into the RAM under it and jumps there. Ys does exactly that: its second-stage
// loader reads a file into $6000-$7FFF and calls it through a vector, and with
// the overlay stuck on the CPU ran the initiator's cold-boot code instead --
// re-seeding boot RAM and restarting the $5000 loader. The sub CPU, still
// running the game's own downloaded dispatcher, then never answered the
// monitor-protocol block the restarted loader wrote to the shared window, and
// both CPUs waited on each other forever.
reg       initrom_enable;
assign INITROM_EN = initrom_enable;
assign SUBMON_SEL = submon_sel;
assign SUBMON_RESET = (submon_reset_count != 8'd0);
assign SUBMON_STATUS = submon_status;

wire twr_sel = machine_av && twr_enable &&
               (MADDRBUS >= 16'h7c00) && (MADDRBUS < 16'h8000);
assign TWRSEL = twr_sel;
wire initiator_sel = machine_av && initrom_enable &&
                     (((MADDRBUS >= 16'h6000) && (MADDRBUS < 16'h8000)) ||
                      (MADDRBUS >= 16'hfffe));
wire fbasic_sel = FBASIC_ROM_SEL;

wire av_write = machine_av && ~WTQEn;
wire bootram_write = av_write && bootram_sel && bootram_write_enable;
wire mmr_write = av_write && (io_sel || submon_io_sel || initrom_io_sel);

// TWR maps the 1 KB window at $7c00-$7fff into page zero. MMR is checked only
// below $fc00; the entire $fc00-$ffff range stays on the physical FM77AV page.
//
// $FD92 is an OFFSET ADDED TO THE CPU ADDRESS, not a base address: with the
// register at 0 the window sits over physical $07c00, not $00000. Both
// references say so, and independently. 77AVEMU builds
// `TWRAddr = (data<<8) + 0x7C00` and translates `(TWRAddr + (addr & 0x3FF))
// & 0xFFFF` (memory/fm77avmemory.cpp:1239-1243, memory/fm77avmemory.h:348-351;
// its own comment reads "Experiment indicated TWR address 0 will map physical
// 0x07C00 to main CPU memory space 0x7C00"). CSP computes
// `((window_offset * 256) + addr) & 0x0ffff` over the FULL logical address and
// returns FM7_MAINMEM_AV_PAGE0 (fm7/mainmem_mmr.cpp:16-22). Both wrap at 64 KB,
// so the window can never leave RAM page 0.
//
// This used to drop the $7c00, which put every window 31 KB too low. It is
// invisible until one title both banks code into low RAM page 0 AND uses the
// window. FM Sound Editor does exactly that: it copies 4 KB to physical
// $00000 through MMR page 8 at frame 22, then from frame 221 walks an
// $ff-write / read-back / $00-write RAM-size probe through the window from
// register $00 to $70. On the reference that probe covers $07c00-$0efff; here
// it started at $00000 and erased the code, so the trampoline's later
// `JSR $8000` into that bank ran 4 KB of zeroes as a `NEG <$00` sled.
reg [17:0] physical_address;
wire [15:0] twr_physical = {twr_address, 8'd0} + MADDRBUS;   // wraps at 64 KB
always @* begin
  if (twr_enable && (MADDRBUS >= 16'h7c00) && (MADDRBUS < 16'h8000))
    physical_address = {2'b00, twr_physical};
  else if (mmr_enable && (MADDRBUS < 16'hfc00))
    physical_address = {mmr[mmr_segment][MADDRBUS[15:12]], MADDRBUS[11:0]};
  else
    physical_address = 18'h30000 + {2'b00, MADDRBUS};
end

// The AV's physical $10000-$1BFFF range is the three 16 KB video planes.
// MMR maps this aperture into the main CPU address space; it is not ordinary
// RAM and must stay coherent with the raster/sub-CPU VRAM store.
// The main CPU only reaches the sub system while the sub CPU is HALTED.
//
// 77AVEMU discards a main-CPU access to physical $10000-$1FFFF whenever the sub
// CPU is running -- a read returns $FF (`fm77avmemory.cpp:737-742`) and a store
// is dropped (`:805-810`). CSP states the same rule the other way round
// (`mainmem_readseq.cpp` `read_direct_access`). The sub I/O aperture below
// already carries this gate; the VRAM aperture did not.
//
// It matters most for the ALU trigger. Once a main-CPU VRAM *read* arms the
// drawing ALU, any ordinary main-CPU read that happens to land in a mapped VRAM
// page fires a paint -- so on a title whose sub CPU is running, an access the
// reference machine answers with $FF instead scribbles a tile into VRAM.
//
// SHALTn is active low: ~SHALTn means halted.
wire sub_open = ~SHALTn;
wire vram_addr_sel = machine_av &&
                     (physical_address >= 18'h10000) &&
                     (physical_address < 18'h1c000);
wire vram_sel = vram_addr_sel && sub_open;
assign VRAM_SEL   = vram_sel;
assign VRAM_PLANE = physical_address[15:14]; // 0=B, 1=R, 2=G
// 77AVEMU's TransformVRAMAddress preserves the plane/page high bits while
// wrapping the low address at 8 KB in 320x200 mode (16 KB in 640x200 mode).
// VRAM_OFFSET is the existing sub-system display offset, so main-CPU MMR
// accesses follow the same scroll transform as the reference machine.
wire [13:0] vram_addr_raw = physical_address[13:0];
wire [13:0] vram_addr_640 = vram_addr_raw + VRAM_OFFSET;
wire [13:0] vram_addr_320 = {vram_addr_raw[13],
                             vram_addr_raw[12:0] + VRAM_OFFSET[12:0]};
assign VRAM_ADDR  = av_mode_320 ? vram_addr_320 : vram_addr_640;
assign VRAM_WRITE = av_write && vram_sel;
// The main CPU's VRAM READ through the same aperture.
//
// This is the drawing ALU's *normal* trigger, not an exotic one: 77AVEMU takes
// the hardware-draw path on every read of MEMTYPE_SUBSYS_VRAM
// (fm77avmemory.cpp:746-750 -> FM77AVCRTC::VRAMDummyRead) and its own comment on
// the write path calls the dummy READ the supposed form, with the write a Pro
// Baseball Fan quirk. Woody Poco uses the read form exclusively -- 53311 reads
// and not one write through this aperture over 300 frames -- so with only the
// write trigger wired its ALU fired zero times and VRAM stayed at 8 non-zero
// bytes for the whole run.
//
// RDQEn is ~(RWB & (QB|EB)), one contiguous low window per read bus cycle, so
// the edge detector in AVHDRAW gets exactly one trigger per access.
assign VRAM_READ  = ~RDQEn && vram_sel;
`ifdef DEBUG_AVDRAW
// Does the main CPU reach VRAM through the MMR aperture at all, and by read or
// by write? 77AVEMU's MEMTYPE_SUBSYS_VRAM store comments that hardware drawing
// is "supposed to be dummy-READ", with the write form a Pro Baseball Fan quirk.
// Both the gated strobes and what they WOULD have been without the sub-halt
// gate, so a run can say how many accesses the gate actually blocked. A gate
// that blocks nothing and a gate that is not in the build look identical from
// the outside (REFERENCE.md trap 3).
reg av_vr_d, av_vw_d, av_ur_d, av_uw_d;
wire av_ungated_rd = vram_addr_sel && ~RDQEn;
wire av_ungated_wr = vram_addr_sel && av_write;
always @(posedge CLKSYS) begin
  av_vr_d <= VRAM_READ;
  av_vw_d <= VRAM_WRITE;
  av_ur_d <= av_ungated_rd;
  av_uw_d <= av_ungated_wr;
  if (VRAM_READ & ~av_vr_d)
    $display("AVMEM VR phys=$%05x addr=$%04x", physical_address, VRAM_ADDR);
  if (VRAM_WRITE & ~av_vw_d)
    $display("AVMEM VW phys=$%05x addr=$%04x", physical_address, VRAM_ADDR);
  if (av_ungated_rd & ~av_ur_d & ~sub_open)
    $display("AVMEM BR phys=$%05x", physical_address);
  if (av_ungated_wr & ~av_uw_d & ~sub_open)
    $display("AVMEM BW phys=$%05x", physical_address);
end
`endif
assign VRAM_DIN   = DIN;

// The AV has a 128-byte shared command window.  The sub CPU sees it at
// $d380-$d3ff; the main CPU sees the same bytes at the un-translated $fc80-
// $fcff aperture (physical $3fc80-$3fcff).  Keep this separate from the
// ordinary sub-system RAM at physical $1d000-$1d37f.
wire shared_sel = machine_av &&
                  (physical_address >= 18'h3fc80) &&
                  (physical_address < 18'h3fd00);
// THE MAIN CPU REACHES THE SHARED WINDOW ONLY WHILE THE SUB CPU IS HALTED.
// It is dual-ported RAM with one arbiter, and that arbiter is the halt: with the
// sub running, a main-CPU read of $FC80-$FCFF returns $FF and a write is
// discarded. Both references say so, independently and in the same words --
// 77AVEMU `memory/fm77avmemory.cpp:640-645` (read: `if(subSysHalt) return
// state.data[SUBSYS_SHARED_RAM_BEGIN+(addr&0x7F)]; return 0xFF;`) and `:928-933`
// (write: `if(subSysHalt) ...; return;`), and CSP `fm7/mainmem_readseq.cpp:145-150`
// / `mainmem_writeseq.cpp:29-34` (`if(!sub_halted) return 0xff;` / `return;`).
//
// This core already applied that rule to the VRAM aperture and the sub I/O page
// and missed it here, on the one window every F-BASIC sub call goes through.
//
// Software PROBES it. Mahjong Kyou Jidai Special disk 1 asks whether the sub is
// running by writing the window and reading it back:
//
//   $1efd  CLR $fc80      ; discarded while the sub runs
//   $1f00  LDA $fc80      ; $FF there, $00 here
//   $1f03  BEQ $1f14      ; zero -> "window is open, sub already halted", skip
//   $1f05..$1f13          ; ...the wait-and-halt this core therefore skipped
//
// It then drove the drawing ALU through the MMR aperture with the sub still
// running, so that aperture -- correctly gated -- dropped the writes: 211 line
// triggers issued and 10 landed, and the title's background fill never happened.
assign SHARED_SEL   = shared_sel;
assign SHARED_ADDR  = 10'h380 + {3'd0, physical_address[6:0]};
assign SHARED_WRITE = av_write && shared_sel && sub_open;
assign SHARED_DIN   = DIN;

// The sub-system I/O page is physical $1D400-$1D4FF, i.e. sub $D400-$D4FF.
// MMR puts it in reach of the main CPU, and the 2019 AV demo uses that:
// it halts the sub CPU and then writes $D430 (the VRAM access/display page)
// and $D410 (the drawing ALU command) itself.  Without this the demo's
// second bit-plane pair is never selected and every gradient byte lands on
// top of the first, which is a screen of vertical bars instead of a
// 4096-colour ramp.  77AVEMU routes the same window
// (`fm77avmemory.h:76-77` and `fm77avmemory.cpp:804-825`).
wire subio_sel = machine_av &&
                 (physical_address >= 18'h1d400) &&
                 (physical_address < 18'h1d500);
assign SUBIO_SEL   = subio_sel;
assign SUBIO_ADDR  = physical_address[7:0];
assign SUBIO_WRITE = av_write && subio_sel;
assign SUBIO_DIN   = DIN;

// ROM and boot-RAM windows do not write the physical RAM array. The AV F-BASIC
// ROM is not shadowed by this first backend; boot RAM has its explicit $FD93
// bit-0 write enable.
// MMR overrides the normal ROM overlay when it translates the CPU window to
// physical RAM, while physical ROM and I/O ranges remain protected.
wire mmr_ram_sel = mmr_enable && (MADDRBUS < 16'hfc00) &&
                    ((physical_address < 18'h10000) ||
                     ((physical_address >= 18'h1c000) &&
                      (physical_address < 18'h1d380)) ||
                     ((physical_address >= 18'h20000) &&
                      (physical_address < 18'h36000)));
wire ram_write = av_write && !io_sel && !bootram_sel && !vram_sel &&
                 !shared_sel && !subio_sel && (MADDRBUS < 16'hfffe) &&
                 (mmr_ram_sel || ((!initiator_sel || twr_sel) && !fbasic_sel));
// The 256 KB physical space is not 256 KB of RAM. Backing all of it with one
// `dpram #(8,18)` cost 2,097,152 block-memory bits -- a third of the whole
// design's memory, on a device the design already overflows -- and most of it
// was never readable or writable:
//
//   $00000-$0FFFF  RAM page 0                              -- kept, block A
//   $10000-$1BFFF  the three VRAM planes                   -- CRTRAM owns these
//   $1C000-$1D37F  sub-system RAM                          -- kept, block B
//   $1D380-$1D3FF  shared window          -- SRAM.v owns it
//   $1D400-$1D4FF  sub I/O                -- registers, not memory
//   $1D800-$1FFFF  font and monitor ROM   -- SMEM.v owns these
//   $20000-$2FFFF  RAM page 1                              -- kept, block C
//   $30000-$3FFFF  the FM-7 machine (RAM low, ROM high)    -- kept, block C
//
// Dropping the two holes takes it to 200 KB. `ram_write` above already encodes
// the same map, so nothing that could be written loses its storage; the reads
// that fall in a hole are answered by the owning module through DOUT's mux.
//
// Physical $1C000-$1D37F is ordinary AV sub-system RAM: C000-CFFF is 4 KB
// and D000-D37F is the adjacent 896-byte page before the shared window. It is
// the only region the sub CPU reaches directly, so block B is the dual-ported
// one and blocks A and C need a single port each.
// Physical $30000-$3FFFF is "the FM-7 machine", and this core already has that
// machine's 64 KB as MRAM -- which sits completely idle in AV mode, because
// MAINRAM_dout selects AVMEM_dout there. Backing the page twice cost 64 M10K
// on a device the design overflows by 137, so AV mode borrows MRAM for it and
// av_ram_hi covers only RAM page 1. FM-7 mode is untouched: it reaches MRAM
// the way it always did.
wire blk_a_sel = (physical_address[17:16] == 2'b00);      // $00000-$0FFFF
wire blk_b_sel = (physical_address[17:13] == 5'b01110);   // $1C000-$1DFFF
wire blk_c_sel = (physical_address[17:16] == 2'b10);      // $20000-$2FFFF
wire blk_d_sel = (physical_address[17:16] == 2'b11);      // $30000-$3FFFF -> MRAM
assign FM7PAGE_SEL   = machine_av && blk_d_sel;
assign FM7PAGE_ADDR  = physical_address[15:0];
assign FM7PAGE_WRITE = ram_write && blk_d_sel;

wire [7:0] blk_a_q, blk_b_q, blk_c_q;

// q is registered, so the read mux has to follow the select the address had
// when the RAM latched it, not the one the bus has moved on to.
reg [2:0] ram_sel_d;
always @(posedge CLKSYS)
  ram_sel_d <= blk_a_sel ? 3'd0 : blk_b_sel ? 3'd1 :
               blk_c_sel ? 3'd2 : blk_d_sel ? 3'd3 : 3'd4;

// MRAM's own output is registered on the same clock, so it lines up with the
// three local blocks and needs no extra delay here.
wire [7:0] ram_q = (ram_sel_d == 3'd0) ? blk_a_q :
                   (ram_sel_d == 3'd1) ? blk_b_q :
                   (ram_sel_d == 3'd2) ? blk_c_q :
                   (ram_sel_d == 3'd3) ? FM7PAGE_DOUT : 8'hff;

dpram #(8,16) av_ram_lo(                                  // $00000-$0FFFF
  .clock     ( CLKSYS                    ),
  .address_a ( physical_address[15:0]    ),
  .data_a    ( DIN                       ),
  .wren_a    ( ram_write && blk_a_sel    ),
  .q_a       ( blk_a_q                   ),
  .address_b ( 16'd0 ), .data_b ( 8'd0 ), .wren_b ( 1'b0 ), .q_b ()
);

dpram #(8,13) av_ram_sub(                                 // $1C000-$1DFFF
  .clock     ( CLKSYS                    ),
  .address_a ( physical_address[12:0]    ),
  .data_a    ( DIN                       ),
  .wren_a    ( ram_write && blk_b_sel    ),
  .q_a       ( blk_b_q                   ),
  .address_b ( SUBRAM_ADDR               ),
  .data_b    ( SUBRAM_DIN                ),
  .wren_b    ( SUBRAM_WRITE              ),
  .q_b       ( SUBRAM_DOUT               )
);

dpram #(8,16) av_ram_hi(                                  // $20000-$2FFFF
  .clock     ( CLKSYS                    ),
  .address_a ( physical_address[15:0]    ),
  .data_a    ( DIN                       ),
  .wren_a    ( ram_write && blk_c_sel    ),
  .q_a       ( blk_c_q                   ),
  .address_b ( 16'd0 ), .data_b ( 8'd0 ), .wren_b ( 1'b0 ), .q_b ()
);

// The 480-byte loader is copied from initiate.rom[$1800/$1a00] by the real
// machine at reset. Keeping the two mode images separate makes the OSD's DOS
// boot selection deterministic while preserving the AV rule that this is RAM
// after $FD93 bit 0 is enabled.
reg [7:0] boot_basic [0:479];
reg [7:0] boot_dos   [0:479];
initial begin
  $readmemh("./roms/fm77av_boot_basic.rom.mem", boot_basic);
  $readmemh("./roms/fm77av_boot_dos.rom.mem",   boot_dos);
end

wire [8:0] boot_offset = MADDRBUS[8:0];
wire [7:0] boot_q = (boot_offset < 9'd480) ?
                    (bootrom_sel[1] ? boot_dos[boot_offset] :
                                      boot_basic[boot_offset]) : 8'hff;

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    mmr_segment         <= 2'd0;
    twr_address         <= 8'd0;
    mmr_enable          <= 1'b0;
    twr_enable          <= 1'b0;
    bootram_write_enable <= 1'b0;
    av_mode_320         <= 1'b0;
    submon_sel          <= 2'd0; // Type C monitor
    submon_reset_count  <= 8'd0;
    submon_status       <= 1'b0;
    initrom_enable      <= 1'b1;
    mmr[0][0] <= 6'd0; mmr[0][1] <= 6'd0; mmr[0][2] <= 6'd0; mmr[0][3] <= 6'd0;
    mmr[0][4] <= 6'd0; mmr[0][5] <= 6'd0; mmr[0][6] <= 6'd0; mmr[0][7] <= 6'd0;
    mmr[0][8] <= 6'd0; mmr[0][9] <= 6'd0; mmr[0][10] <= 6'd0; mmr[0][11] <= 6'd0;
    mmr[0][12] <= 6'd0; mmr[0][13] <= 6'd0; mmr[0][14] <= 6'd0; mmr[0][15] <= 6'd0;
    mmr[1][0] <= 6'd0; mmr[1][1] <= 6'd0; mmr[1][2] <= 6'd0; mmr[1][3] <= 6'd0;
    mmr[1][4] <= 6'd0; mmr[1][5] <= 6'd0; mmr[1][6] <= 6'd0; mmr[1][7] <= 6'd0;
    mmr[1][8] <= 6'd0; mmr[1][9] <= 6'd0; mmr[1][10] <= 6'd0; mmr[1][11] <= 6'd0;
    mmr[1][12] <= 6'd0; mmr[1][13] <= 6'd0; mmr[1][14] <= 6'd0; mmr[1][15] <= 6'd0;
    mmr[2][0] <= 6'd0; mmr[2][1] <= 6'd0; mmr[2][2] <= 6'd0; mmr[2][3] <= 6'd0;
    mmr[2][4] <= 6'd0; mmr[2][5] <= 6'd0; mmr[2][6] <= 6'd0; mmr[2][7] <= 6'd0;
    mmr[2][8] <= 6'd0; mmr[2][9] <= 6'd0; mmr[2][10] <= 6'd0; mmr[2][11] <= 6'd0;
    mmr[2][12] <= 6'd0; mmr[2][13] <= 6'd0; mmr[2][14] <= 6'd0; mmr[2][15] <= 6'd0;
    mmr[3][0] <= 6'd0; mmr[3][1] <= 6'd0; mmr[3][2] <= 6'd0; mmr[3][3] <= 6'd0;
    mmr[3][4] <= 6'd0; mmr[3][5] <= 6'd0; mmr[3][6] <= 6'd0; mmr[3][7] <= 6'd0;
    mmr[3][8] <= 6'd0; mmr[3][9] <= 6'd0; mmr[3][10] <= 6'd0; mmr[3][11] <= 6'd0;
    mmr[3][12] <= 6'd0; mmr[3][13] <= 6'd0; mmr[3][14] <= 6'd0; mmr[3][15] <= 6'd0;
  end
  else begin
    if (submon_reset_count != 8'd0)
      submon_reset_count <= submon_reset_count - 8'd1;

    // $D430 bit 0 reports that a sub-monitor switch reset occurred.  The
    // flag is cleared by reading $D430, as in 77AVEMU's subROMSwitch latch.
    if (SUBMON_STATUS_CLEAR)
      submon_status <= 1'b0;

    if (mmr_write) begin
      case (MADDRBUS[7:0])
      // CSP fm7_mainio.cpp:1603 `flag = ((data & 0x02) == 0)`;
      // 77AVEMU fm77avmemory.cpp:325 `state.avBootROM=(0==(data&2))`.
      8'h10: initrom_enable <= ~DIN[1];
      8'h12: av_mode_320 <= DIN[6];
      8'h80, 8'h81, 8'h82, 8'h83,
      8'h84, 8'h85, 8'h86, 8'h87,
      8'h88, 8'h89, 8'h8a, 8'h8b,
      8'h8c, 8'h8d, 8'h8e, 8'h8f:
        mmr[mmr_segment][MADDRBUS[3:0]] <= DIN[5:0];
      8'h90: mmr_segment <= DIN[1:0];
      8'h92: twr_address <= DIN;
      8'h93: begin
        mmr_enable           <= DIN[7];
        twr_enable           <= DIN[6];
        bootram_write_enable <= DIN[0];
      end
      8'h13: begin
        // 0=C, 1=A, 2=B, 4=RAM on AV40. The base AV has no RAM monitor
        // bank, so retain Type C for unsupported values.
        case (DIN[2:0])
          3'd1: submon_sel <= 2'd1;
          3'd2: submon_sel <= 2'd2;
          default: submon_sel <= 2'd0;
        endcase
        if ((DIN[2:0] == 3'd1 && submon_sel != 2'd1) ||
            (DIN[2:0] == 3'd2 && submon_sel != 2'd2) ||
            ((DIN[2:0] != 3'd1 && DIN[2:0] != 3'd2) && submon_sel != 2'd0))
          submon_status <= 1'b1;
        // The real AV resets the sub-system on every write, including a
        // write that selects the already-active monitor bank.
        submon_reset_count <= 8'hff;
      end
      default: ;
      endcase
    end

    if (bootram_write)
      if (bootrom_sel[1]) boot_dos[boot_offset] <= DIN;
      else                 boot_basic[boot_offset] <= DIN;
  end
end

always @* begin
  case (MADDRBUS[7:0])
    // $FD12 is not just the mode latch: bit 0 is VSYNC and bit 1 is DISPLAY,
    // and titles wait on them. 77AVEMU spells out both senses
    // (fm77avcrtc.cpp:238-257): base $BF, `if(!InVSYNC) &= 0xFE` so bit 0 is 1
    // DURING vsync, and `if(InBlank) &= 0xFD` so bit 1 is 0 while blanking.
    // CSP drives the same two bits from SIG_DISPLAY_VSYNC and
    // SIG_DISPLAY_DISPLAY (fm7_mainio.cpp:1095-1108).
    //
    // This read used to be a constant, so bits 1:0 were always 11 -- a state
    // that never occurs on real hardware. Woody Poco halts the sub CPU, then
    // spins on `LDA $fd12 / ANDA #$03 / DECA / BNE` waiting for 01, i.e. vsync
    // with the display off, which is the ordinary way to wait for vblank before
    // drawing. It never arrived, so the main span forever in that four
    // instruction loop.
    //
    // The DISPLAY bit needs VERTICAL blanking, and that is the subtlety.
    // 77AVEMU's InBlank() is `InVBLANK() || InHSYNC()` (fm77avcrtc.h:136-139),
    // and InVSYNC() is a sub-interval of that same vertical period. SBLANKn --
    // which drives $D430 bit 7 -- is HORIZONTAL only, so using it alone
    // produced a machine that was never in vblank and vsync together: the read
    // returned $ff, $fe and $fc but never the $fd the title waits for.
    //
    // Do NOT "correct" the horizontal half to SHSYNCn to match the name of
    // 77AVEMU's InHSYNC(). Despite the name that function is the horizontal
    // BLANKING interval, not the sync pulse: `intoLine > CRT_HORIZONTAL_DURATION`
    // with 39.7 us active out of a 63.5 us line (fm77avcrtc.cpp:166-175,
    // fm77avcrtc.h:84-85), i.e. 62.5% active -- exactly the 640 of 1024 that
    // HBLANKn gives here. The two already agree; swapping in SHSYNCn would make
    // the bit read "blanking" for 6% of each line instead of 37.5%.
    8'h12: IODOUT = { 1'b1, av_mode_320, 4'b1111,
                      ~(~VBLANKn | ~SBLANKn), ~SVSYNCn };
    8'h80, 8'h81, 8'h82, 8'h83,
    8'h84, 8'h85, 8'h86, 8'h87,
    8'h88, 8'h89, 8'h8a, 8'h8b,
    8'h8c, 8'h8d, 8'h8e, 8'h8f:
      IODOUT = {2'b00, mmr[mmr_segment][MADDRBUS[3:0]]};
    // $FD93 is R/W (haserin09 difference.html, the FD93 mode-select row:
    // b7 MMR 0=off/1=on, b6 window 0=off/1=on, b0 boot RAM 0=RO/1=R/W on the
    // AV series, everything else unused, all three reset to 0).
    //
    // Bit 0 must report the LATCH, not a constant. 77AVEMU builds the same
    // `0x3f | mmr | twr` and then clears bit 0 when the boot area is ROM
    // (fm77avio.cpp:959-971 over fm77avmemory.cpp:1304-1310). Returning a
    // hard 1 here is invisible until a title read-modify-writes this register,
    // which Woody Poco does 2355 times: it reads $fd93, sets bit 7 and writes
    // back, so our stale bit 0 rode along and left boot RAM permanently
    // writable ($bf written where the reference writes $be).
    8'h93: IODOUT = 8'h3e | {7'b0, bootram_write_enable} |
                         (mmr_enable ? 8'h80 : 8'h00) |
                         (twr_enable ? 8'h40 : 8'h00);
    default: IODOUT = 8'hff;
  endcase
end

// The sub I/O aperture is readable, not just writable. It used to fall through
// to the RAM array -- which reads as zero, since nothing ever writes it -- and
// that is invisible until a title actually reads it. Woody Poco does: it halts
// the sub CPU, maps physical $1D000 to $2000-$2FFF, writes an AV keyboard
// encoder command to $2431 ($D431) and then polls $2432 ($D432) for the ACK
// bit. With the read landing in dead RAM the ACK never arrived and the main CPU
// span on `LDA $2432 / BITA #$01 / BEQ` forever.
// A main-CPU read of the closed aperture is $FF, not whatever the RAM array
// happens to present for an address it does not decode -- `vram_sel` is gated
// on the halt, so without this the read falls through to `ram_q`, and physical
// $10000-$1BFFF is not part of `ram_sel`.
assign DOUT = bootram_sel ? boot_q :
              vram_addr_sel ? (sub_open ? VRAM_DOUT : 8'hff) :
              subio_sel ? SUBIO_DOUT :
              shared_sel ? (sub_open ? SHARED_DOUT : 8'hff) : ram_q;

endmodule
