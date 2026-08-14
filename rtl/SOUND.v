
module SOUND(
  input CLKSYS,
  input CLK1_2,
  input RESETBn,
  input [7:0] MDATABUS_in,
  output [7:0] MDATABUS_out,
  input RFD0En,
  input WFD0En,
  input WFD0Dn,

  // Joysticks, MiSTer bit order: [0]=right [1]=left [2]=down [3]=up
  // [4]=button A [5]=button B, active high.
  input [5:0] joystick_0,
  input [5:0] joystick_1,

  output [13:0] mix_audio_o
);

wire reset = ~RESETBn;

// clock is supposed to come from CLK1_2 (CLKCTL module) but audio module needs
// a clock enable so we regenerate it here.
wire EN_CLK_1_2;
clk_en #(CORE_CLK_1_2) u_ck_en(.ref_clk(CLKSYS), .cen(EN_CLK_1_2));

// $fd0d carries the PSG bus-control pair {bdir, bc1}. This was clocked on
// `posedge WFD0Dn` -- an address decode output used as a clock, which is clean
// in Verilator and a glitchy ripple clock in Quartus. Same family as the FLAGS,
// PERIPHERAL, MFD and PAL conversions; see DERIVED_CLOCKS.md.
//
// Converted to the idiom this file already uses for $fd0e a few lines down:
// register the strobe on CLKSYS and capture on its LEADING edge, where the CPU
// still has the data on the bus. The trailing edge the original used is where
// the bus has already decayed in zero-delay RTL -- the same mistake $fd37 made.
//
// The one-cycle delay cannot reorder this against the $fd0e write that follows:
// CLKSYS is 48 MHz against a 1.2288 MHz E, so {bdir,bc1} settles long before the
// next bus cycle carries the data byte.
reg bci, bdir;

reg wfd0d_d;
always @(posedge CLKSYS) wfd0d_d <= WFD0Dn;
wire wfd0d_stb = ~WFD0Dn & wfd0d_d;   // falling edge = a write to $fd0d

always @(posedge CLKSYS) begin
  if (reset) { bdir, bci } <= 2'b0;
  else if (wfd0d_stb) { bdir, bci } <= MDATABUS_in[1:0];
end


//----------------------------------------------------------------------------
// Joysticks
//
// The FM-7's sticks hang off the PSG's I/O ports; CSP wires exactly this in
// fm7.cpp:626 (`opn[0]->set_context_port_b(joystick, ...)`). The protocol, from
// refs/common-src-project/src/vm/fm7/joystick.cpp:
//
//   * writing PSG register 15 (port B) selects which stick is being read --
//     high nibble $2 selects stick 0, $5 selects stick 1, anything else none
//   * reading PSG register 14 (port A) returns that stick, ACTIVE LOW, as
//     { 1, 1, ~buttonB, ~buttonA, ~right, ~left, ~down, ~up }
//
// This is handled here rather than inside ym2149_audio.v, which has no I/O
// ports at all and is machine-translated from VHDL (n###_o signal names) --
// adding a register file there would be far more invasive than snooping the
// bus, which is all that is needed.
//
// The PSG bus protocol is carried on {bdir, bc1}, which the FM-7 puts in $fd0d,
// with the data byte in $fd0e:
//
//   2'b11  latch register address     2'b10  write data     2'b01  read data
//
reg [3:0] psg_addr;
reg [7:0] psg_port_b;

reg wfd0e_d;
always @(posedge CLKSYS) wfd0e_d <= WFD0En;
wire wfd0e_stb = ~WFD0En & wfd0e_d;   // falling edge = a write to $fd0e

// $fd0e LATCHES A BYTE; the following $fd0d write is what acts on it. The
// whole audio path was silent because this was implemented the other way
// round -- `data_i` was wired straight to the live CPU bus, so by the time the
// command arrived the byte was long gone. An entire run of Thexder issued 1024
// register writes and all three channel DACs stayed at zero.
//
// The order is not a guess. Thexder's own writes, logged off the bus, are:
//
//     $fd0e <- 08     put 8 on the data latch
//     $fd0d <- 03     command 3: latch it as the register address
//     $fd0d <- 00
//     $fd0e <- 1f     data
//     $fd0d <- 02     command 2: write $1f to register 8 (channel A amplitude)
//
// which is exactly CSP's model -- `sound.cpp:308-348`, where set_opn_cmd() runs
// on the $FD0D write and consumes `opn_data`, the byte stored by set_psg() on
// the previous $FD0E write. IO_MAP.md used to give a poke sequence in the
// opposite order; that sequence was checked against this core back when this
// code was the other way round, so it proved only self-consistency.
//
// Holding the byte also fixes the sampling. {bdir,bc1} persists until the next
// $fd0d write, far longer than the chip's 1.2 MHz enable period, so it now sees
// a stable command and a stable byte together.
reg [7:0] psg_data;
always @(posedge CLKSYS) begin
  if (reset) psg_data <= 8'd0;
  else if (wfd0e_stb) psg_data <= MDATABUS_in;
