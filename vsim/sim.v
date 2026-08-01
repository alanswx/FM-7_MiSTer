//============================================================================
//  FM-7 Verilator simulation wrapper
//
//  Stands in for FM-7_MiSTer.sv (the MiSTer top level) without the sys/
//  framework: no hps_io, no PLL, no real SDRAM controller. sim_main.cpp drives
//  clk_sys directly and everything else is wired exactly as FM-7_MiSTer.sv
//  wires it, so the core sees the same 48 MHz clock and the same ioctl/ps2
//  path as on hardware.
//
//  Deliberate differences from FM-7_MiSTer.sv, all of them noted below:
//    - clk_sys comes from sim_main instead of the PLL. The PLL's outclk_0 is
//      48.000 MHz, so this is exact, not an approximation. outclk_1 (2 MHz) is
//      unused by the core and is not reproduced.
//    - rtl/sdram.sv (the real controller, with SDRAM_* pins) is replaced by the
//      behavioural model in vsim/rtl/sdram.sv. Same client interface and the
//      same edge-detected requests and read latency.
//    - The tape download writes BYTES (wtbt=00, 8-bit ioctl_dout). This is no
//      longer a difference: FM-7_MiSTer.sv used to instantiate hps_io with
//      WIDE(1) and write 16-bit words, but WIDE also widens the FLOPPY sector
//      buffer, which the top wires as [7:0] -- so every sector read was
//      silently half-truncated and no disk could boot on hardware. The FPGA
//      build is WIDE(0) now and matches this wrapper byte for byte.
//    - VGA_R/G/B replicate the core's single colour bit across all 8 bits.
//      FM-7_MiSTer.sv assigns only VGA_x[7] and leaves [6:0] undriven (0 after
//      synthesis), which would make every screenshot half-brightness.
//    - VGA_VB clears 384 pixel clocks early, inside the last blanked line. See
//      the comment at the assignment -- it is a framebuffer alignment fix and
//      cannot affect any visible pixel.
//============================================================================

