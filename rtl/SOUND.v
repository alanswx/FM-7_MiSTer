
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

reg bci, bdir;
always @(posedge WFD0Dn, posedge reset)
  if (reset) { bdir, bci } <= 2'b0;
  else { bdir, bci } <= MDATABUS_in[1:0];

wire data_in_oe = ~(~bci | bdir);

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

always @(posedge CLKSYS) begin
  if (reset) begin
    psg_addr   <= 4'd0;
    psg_port_b <= 8'd0;
  end
  else if (wfd0e_stb) begin
    if ({bdir, bci} == 2'b11)
      psg_addr <= MDATABUS_in[3:0];
    else if ({bdir, bci} == 2'b10 && psg_addr == 4'd15)
      psg_port_b <= MDATABUS_in;
  end
end

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

// P4-3: this was declared and never driven. sel_n_i divides the PSG strobe --
// per the header of ym2149_audio.v, 0 = undivided, 1 = divide by two. The FM-7's
// AY-3-8910 runs from a 1.2288 MHz master clock and halves it internally, so
// with en_clk_psg_i already at 1.2 MHz the divided setting is the one that puts
// the tone counters at the right rate; undriven (effectively 0) makes every
// pitch an octave sharp. Worth confirming by ear against a reference recording.
wire sel_n_i = 1'b1;
wire bc_i = bci;
wire bdir_i = bdir;
wire [7:0] data_i = ~data_in_oe ? MDATABUS_in : 8'd0;
wire [7:0] data_r_o;

// Register 14 is port A, i.e. the joystick, and never the PSG's own register.
assign MDATABUS_out = (psg_addr == 4'd14) ? joy_port_a : data_r_o;

`ifdef DEBUG_JOY
// `make DEBUG_JOY=1`. One line per PSG register-15 write (which stick the
// software selected) and per register-14 read (what it got back).
reg rfd0e_d;
always @(posedge CLKSYS) begin
  rfd0e_d <= RFD0En;
  if (wfd0e_stb && {bdir, bci} == 2'b11)
    $display("PSGADDR  <- %0d", MDATABUS_in[3:0]);
  if (wfd0e_stb && {bdir, bci} == 2'b10)
    $display("PSGWR    reg%0d <- %02x", psg_addr, MDATABUS_in);
  if (wfd0e_stb && {bdir, bci} == 2'b10 && psg_addr == 4'd15)
    $display("JOYSEL port_b=%02x -> %s", MDATABUS_in,
             (MDATABUS_in[7:4] == 4'h2) ? "stick 0" :
             (MDATABUS_in[7:4] == 4'h5) ? "stick 1" : "none");
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
  .ch_a_o       ( ch_a_o       ),
  .ch_b_o       ( ch_b_o       ),
  .ch_c_o       ( ch_c_o       ),
  .mix_audio_o  ( mix_audio_o  ),
  .pcm14s_o     ( pcm14s_o     )
);

endmodule

