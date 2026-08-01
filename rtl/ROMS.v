
module ROMS (
  input [15:0] MADDRBUS,
  input RESETBn,
  input RFD0Fn,
  input WFD0Fn,
  input RDQEn,
  input CLKSYS,
  output FCXXn,
  output RAM1HB2n,
  output [7:0] ROMDATA,
  output BTRDYn,
  output BTROMn,
  output SUBSELn,
  output MIOSn,
  output RAM1HB1n,
  input [1:0] SW2
);

assign FCXXn = ~&MADDRBUS[15:10];

reg ff_q;

wire [3:0] m139_q;
wire [7:0] m151_q;
wire [7:0] m152_bank_q;

// Boot ROM select. M152 is a single 2 KB chip holding FOUR 512-byte banks, and
// the OSD's four settings are exactly those banks -- see TODO.md P3-6b. MAME
// says the same of its own 0x800 `boot` region ("actually 0.5K banks of the
// same ROM", fm7.cpp:2179). SW2 is the bank number.
//
// This replaces a pair of loose 512-byte images (boot_bas.rom / boot_dos_a.rom)
// selected by |SW2, which made settings 1, 2 and 3 all the same ROM and left
// bank 1 unreachable.
//
// It also retires a hack. The old mux had `|| &MADDRBUS[15:4]`, forcing reads of
// $fff0-$ffff from the DOS image whatever the setting, because boot_bas.rom is a
// **bad dump**: its last two bytes are the reset vector and they read $ffff
// instead of $fe00, so a machine booting from it fetched a garbage RESET. Every
// bank of the real chip carries RESET=$fe00, so nothing needs forcing now.
wire [7:0] m152_q = m152_bank_q;

assign ROMDATA = m151_q | m152_q;

wire m107_q  = ~(MADDRBUS[15] & FCXXn & ff_q);
wire m120_q  = ~|SW2;

wire m131_q1 = ~MADDRBUS[9] | FCXXn;
wire m131_q2 = BTROMn | RDQEn;

wire m139_rdy_n;

assign SUBSELn  = FCXXn ? 1'b1 : m139_q[0];
assign MIOSn    = FCXXn ? 1'b1 : m139_q[1];
assign BTROMn   = FCXXn ? 1'b1 : m139_q[2];
assign RAM1HB1n = FCXXn ? 1'b1 : m139_q[3];
assign RAM1HB2n = m107_q;

// The boot-ROM/RAM switch at $fd0f: reading it maps the F-BASIC ROM at
// $8000-$fbff, writing it maps RAM there. CSP describes exactly that
// (fm7_mainio.cpp:771) and this core matches it.
//
// This used to be three asynchronous edges, and one of them was
//
//     wire ck = ~RESETBn;   // a flip-flop CLOCKED BY RESET BEING ASSERTED
//
// which only loads the power-on default `m120_q` on a RISING edge of ~RESETBn,
// i.e. on RESETBn FALLING. If RESETBn is already low when the FPGA comes out of
// configuration there is never such an edge: ff_q keeps whatever Quartus
// powered it up as, RAM1HB2n stays high, the F-BASIC ROM is never chip-selected,
// every read of $8000-$fbff returns $00, and the boot ROM's `LDX $fbfe / JMP ,X`
// jumps to $0000 and executes zeroed RAM forever.
//
// vsim never showed this because sim_main.cpp deliberately runs a power-on pulse
// -- `top->reset = (reset_prologue == 0) && (reset_hold > 0)` at :986 holds
// reset LOW for 64 cycles and only then asserts it, manufacturing the edge. On
// hardware FM-7_MiSTer.sv takes `reset = RESET | status[0] | buttons[1]` and
// sys/ asserts RESET at power-on, so the edge was never guaranteed and the
// design was leaning on a Quartus power-up state. See TODO.md P0-2.
//
// Now an ordinary synchronous reset-and-load. Read still wins over write, as
// before. The strobes are many CLKSYS cycles wide (E is 1.2288 MHz against a
// 48 MHz CLKSYS), so edge-detecting them here is safe.
reg rfd0f_d, wfd0f_d;
always @(posedge CLKSYS) begin
  rfd0f_d <= RFD0Fn;
  wfd0f_d <= WFD0Fn;
  if (~RESETBn)               ff_q <= m120_q;   // held loaded for the whole reset
  else if (rfd0f_d & ~RFD0Fn) ff_q <= 1'b1;     // read  $fd0f -> F-BASIC ROM
  else if (wfd0f_d & ~WFD0Fn) ff_q <= 1'b0;     // write $fd0f -> RAM
end

m139 m139_u1(
  .clk   ( CLKSYS        ),
  .addr  ( MADDRBUS[9:1] ),
  .q     ( m139_q        ),
  .cs_n  ( FCXXn         )
);

rom #("./roms/fbasic300.rom.mem", 15, 8) m151(
  .clk  ( CLKSYS         ),
  .addr ( MADDRBUS[14:0] ),
  .dout ( m151_q         ),
  .ce_n ( RDQEn | m107_q )
);

// The whole 2 KB chip, addressed as {bank, offset}.
rom #("./roms/TL11_11_M152.rom.mem", 11, 8) m152(
  .clk  ( CLKSYS               ),
  .addr ( {SW2, MADDRBUS[8:0]} ),
  .dout ( m152_bank_q          ),
  .ce_n ( m131_q1 | m131_q2    )
);

endmodule
