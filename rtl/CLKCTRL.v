
// Clock control is page 2 of schematics, just after the MAIN CPU page.

module CLKCTRL(
  input SW2,
  input CLKSYS,
  input SCLK1, // 8
  input SCLK2, // 4
  input SCLKNMIn,
  input RFD00n, // <= see keyboard
  input RFD03n,
  input KEYINn,
  input LPINTn,
  input TMMASK,
  input SVIDEOCLK, // 2
  input IOSn,
  input BTRDYn,
  input EB,
  input RESETBn,
  output MRDYn,
  output reg _2MS,
  input IRQCLRn,
  input EXTIRQ,
  output MCPUCLK, // 8 | 4.9
  output SCPUCLK, // 8 | 4
  output reg [7:0] MDATABUS_out,
  output IRQn,
  output reg switch,
  output CLK2_5,
  output CLK1_2,
  output CLK0_3
);

wire CLK4_9;

// 4.9152MHz
clk_en #(CORE_CLK_4_9) u_ck_en(.ref_clk(CLKSYS), .clk(CLK4_9));

// clock divider (74LS393) used to generate  2.5MHz, 1.2MHz & 0.3MHz
reg [3:0] m93;
always @(posedge CLK4_9)
  m93 <= m93 + 4'd1;

assign CLK2_5 = m93[0];
assign CLK1_2 = m93[1];
assign CLK0_3 = m93[3];

// FM8 compatibility switch
// SW2 switch is on the left on schematics.
// Switch goes into a FF that is clocked on SCLKNMIn.
// Output Q (here named "switch") is then used as bit zero of the main data bus.
// Bit zero is visible on the bus when RFD00 is active (low). So the switch
// status is exposed to the main CPU.
// The implementation of bit zero on main data bus is done in the keyboard
// module and not here because $FD00 is also populated by the keyboard logic.
always @(posedge SCLKNMIn)
  switch <= SW2;

// 74ls158 has inverted outputs, this is not the case here
// TODO: ~all clocks
// This is the clock multiplexer, either FM-7 or FM-8.
// This switch status is readable on $FD00 bit 0.
// There are two different tape procedures in BIOS.
// When loading tapes, the bios checks for this flag fist and jumps to the
// corresponding procedure.
assign MCPUCLK = switch ? CLK4_9 : SCLK1;

// The FM-7/FM-8 switch changes the MAIN CPU's clock only. The sub CPU runs at
// the same rate either way: MAME has it at 16.128MHz/2 = 8.064 MHz for both
// (fm7.cpp `MC6809(config, m_sub, 16.128_MHz_XTAL / 2)`), giving E = 2.016 MHz,
// while the FM-7's main CPU drops to 4.9152 MHz / E = 1.2288 MHz.
//
// This used to hand the sub SCLK2 in FM-7 mode, which is 4 MHz -- E = 1 MHz,
// half speed. SCLK2 is not the sub's clock at all; MB60H010.v labels it "clock
// for MB88401 MCU", i.e. the keyboard controller.
//
// It matters beyond fidelity. The sub CPU is meant to be the FASTER of the two
// (E 2.016 vs 1.2288 MHz) and software leans on that: Thexder pumps its sub-CPU
// program across the shared window with a counter at $fcfe and never waits for
// the sub to catch up. At half speed the sub fell behind and dropped roughly
// every other byte. This is P0-5 again, on the other CPU.
assign SCPUCLK = SCLK1;

// M50 is a FF that is supposed to output the timer IRQ signal for the main CPU.
// It can be masked with TMMASK. Clock is a 2MS signal generated in this module.
reg m50_1;
wire m50_qn = ~m50_1;

// On the schematic this is a 74LS74 clocked by _2MS with an ASYNCHRONOUS
// preset from the $FD03 read, so the clear can never be missed. Sampling it
// on SVIDEOCLK (~2 MHz) instead did miss it: IRQCLRn is an E-domain strobe
// roughly a quarter of a microsecond wide, shorter than SVIDEOCLK's period,
// and when it did coincide with _2MS_en the second assignment below won and
// threw the clear away. The result was IRQn stuck asserted and the main CPU
// permanently re-entering its interrupt handler.
//
// Running the flip-flop on CLKSYS fixes both problems without an async
// clock: the strobe is many CLKSYS cycles wide so it cannot be missed, and
// giving the clear priority over the tick matches the async preset.
reg _2MS_en_d;
wire _2MS_tick = _2MS_en & ~_2MS_en_d;   // SVIDEOCLK pulse -> 1 CLKSYS pulse

always @(posedge CLKSYS) begin
  _2MS_en_d <= _2MS_en;
  if (~RESETBn) m50_1 <= 1'b1;
  else begin
    if (_2MS_tick) m50_1 <= TMMASK;
    if (~IRQCLRn)  m50_1 <= 1'b1;   // clear wins, as the async preset does
  end
end

// This is the read $FD03 I/O implementation.
always @*
  if (~RFD03n) MDATABUS_out = { 4'hf, ~EXTIRQ, m50_qn, LPINTn, KEYINn };
  else MDATABUS_out = 8'd0;

// IRQ generation logic
assign IRQn = m50_1 & KEYINn & LPINTn;

// This is a simple clock divider that generates the 2MS clock.
// Bottom right on schematic page.
reg[9:0] ms_counter;
reg _2MS_en;
always @(posedge SVIDEOCLK) begin
  if (~RESETBn) begin
    ms_counter <= 10'd0;
    _2MS_en <= 1'b0;
  end
  else begin
    ms_counter <= ms_counter + 10'b1;
    _2MS_en <= 1'b0;
    if (ms_counter == 10'd499) begin
      _2MS <= ~_2MS;
      _2MS_en <= _2MS;
    end
  end
end

// This last part is the MRDY generation signal. It is not implemented in the
// CPU core, so this part is useless for now. But it could be possible to
// implement it as MRDY will simply stretch E and Q clocks by multiples of a
// quarter period until it goes high again. Implementation should be done in
// mc809s.v file, where Q/E generation happens.

reg m50_2;
reg [3:0] m73;
wire m50_pr = ~(RESETBn & switch & ~&m73[1:0]);

always @(negedge MCPUCLK or posedge m50_2)
  if (m50_2) m73 <= 4'd0;
  else m73 <= m73 + 4'd1;

always @(posedge EB or posedge m50_pr)
  if (m50_pr) m50_2 <= 1'b1;
  else m50_2 <= IOSn & BTRDYn;

assign MRDYn = ~m50_2;

endmodule
