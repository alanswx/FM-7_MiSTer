
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
  // FM77AV only: the YM2203's timer interrupt. 77AVEMU keeps this source in
  // MAIN_IRQ_ENABLE_ALWAYS_ON (fm77av.h:117) with the note "Never mask by
  // $FD02" -- the YM2203C card has no mask register, so software cannot turn
  // it off and does not expect to. Tied high in FM-7 mode, where there is no
  // YM2203 at all.
  input FMIRQn,
  output MCPUCLK, // 8 | 4.9
  output SCPUCLK, // 8 | 4
  output reg [7:0] MDATABUS_out,
  output IRQn,
  output reg switch = 1'b1,   // power-up value; see the SCLKNMIn note below
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
// SCLKNMIn is not a clock, and this flip-flop had NO RESET -- so `switch` held
// whatever Quartus powered it up as until the first SCLKNMIn edge arrived, then
// changed. That is the P0-2 hazard again (TODO.md), but with a sharper edge to
// it: `switch` drives the clock multiplexer immediately below
//
//     assign MCPUCLK = switch ? CLK4_9 : SCLK1;
//
// so the transition is a MID-FLIGHT SWITCH OF THE MAIN CPU'S CLOCK SOURCE
// between two unrelated clocks, which produces a runt pulse. It happens once
// per power-on at a moment set by SCLKNMIn's phase, i.e. at a different point
// in the boot every time -- the shape of an intermittent early-boot failure.
//
// On CLKSYS with a defined power-up value. SW2 is tied to a constant (core.v
// wires it 1'b1, "0 = FM-8 compatibility"), so `switch` now settles one CLKSYS
// cycle after configuration and the mux never transitions at all. Behaviour is
// unchanged for any static SW2; only the power-up glitch goes away.
//
// See DERIVED_CLOCKS.md. This module is where two independent hardware
// regressions point: b1aff78 ($fd03 ack) landed here, and it is also TMMASK's
// destination, the clock domain flagged behind the m77 failures.
always @(posedge CLKSYS)
  switch <= SW2;

// 74ls158 has inverted outputs, this is not the case here
// TODO: ~all clocks
// This is the clock multiplexer, either FM-7 or FM-8.
// This switch status is readable on $FD00 bit 0.
// There are two different tape procedures in BIOS.
// When loading tapes, the bios checks for this flag fist and jumps to the
// corresponding procedure.
assign MCPUCLK = switch ? CLK4_9 : SCLK1;

// SUPERSEDED CLAIM: "the FM-7/FM-8 switch changes the MAIN CPU's clock only,
// the sub runs at the same rate either way" -- disproven by the Fujitsu FM-7
// System Specifications, page 38, section 1.4. Both CPUs run at 8 MHz normally
// and the FM-8 setting moves BOTH, main to 4.9 MHz and sub to 4 MHz; the manual
// says in as many words that they cannot be switched independently. It is one
// DIP switch, read back on $FD00 b0, which page 22's I/O map labels 0:1.2M /
// 1:2M. See docs/FM77AV.md.
//
// So this core currently sits in a combination no real FM-7 can be in: main on
// the FM-8 leg at 4.8 MHz, sub on the FM-7 leg at 8 MHz. That is why raising
// only the main clock breaks the FM77AV demo -- it moves the main:sub ratio,
// and the paragraph below is the evidence that the ratio is load-bearing.
// Per the manual the fix is to move BOTH to 8 MHz, plus the AV's MMR-conditional
// drop to ~1.6 MHz (FM-Techknow p.334). Untried; see TODO.md.
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
// ...but clearing it while the strobe is LOW destroys the value the CPU came
// to read. IRQCLRn is `RFD03n & RESETBn` (PERIPHERAL.v:121), so it is asserted
// for the WHOLE $fd03 read, and CLKSYS is 48 MHz against a 1.2288 MHz E -- the
// flag therefore cleared a cycle or two into the access, and the combinational
// readback below then presented the CLEARED value for the rest of it, which is
// when the CPU latches. $fd03 read $ff -- "no source is requesting" -- on every
// single interrupt, so a handler could never tell which source had fired.
//
// Ys is the worked example. Its ISR is the ordinary dispatch:
//
//     $117d  LDA  $fd03      ; a = $ff, every time
//     $1180  BITA #$04       ; timer bit, active low
//     $1182  BEQ  $1195      ; -> timer handler. NEVER TAKEN
//     $1188  RTI             ; gives up
//
// so $1195 never ran and $11e2 (`STA $ffe5`, the flag its main loop polls at
// $1113) never executed. CSP captures first and clears afterwards, explicitly:
//
//     val = irqstat_reg0 | 0xf0;   // capture FIRST
//     irqstat_timer = false;        // clear AFTER
//     return val;                   // pre-clear value
//
// Acknowledging on either edge of RFD03n is wrong, because ONE $fd03 read
// produces TWO strobes. Measured, printing every RFD03n transition ($time here
// counts CLKSYS edges, not picoseconds):
//
//     t=324215191  RFD03n=0  EB=0  m50_1=0    pulse 1 opens, E LOW
//     t=324215201  RFD03n=1  EB=0  m50_1=0    pulse 1 shuts, 10 cycles wide
//     t=324215211  RFD03n=0  EB=1  m50_1=1    pulse 2 opens, E HIGH, ALREADY CLEARED
//     t=324215231  RFD03n=1  EB=0  m50_1=1    pulse 2 shuts, 20 cycles wide
//     t=324264351  ...                        next interrupt, 49160 cycles on
//
// The decoder is combinational off RDQEn (MDECODE.v:72 , which
// core.v:348 wires to RDQEn). RDQEn is ~(RWB & (QB|EB)), which assumes Q and E
// OVERLAP -- one continuous strobe from Q rising to E falling. In this model
// they do not overlap, so it breaks into a Q-phase pulse and an E-phase pulse
// with a 10-cycle dead gap between them.
//
// Pulse 2, with E high, is the real data cycle -- the 6809 latches on E's fall.
// So acknowledging anywhere before it destroys the value the CPU is about to
// take, and $fd03 reads $ff, "no source is requesting", on every interrupt.
// A plain edge does not work (both edges of pulse 1 are too early) and neither
// does a short glitch filter (the gap is 10 cycles, not one). Qualify on EB
// instead: latch, at each strobe opening, whether this is the E-phase pulse,
// and acknowledge only at the close of that one.
//
// CSP does the same thing in software -- capture first, clear afterwards:
//
//     val = irqstat_reg0 | 0xf0;   // capture FIRST
//     irqstat_timer = false;        // clear AFTER
//     return val;                   // pre-clear value
reg _2MS_en_d;
wire _2MS_tick = _2MS_en & ~_2MS_en_d;   // SVIDEOCLK pulse -> 1 CLKSYS pulse