end



always @(posedge CLKSYS) begin
  if (reset) begin
    psg_addr   <= 4'd0;
    psg_port_b <= 8'd0;
  end
  else if (wfd0d_stb) begin
    if (MDATABUS_in[1:0] == 2'b11)
      psg_addr <= psg_data[3:0];
    else if (MDATABUS_in[1:0] == 2'b10 && psg_addr == 4'd15)
      psg_port_b <= psg_data;
  end
end

// Direction as the PSG core sees it, so the byte it samples and the command
// it samples are gated by the same window.
wire data_in_oe = ~(~bci | bdir);

wire joy0_sel = (psg_port_b[7:4] == 4'h2);
wire joy1_sel = (psg_port_b[7:4] == 4'h5);
wire [5:0] joy = joy0_sel ? joystick_0 :
                 joy1_sel ? joystick_1 : 6'd0;

// $ff when no stick is selected, which is what CSP returns.
wire [7:0] joy_port_a = (joy0_sel | joy1_sel)
                      ? { 2'b11, ~joy[5], ~joy[4], ~joy[0], ~joy[1], ~joy[2], ~joy[3] }
                      : 8'hff;

wire clk_i = CLKSYS;
wire en_clk_psg_i = EN_CLK_1_2;
wire reset_n_i = RESETBn;

// P4-3: this was declared and never driven, then driven to 1'b1 on the reading
// that 1 = 'divide by two' put the tone counters right. MEASURED, and it is the
// other way round -- the name is active low:
//
//     sel_n_i = 1  ->  tone counter divides the enable by 8   (an octave SHARP)
//     sel_n_i = 0  ->  divides by 16, which is the AY-3-8910   (correct)
//
// `make sound-test` programs TP = $0140 and measures the square wave: 204,800
// clocks per period at 1'b1 against 409,600 at 1'b0. Shipping 1'b1 made every
// pitch exactly twice the right frequency, which is what the hardware sounded
// like. The bench now asserts the divider so this cannot come back.
//
// Residual: CORE_CLK_1_2 = 39 gives 48/40 = 1.2 MHz where the real PSG clock is
// 1.2288 MHz, so pitches sit 2.3% flat -- about 0.4 semitone. Fixing that needs
// a fractional divider and is a separate job.
wire sel_n_i = 1'b0;
wire bc_i   = bci;
wire bdir_i = bdir;
// The latched $fd0e byte, not the live bus -- see the psg_data comment above.
wire [7:0] data_i = ~data_in_oe ? psg_data : 8'd0;
wire [7:0] data_r_o;

// Register 14 is port A, i.e. the joystick, and never the PSG's own register.
assign MDATABUS_out = (psg_addr == 4'd14) ? joy_port_a : data_r_o;

`ifdef DEBUG_JOY
// `make DEBUG_JOY=1`. One line per PSG register-15 write (which stick the
// software selected) and per register-14 read (what it got back).
reg rfd0e_d;
always @(posedge CLKSYS) begin
  rfd0e_d <= RFD0En;
  // The command write is what acts, on the byte $fd0e latched earlier.
  if (wfd0d_stb && MDATABUS_in[1:0] == 2'b11)
    $display("PSGADDR  <- %0d", psg_data[3:0]);
  if (wfd0d_stb && MDATABUS_in[1:0] == 2'b10)
    $display("PSGWR    reg%0d <- %02x", psg_addr, psg_data);
  if (wfd0d_stb && MDATABUS_in[1:0] == 2'b10 && psg_addr == 4'd15)
    $display("JOYSEL port_b=%02x -> %s", psg_data,
             (psg_data[7:4] == 4'h2) ? "stick 0" :
             (psg_data[7:4] == 4'h5) ? "stick 1" : "none");
  if (~RFD0En && rfd0e_d && psg_addr == 4'd14)
    $display("JOYRD  port_b=%02x -> %02x", psg_port_b, joy_port_a);
end
`endif

ym2149_audio u_ym2149_audio(
  .clk_i        ( clk_i        ),
  .en_clk_psg_i ( en_clk_psg_i ),
  .sel_n_i      ( sel_n_i      ),
  .reset_n_i    ( reset_n_i    ),
  .bc_i         ( bc_i         ),
  .bdir_i       ( bdir_i       ),
  .data_i       ( data_i       ),
  .data_r_o     ( data_r_o     ),
  // The per-channel and raw-PCM taps are not used -- only the mixed output is.
  // Naming them here created implicit ONE-BIT nets for multi-bit outputs, which
  // both Quartus (10236) and Verilator (IMPLICIT) warn about; leave them
  // unconnected so the width mismatch cannot come back as a silent truncation.
  .ch_a_o       (              ),
  .ch_b_o       (              ),
  .ch_c_o       (              ),
  .mix_audio_o  ( mix_audio_o  ),
  .pcm14s_o     (              )
);

endmodule

