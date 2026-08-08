
module TIMER(
  input CLKSYS,
  input [7:0] MDATABUS_in,
  output reg [7:0] MDATABUS_out,
  input WFD03n,
  input BUZZERn,
  input RESETBn,
  input EB,
  input Z80W,
  input REFGRVTn,
  input ATTENTn,
  input RFD04n,
  input RFD05n,
  input BUSY,
  input SHALTACn,   // sub-CPU halt acknowledge, active low
  input BREAKn,
  input EXTDETn,
  input CLK0_3,
  output SOUND,
  output SCLKNMIn,
  output DMAn,
  output FIRQn
);

reg [2:0] cmd;
reg speaker;
reg single;
reg continuous;
reg [4:0] _1s;

reg [6:0] cnt1;
reg [12:0] cnt2;
reg beep;
reg _20MS;

wire s0 = ~(WFD03n|BUZZERn);

wire reset = ~RESETBn;
always @(posedge CLK0_3, posedge s0, posedge reset) begin
  if (reset) begin
    speaker <= 1'b0;
    single <= 1'b0;
    continuous <= 1'b0;
  end
  else if (s0) cmd <= { MDATABUS_in[7:6], MDATABUS_in[0] };
  else begin
    speaker <= cmd[0];
    single <= cmd[1];
    continuous <= cmd[2];
    // thanks to friendly.joe, we know continuous has priority
    if (~continuous || _1s >= 5'd19) begin
      speaker <= 1'b0;
      cmd <= 3'd0;
    end
  end
end

always @(posedge _20MS) begin
  if (~speaker) _1s <= 5'd0;
  else _1s <= _1s + 5'd1;
end

// 300kHz / 250 = 1200Hz
always @(posedge CLK0_3) begin
  cnt1 <= cnt1 + 7'd1;
  if (cnt1 == 7'd125) begin
    cnt1 <= 7'd0;
    beep <= ~beep;
  end
end

always @(posedge CLK0_3, posedge reset) begin
  if (reset) begin
    cnt2 <= 13'd0;
    _20MS <= 1'b0;
  end
  else begin
    cnt2 <= cnt2 + 13'd1;
    if (cnt2 == 13'd3000) begin
      cnt2 <= 13'd0;
      _20MS <= ~_20MS;
    end
  end
end

// TODO: MB14415 timer / buzzer (see MC14415)

assign DMAn = 1'b1; // dummy output

// $fd04 bit 0 -- the sub CPU's "attention" FIRQ.
//
// The sub raises it by READING $d404 (SDECODE's m98 is the sub-side READ
// decoder, so ATTENTn is a read strobe), and the main clears it by reading
// $fd04. All three references agree, including that it is active low:
//
//   MAME     attn_irq_r sets attn_irq and asserts M6809_FIRQ_LINE
//            (fm7_v.cpp:77); fd04_r returns $ff with bit 0 cleared, then
//            zeroes the flag.
//   CSP      get_fd04: `if(!firq_sub_attention) val |= 0x01;`, then
//            set_sub_attention(false) (fm7_mainio.cpp:661).
//   77AVEMU  MAIN_FIRQ_SOURCE_ATTENTION=0x01 with `byteData = ~firqSource`,
//            and reading $fd04 clears ATTENTION but deliberately NOT the
//            break key ("Probably break-key FIRQ not", fm77avio.cpp:668).
//
// The previous version could never fire. Its asynchronous preset was
//
//     s2 = ~m47_q11 = ~(RESETBn & ~RFD04n)
//
// which is HIGH whenever $fd04 is *not* being read -- so the flag sat held
// cleared at all times except inside the read window, and an attention could
// only ever be captured if the sub happened to read $d404 during exactly the
// cycles the main was reading $fd04. In practice the main CPU never received
// an attention FIRQ at all. Bit 0 then reported m47_q11, which is 1 throughout
// any read of $fd04 -- a constant "no interrupt pending".
//
// Clearing on the trailing edge of the read strobe rather than during it keeps
// the value stable for the whole bus cycle; an asynchronous clear asserted
// across the read is the P0-1 race wearing a different hat. Set wins over
// clear, so an attention landing on the acknowledge cycle is not swallowed --
// the same argument as KEYBOARD.v's m132.
// ...and the trailing edge is NOT "main finished reading \$fd04", because one
// read makes TWO strobes. Identical structure to the \$fd03 bug, measured here
// on OS-9 (\$time counts CLKSYS edges):
//
//     t=171925871  RFD04n=0  EB=0  attn_pend=1   pulse 1 opens, Q phase
//     t=171925881  RFD04n=1  EB=0  attn_pend=1   pulse 1 shuts -> CLEAR FIRES
//     t=171925891  RFD04n=0  EB=1  attn_pend=0   pulse 2 opens, E phase, GONE
//     t=171925911  RFD04n=1  EB=0  attn_pend=0   pulse 2 shuts
//
// RDQEn is ~(RWB & (QB|EB)) and assumes Q and E overlap; they do not, so the
// decode splits into a Q-phase pulse and an E-phase pulse. The 6809 latches on
// E's fall, i.e. in pulse 2, so clearing at the close of pulse 1 means the main
// CPU reads bit 0 = 1, "no attention pending", every single time. OS-9 hits
// this 578 times in 900 frames and has never once seen an attention it was
// actually sent.
//
// Qualify on EB exactly as CLKCTRL.v does for \$fd03: remember at each strobe
// opening whether this is the E-phase pulse, and acknowledge only at the close
// of that one. Set still wins over clear, so an attention landing on the
// acknowledge cycle is not swallowed -- the same argument as KEYBOARD.v's m132.
reg attn_pend;              // 1 = an attention is waiting
reg attn_d, rfd04_d;
reg fd04_ephase;            // the strobe now open is the cycle the CPU latches
always @(posedge CLKSYS) begin
  attn_d  <= ATTENTn;
  rfd04_d <= RFD04n;
  if (rfd04_d & ~RFD04n) fd04_ephase <= EB;        // strobe opening
  if (~RESETBn)               attn_pend <= 1'b0;
  else if (attn_d & ~ATTENTn) attn_pend <= 1'b1;   // sub read \$d404
  else if (~rfd04_d & RFD04n & fd04_ephase)
                              attn_pend <= 1'b0;   // main REALLY finished reading
end

wire m45_q8n = ~attn_pend;  // active low, as the bus and FIRQn see it

// $fd05 bit 7 is "the sub system is not available", which is true both while it
// is BUSY working on a command and while it is HALTED for the main CPU to touch
// shared RAM. MAME says so explicitly (fm7_v.cpp subintf_r: `if(sub_busy != 0
// || sub_halt != 0) ret |= 0x80;`).
//
// BUSY alone is not enough, and the two halves are mutually exclusive here:
// FLAGS.v holds the BUSY flip-flop asynchronously cleared while the halt is
// acknowledged (`s3 = RESETBn & SHALTACn`), so during a halt bit 7 read as 0
// forever. Software that requests a halt and then polls for it to take effect
// -- the normal way to get at shared RAM -- hung.
//
// Nothing caught this before because the only code exercised so far polls the
// other way round. F-BASIC waits for bit 7 to CLEAR (`LDA <$05 / BMI`), which a
// permanently-0 bit satisfies immediately, so the handshake looked healthy.
// Thexder's loader waits for it to SET and spun forever at $100c.
wire SUBUNAVAIL = BUSY | ~SHALTACn;

// m72
//
// Bit 2 carries BUSY here, which no reference does: MAME's fd04_r leaves it
// set, CSP ORs in 0x7c for a plain FM-7 and puts sub-busy at bit 7 instead,
// and 77AVEMU returns ~firqSource so bits 2-7 all read 1. This core is derived
// from the schematic rather than from any of them, and no title measured so far
// reads $fd04 for anything but the attention flag, so it is left alone rather
// than churned on a disagreement between references. Recorded in TODO.md.
always @*
  if (~RFD04n)
    MDATABUS_out = { 5'b11111, BUSY, BREAKn, m45_q8n };
  else if (~RFD05n)
    MDATABUS_out = { SUBUNAVAIL, 6'b111111, EXTDETn };
  else
    MDATABUS_out = 8'h00;

assign FIRQn = m45_q8n & BREAKn;
assign SOUND = speaker ? beep : 1'b0;
assign SCLKNMIn = _20MS;

endmodule