`timescale 1ns / 1ps

module emu
(
	input         clk_sys,          // 48 MHz, driven by sim_main
	input         reset,

	// core options, mirroring the OSD status bits in FM-7_MiSTer.sv
	input   [1:0] bootrom_sel,      // status[11:10] "BootROM" Basic/1/2/3
	input         tape_rewind,      // status[8]     "Tape Rewind"
	input         tape_audio,       // status[9]     "Tape Audio"

	// [7:0] scancode, [8] extended, [9] pressed, [10] toggles per event
	input  [10:0] ps2_key,

	// Joysticks, driven from sim_main.cpp's --joystick option.
	// MiSTer bit order: [0]=right [1]=left [2]=down [3]=up [4]=A [5]=B.
	input   [5:0] joystick_0,
	input   [5:0] joystick_1,

	// HPS ioctl download. index 1 == "F1,t77" in CONF_STR.
	input         ioctl_download,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_dout,
	input   [7:0] ioctl_index,
	output        ioctl_wait,

	// MiSTer block device, driven by sim/sim_blkdevice.cpp. Widths chosen to
	// match SimBlockDevice's member types: sd_rd/sd_wr/sd_ack/img_mounted are
	// per-drive bit vectors (SData), img_size is 64-bit (QData). Only drive 0
	// is connected.
	input  [15:0] img_mounted,
	input         img_readonly,
	input  [63:0] img_size,
	output [31:0] sd_lba,
	output [15:0] sd_rd,
	output [15:0] sd_wr,
	input  [15:0] sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_HB,
	output        VGA_VB,
	output        VGA_DE,
	output        CE_PIXEL,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	// raster position, for the sim UI
	output  [9:0] h_count,
	output  [8:0] v_count,

	// ---- debug taps ----------------------------------------------------
	// Hierarchical reads into the core. Nothing here drives the core, and none
	// of it exists in FM-7_MiSTer.sv -- it is purely so sim_main can show and
	// log internal state without --public-flat-rw or edits to rtl/.

	// Main 6809
	output [15:0] dbg_m_pc,
	output [15:0] dbg_m_addr,
	output  [7:0] dbg_m_dout,
	output  [7:0] dbg_m_din,
	output        dbg_m_rw,         // 1 = read
	output        dbg_m_ifetch,     // high during the opcode fetch; addr = the
	                                // instruction's own address
	output        dbg_m_e,
	output        dbg_m_irqn,
	output        dbg_m_firqn,
	output        dbg_m_nmin,
	output        dbg_m_haltn,      // GHn: sub-system HALT request to main CPU
	output  [7:0] dbg_m_a, dbg_m_b, dbg_m_cc, dbg_m_dp,
	output [15:0] dbg_m_x, dbg_m_y, dbg_m_u, dbg_m_s,

	// Sub 6809
	output [15:0] dbg_s_pc,
	output [15:0] dbg_s_addr,
	output  [7:0] dbg_s_dout,
	output  [7:0] dbg_s_din,
	output        dbg_s_rw,         // 1 = read
	output        dbg_s_e,
	output        dbg_s_ifetch,
	output  [7:0] dbg_s_a, dbg_s_b, dbg_s_cc, dbg_s_dp,
	output [15:0] dbg_s_x, dbg_s_y, dbg_s_u, dbg_s_s,
	output        dbg_s_haltn,      // SHALTn
	output        dbg_s_halt_ackn,  // SHALTACn: 0 = sub bus handed to main CPU
	output        dbg_s_irqn,       // SUBIRQn
	output        dbg_s_firqn,      // KSTROBEn
	output        dbg_s_nmin,       // SCLKNMIn
	output        dbg_busy,         // BUSY flag read back at $fd05 bit 7

	// Main-CPU memory map selects, all active low except FCXXn's sense as
	// documented in ROMS.v. Bit order matches the sim's "mmap" printout:
	//   [0] FCXXn [1] RAM1HB1n [2] RAM1HB2n [3] BTROMn
	//   [4] BTRDYn [5] SUBSELn [6] MIOSn    [7] RDQEn
	output  [7:0] dbg_mmap,
	output  [7:0] dbg_romdata,     // ROMS.v output, before core.v's read mux

	// Main-CPU I/O window ($fd00-$fdff). Levels; sim_main edge-detects.
	output        dbg_io_rd,
	output        dbg_io_wr,
	output  [7:0] dbg_io_port,
	output  [7:0] dbg_io_data,

	// Video
	output [23:0] dbg_pal,          // 8 entries x 3 bits, entry 0 in [2:0]
	output  [7:0] dbg_vpage,        // $fd37 latch (VPAGEn / DPAGEn)
	output [13:0] dbg_voffset,      // MB60H010 scroll offset
	output        dbg_svdoffn,      // 0 = display forced off

	// Keyboard
	output  [7:0] dbg_kdata,
	output        dbg_kp0,          // 9th data bit
	output        dbg_kstroben,
	output        dbg_kpending,     // a code is latched and not yet acked
	output  [2:0] dbg_km77,         // $fd02 mask bits

	// Tape
	output        dbg_tape_motor,
	output        dbg_tape_in,
	output [24:0] dbg_tape_addr,
	output        dbg_tape_rd,
	output        dbg_tape_eot,
	output [24:0] dbg_tape_size,

	output        dbg_resetbn
);

//////////////////////////////////////////////////////////////////
// Core
//
// Wiring copied from FM-7_MiSTer.sv, minus the OSD status[] indirection.
//////////////////////////////////////////////////////////////////

wire        RESETn = ~reset;
wire        CLKSYS = clk_sys;

wire  [2:0] grb;
wire        HBlank, VBlank, HSync, VSync, ce_pix;
wire        SVIDEOCLK;
wire [13:0] audio_out;
wire        buzzer;
wire  [7:0] relay_snd;

wire        cin;
wire        motor;

core u_core(
  .RESETn      ( RESETn      ),
  .CLKSYS      ( CLKSYS      ),
  .HBLANK      ( HBlank      ),
  .VBLANK      ( VBlank      ),
  .VSync       ( VSync       ),
  .HSync       ( HSync       ),
  .grb         ( grb         ),
  .ps2_key     ( ps2_key     ),
  .joystick_0  ( joystick_0  ),
  .joystick_1  ( joystick_1  ),
  .SVIDEOCLK   ( SVIDEOCLK   ),
  .ce_pix      ( ce_pix      ),
  .audio_out   ( audio_out   ),
  .buzzer      ( buzzer      ),
  // tape
  .cin         ( cin         ),
  .motor       ( motor       ),
  .bootrom_sel ( bootrom_sel ),
  // floppy, drive 0 only
  .img_mounted  ( img_mounted[0]  ),
  .img_readonly ( img_readonly    ),
  .img_size     ( img_size        ),
  .sd_lba       ( sd_lba          ),
  .sd_rd        ( sd_rd_0         ),
  .sd_wr        ( sd_wr_0         ),
  .sd_ack       ( sd_ack[0]       ),
  .sd_buff_addr ( sd_buff_addr    ),
  .sd_buff_dout ( sd_buff_dout    ),
  .sd_buff_din  ( sd_buff_din     ),
  .sd_buff_wr   ( sd_buff_wr      )
);

wire sd_rd_0, sd_wr_0;
assign sd_rd = { 15'd0, sd_rd_0 };
assign sd_wr = { 15'd0, sd_wr_0 };

pcm pcm(
  .CLKSYS         ( CLKSYS    ),
  .motor          ( motor     ),
  .unsigned_audio ( relay_snd )
);

//////////////////////////////////////////////////////////////////
// Video out
//////////////////////////////////////////////////////////////////

// FM-7_MiSTer.sv drives only bit 7 of each channel and leaves the rest
// undriven. Replicating the bit instead keeps screenshots at full scale
// without changing which pixels are lit.
assign VGA_R = {8{grb[1]}};
assign VGA_G = {8{grb[2]}};
assign VGA_B = {8{grb[0]}};

assign VGA_HS   = HSync;
assign VGA_VS   = VSync;
assign VGA_HB   = HBlank;
assign VGA_DE   = ~(HBlank | VBlank);

// One-cycle pulse per pixel. The core's ce_pix is SFTCLK, which clk_en drives
// as a real 16 MHz CLOCK -- high for two of every three clk_sys cycles, not a
// one-cycle enable. Passing it straight through made sim_main sample every
// pixel twice and doubled the picture horizontally. (FM-7_MiSTer.sv hands the
// same signal to the MiSTer scaler as CE_PIXEL, which is worth a look: a
// two-thirds duty "enable" is not what a ce_pix input normally expects.)
reg ce_pix_d;
always @(posedge clk_sys) ce_pix_d <= ce_pix;
assign CE_PIXEL = ce_pix & ~ce_pix_d;

assign h_count = u_core.u_MB60H010.xx;
assign v_count = u_core.u_MB60H010.yy;

// SimVideo starts a new line when HBLANK falls and a new frame when VBLANK
// falls, and it resets the line counter AFTER the line increment. In this core
// both edges land on the same clock -- MB60H010 wraps xx to 0 and yy to 0
// together -- so the frame reset would eat the line increment and shift the
// whole picture up by one line. Clearing VB during the last blanked line
// (yy==261, xx>=640) puts the two edges back in the order SimVideo expects.
// HBLANK is high for that whole window, so no visible pixel is affected.
assign VGA_VB = VBlank & ~((v_count == 9'd261) && (h_count >= 10'd640));

//////////////////////////////////////////////////////////////////
// Audio
//
// FM-7_MiSTer.sv: cassette bit, core PSG, buzzer and relay click, summed.
// status[9] ("Tape Audio") gates the cassette and relay.
//////////////////////////////////////////////////////////////////

wire [15:0] cin_audio   = { 1'b0, cin & motor & tape_audio, 13'b0 };
wire [15:0] core_audio  = { 1'b0, audio_out, 13'b0 };
wire [15:0] buz_audio   = { 1'b0, buzzer, 13'b0 };
wire [15:0] relay_audio = { 1'b0, (tape_audio ? relay_snd : 8'd0), 7'b0 };

assign AUDIO_L = cin_audio + core_audio + buz_audio + relay_audio;
assign AUDIO_R = AUDIO_L;

//////////////////////////////////////////////////////////////////
// Cassette: ioctl -> SDRAM -> t77_decode
//
// Same shape as the synthesis top level, so what the sim exercises is the
// path that ships.
//////////////////////////////////////////////////////////////////

wire [15:0] sdram_data;
wire [24:0] sdram_addr;
wire        need_more_byte;
wire        sdram_ready;

// index 1 == "F1,t77,Load Tape" in CONF_STR.
wire tape_download = ioctl_download && (ioctl_index == 8'd1);

// The tape path goes through the SDRAM controller, which detects requests on an
// EDGE. Without back-pressure SimBus holds ioctl_wr high for the whole
// transfer, the controller sees one write, and only the first byte lands.
// Throttling on sdram_ready is what makes ioctl_wr re-strobe per byte.
assign ioctl_wait = tape_download & ~sdram_ready;

reg old_ioctl_download;
always @(posedge clk_sys)
  old_ioctl_download <= tape_download;

wire rewind = (old_ioctl_download & ~tape_download) | tape_rewind;

// Size of the mounted tape, so t77_decode can stop at the end. SimBus writes
// bytes and so does the FPGA build now (hps_io WIDE(0)), so both step by 1.
reg [24:0] tape_size = 25'd0;
always @(posedge clk_sys)
  if (tape_download && ioctl_wr) tape_size <= ioctl_addr + 25'd1;

sdram u_sdram(
  .init  ( 1'b0                                          ),
  .clk   ( CLKSYS                                        ),
  .wtbt  ( 2'b00                                         ),
  .addr  ( tape_download ? ioctl_addr : sdram_addr       ),
  .dout  ( sdram_data                                    ),
  .din   ( { 8'd0, ioctl_dout }                          ),
  .we    ( tape_download & ioctl_wr                      ),
  .rd    ( need_more_byte                                ),
  .ready ( sdram_ready                                   )
);

t77_decode u_t77_decode(
  .CLKSYS     ( CLKSYS         ),
  .start      ( motor          ),
  .data       ( sdram_data     ),
  .data_stb   ( sdram_ready    ),
  .sdram_addr ( sdram_addr     ),
  .sdram_rd   ( need_more_byte ),
  .sout       ( cin            ),
  .rewind     ( rewind         ),
  .image_size ( tape_size      ),
  .eot        ( dbg_tape_eot   )
);

//////////////////////////////////////////////////////////////////
// Debug taps (hierarchical reads -- observation only)
//////////////////////////////////////////////////////////////////

// Main 6809. `corecpu` is the mc6809i instance inside mc6809s.
//
// Instruction boundaries come from the state machine, not from LIC. mc6809i
// asserts LIC on the last cycle of an instruction, at which point `pc` has
// already been advanced past the operands but not yet through a taken branch
// -- so LIC-sampled pc is neither the current nor the next instruction's
// address. CPUSTATE_FETCH_I1 (7'd4) is the opcode fetch, and `assign ADDR =
// addr_nxt` with `addr_nxt = pc` in that state means the bus is carrying the
// instruction's own address while it is high. The two Latched signals exclude
// the HALT and DMA branches of that state, which re-enter it without fetching.
assign dbg_m_pc      = u_core.u_MCPU.mc6809s_i0.corecpu.pc;
assign dbg_m_addr    = u_core.MADDRBUS;
assign dbg_m_dout    = u_core.MDATABUS_out;
assign dbg_m_din     = u_core.MDATABUS_in;
assign dbg_m_rw      = u_core.RWB;
assign dbg_m_ifetch  = (u_core.u_MCPU.mc6809s_i0.corecpu.CpuState == 7'd4)
                     &  u_core.u_MCPU.mc6809s_i0.corecpu.HALTLatched
                     &  u_core.u_MCPU.mc6809s_i0.corecpu.DMABREQLatched;
assign dbg_m_e       = u_core.E;
assign dbg_m_irqn    = u_core.IRQn;
assign dbg_m_firqn   = u_core.FIRQn;
assign dbg_m_nmin    = u_core.NMIn;
assign dbg_m_haltn   = u_core.GHn;
assign dbg_m_a       = u_core.u_MCPU.mc6809s_i0.corecpu.a;
assign dbg_m_b       = u_core.u_MCPU.mc6809s_i0.corecpu.b;
assign dbg_m_cc      = u_core.u_MCPU.mc6809s_i0.corecpu.cc;
assign dbg_m_dp      = u_core.u_MCPU.mc6809s_i0.corecpu.dp;
assign dbg_m_x       = u_core.u_MCPU.mc6809s_i0.corecpu.x;
assign dbg_m_y       = u_core.u_MCPU.mc6809s_i0.corecpu.y;
assign dbg_m_u       = u_core.u_MCPU.mc6809s_i0.corecpu.u;
assign dbg_m_s       = u_core.u_MCPU.mc6809s_i0.corecpu.s;

// Sub 6809.
assign dbg_s_pc         = u_core.u_SCPU.mc6809s_i0.corecpu.pc;
assign dbg_s_addr       = u_core.SADDRBUS;
assign dbg_s_dout       = u_core.SDATABUS_out;
assign dbg_s_din        = u_core.SDATABUS_in;
assign dbg_s_rw         = u_core.SRWB;
assign dbg_s_e          = u_core.SEB;
assign dbg_s_ifetch     = (u_core.u_SCPU.mc6809s_i0.corecpu.CpuState == 7'd4)
                        &  u_core.u_SCPU.mc6809s_i0.corecpu.HALTLatched
                        &  u_core.u_SCPU.mc6809s_i0.corecpu.DMABREQLatched;
assign dbg_s_a          = u_core.u_SCPU.mc6809s_i0.corecpu.a;
assign dbg_s_b          = u_core.u_SCPU.mc6809s_i0.corecpu.b;
assign dbg_s_cc         = u_core.u_SCPU.mc6809s_i0.corecpu.cc;
assign dbg_s_dp         = u_core.u_SCPU.mc6809s_i0.corecpu.dp;
assign dbg_s_x          = u_core.u_SCPU.mc6809s_i0.corecpu.x;
assign dbg_s_y          = u_core.u_SCPU.mc6809s_i0.corecpu.y;
assign dbg_s_u          = u_core.u_SCPU.mc6809s_i0.corecpu.u;
assign dbg_s_s          = u_core.u_SCPU.mc6809s_i0.corecpu.s;
assign dbg_s_haltn      = u_core.SHALTn;
assign dbg_s_halt_ackn  = u_core.SHALTACn;
assign dbg_s_irqn       = u_core.SUBIRQn;
assign dbg_s_firqn      = u_core.KSTROBEn;
assign dbg_s_nmin       = u_core.SCLKNMIn;
assign dbg_busy         = u_core.BUSY;

// Main-CPU I/O. MDECODE decodes IOSn low for $fd00-$fdff, so the port number
// is just the low address byte. RDEn/WTQEn are the read/write bus qualifiers
// the same decoder uses to build the individual RFDxx/WFDxx strobes, which is
// why they line up with real accesses and not with idle bus cycles.
assign dbg_io_rd   = ~u_core.IOSn & ~u_core.RDEn;
assign dbg_io_wr   = ~u_core.IOSn & ~u_core.WTQEn;
assign dbg_mmap    = { u_core.RDQEn,    u_core.MIOSn,    u_core.SUBSELn, u_core.BTRDYn,
                       u_core.BTROMn,   u_core.RAM1HB2n, u_core.RAM1HB1n, u_core.FCXXn };
assign dbg_romdata = u_core.ROMDATA;

assign dbg_io_port = u_core.MADDRBUS[7:0];
assign dbg_io_data = dbg_io_wr ? u_core.MDATABUS_out : u_core.MDATABUS_in;

// Video. PAL holds eight 3-bit GRB entries; pack them so entry n is in
// dbg_pal[3n+2 : 3n].
assign dbg_pal = { u_core.PAL.pal[7], u_core.PAL.pal[6],
                   u_core.PAL.pal[5], u_core.PAL.pal[4],
                   u_core.PAL.pal[3], u_core.PAL.pal[2],
                   u_core.PAL.pal[1], u_core.PAL.pal[0] };
assign dbg_vpage   = u_core.u_FLAGS.m46;
assign dbg_voffset = u_core.u_MB60H010.VOFFSET;
assign dbg_svdoffn = u_core.SVDOFFn;

// Keyboard. `kdata`/`P0` are the 9-bit code the sub CPU reads at $d400; m132
// is the "a code is waiting" latch that drives KSTROBEn / KEYINn.
assign dbg_kdata    = u_core.KEYBOARD.kdata;
assign dbg_kp0      = u_core.KEYBOARD.P0;
assign dbg_kstroben = u_core.KSTROBEn;
assign dbg_kpending = u_core.KEYBOARD.m132;
assign dbg_km77     = u_core.KEYBOARD.m77;

// Tape.
assign dbg_tape_motor = motor;
assign dbg_tape_in    = cin;
assign dbg_tape_addr  = sdram_addr;
assign dbg_tape_size  = tape_size;
assign dbg_tape_rd    = need_more_byte;

assign dbg_resetbn = u_core.RESETBn;

endmodule