reg irqclr_d;
reg fd03_ephase;                         // this strobe is the real data cycle
wire fd03_open  = irqclr_d & ~IRQCLRn;   // strobe opening
wire fd03_close = ~irqclr_d & IRQCLRn;   // strobe closing

always @(posedge CLKSYS) begin
  _2MS_en_d <= _2MS_en;
  irqclr_d  <= IRQCLRn;
  if (~RESETBn) begin
    m50_1       <= 1'b1;
    fd03_ephase <= 1'b0;
  end
  else begin
    if (fd03_open) fd03_ephase <= EB;    // E high => the cycle the CPU latches
    if (_2MS_tick) m50_1 <= TMMASK;
    if (fd03_close & fd03_ephase)        // ack only at the end of THAT pulse
      m50_1 <= 1'b1;                     // clear still wins over a same-cycle tick
  end
end

// This is the read $FD03 I/O implementation.
//
// LOCAL CHANGE: bit 2 was `m50_qn` (= ~m50_1) while bits 0, 1 and 3 are all
// active low -- KEYINn, LPINTn and ~EXTIRQ each read 0 when that source is
// pending. CSP has the whole register active low: a pending source clears its
// bit (`irqstat_reg0 &= ~0x08` for external, fm7_mainio.cpp:1141) and reading
// acknowledges by setting the timer and printer bits back
// (`irqstat_reg0 |= 0x06`). MAME's bit map agrees on the assignments
// (IRQ_FLAG_KEY 0x01, PRINTER 0x02, TIMER 0x04, OTHER 0x08, fm7.h:69).
//
// And m50_1 is already the active-low timer flag in this module -- `IRQn =
// m50_1 & KEYINn & LPINTn` asserts on 0 -- so inverting it for the register
// made bit 2 read the opposite sense to the IRQ line that drives it.
always @*
  if (~RFD03n) MDATABUS_out = { 4'hf, ~EXTIRQ, m50_1, LPINTn, KEYINn };
  else MDATABUS_out = 8'd0;

// IRQ generation logic
// The YM2203 timer joins the timer, keyboard and printer sources. Woody Poco
// (FM77AV) programs timer A with IRQ A enabled (register $27 <- $05 at
// pc=$c981) and then waits on a counter its handler increments; with jt03's
// irq_n going nowhere the handler never ran and the main CPU span forever at
// $b532 on `LDA $2119,PCR / CMPA #$14 / BCS`.
assign IRQn = m50_1 & KEYINn & LPINTn & FMIRQn;

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
