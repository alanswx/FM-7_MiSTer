
module MDECODE (
  input [15:0] MADDRBUS,
  input RDEn,
  input E,
  input RWBn,
  input WTQEn,
  output IOSn,
  output FD0Xn,
  output PLTREGn,
  output AB3n,
  output WFD05n,
  output WFD37n,
  output WFD00n,
  output WFD01n,
  output WFD02n,
  output WFD03n,
  output WFD0Dn,
  output WFD0En,
  output WFD0Fn,
  output RFD00n,
  output RFD01n,
  output RFD02n,
  output RFD04n,
  output RFD03n,
  output RFD05n,
  output RFD0En,
  output RFD0Fn,
  output WFD20n,
  output WFD21n,
  output RFD22n,
  output RFD23n
);

wire m55_q8 = ~&{ MADDRBUS[15:10], ~MADDRBUS[9], MADDRBUS[8] };

wire m54_q11 = |MADDRBUS[7:6];
wire m54_q3  = |MADDRBUS[5:4];
wire m54_q6  = m54_q11 | m54_q3;
wire m54_q8 = m55_q8 | m54_q6;

wire m41_q8 = ~&MADDRBUS[5:4];
wire m22_q8 = ~(m41_q8 | m54_q11 | m55_q8);

wire m22_q12 = ~(FD0Xn | RDEn | AB3n);
wire m22_q6  = ~(FD0Xn | WTQEn | AB3n);

wire m120_q13 = ~(MADDRBUS[3] | MADDRBUS[1]);
wire m107_q8 = ~(m120_q13 & MADDRBUS[2] & MADDRBUS[0]);
wire m120_q1 = ~(m107_q8 | FD0Xn);
wire m14_q6 = ~(m120_q1 & E & RWBn);

assign IOSn = m55_q8;
assign FD0Xn = m54_q8;
assign PLTREGn = ~(m22_q8 & MADDRBUS[3]);
assign WFD05n = m14_q6;
assign AB3n = ~MADDRBUS[3];

x74138 x74138_m40 (
  .G2B ( m54_q8       ),
  .G2A ( WTQEn        ),
  .G1  ( ~MADDRBUS[3] ),
  .A   ( MADDRBUS[0]  ),
  .B   ( MADDRBUS[1]  ),
  .C   ( MADDRBUS[2]  ),
  .Y0  ( WFD00n       ),
  .Y1  ( WFD01n       ),
  .Y2  ( WFD02n       ),
  .Y3  ( WFD03n       )
);

x74138 x74138_m52 (
  .G2B ( m54_q8       ),
  .G2A ( RDEn         ),
  .G1  ( ~MADDRBUS[3] ),
  .A   ( MADDRBUS[0]  ),
  .B   ( MADDRBUS[1]  ),
  .C   ( MADDRBUS[2]  ),
  .Y0  ( RFD00n       ),
  .Y1  ( RFD01n       ),
  .Y2  ( RFD02n       ),
  .Y3  ( RFD03n       ),
  .Y4  ( RFD04n       ),
  .Y5  ( RFD05n       )
);

`ifdef DEBUG_ACK
reg debug_rfd01_d, debug_rfd02_d, debug_rfd03_d, debug_rfd04_d;
always @(RFD01n or RFD02n or RFD03n or RFD04n) begin
  if (RFD01n != debug_rfd01_d)
    $display("MACK t=%0t addr=%04X RFD01n=%b EB=%b", $time, MADDRBUS, RFD01n, E);
  if (RFD02n != debug_rfd02_d)
    $display("MACK t=%0t addr=%04X RFD02n=%b EB=%b", $time, MADDRBUS, RFD02n, E);
  if (RFD03n != debug_rfd03_d)
    $display("MACK t=%0t addr=%04X RFD03n=%b EB=%b", $time, MADDRBUS, RFD03n, E);
  if (RFD04n != debug_rfd04_d)
    $display("MACK t=%0t addr=%04X RFD04n=%b EB=%b", $time, MADDRBUS, RFD04n, E);
  debug_rfd01_d = RFD01n;
  debug_rfd02_d = RFD02n;
  debug_rfd03_d = RFD03n;
  debug_rfd04_d = RFD04n;
end
`endif

// $fd37 write strobe (the multi-page register: which VRAM planes the CPU can
// reach, and which of them are displayed).
//
// This used to come from an x74138 enabled by m54_q8, which is FD0Xn -- the
// $fd00-$fd0f decode. With G2A tied to MADDRBUS[3], that decoder's Y7 is $fd07,
// NOT $fd37, so it could never assert for this register: $fd37 was not writable
// at all, read back $00 for ever, and every game's plane selection was silently
// ignored.
//
// m22_q8 is the $fd30-$fd3f decode (bits 7:6 = 00, bits 5:4 = 11, inside IOSn) --
// the same term PLTREGn uses. MADDRBUS[3] separates the palette at $fd38-$fd3f
// from $fd30-$fd37, MADDRBUS[2:0] == 7 picks $fd37, and WTQEn qualifies it as a
// write so the strobe is asserted only while the CPU is driving data.
assign WFD37n = ~(m22_q8 & ~MADDRBUS[3] & (&MADDRBUS[2:0]) & ~WTQEn);

// $fd20-$fd23, the kanji ROM window (P3-3).
//
//   $fd20 write : glyph address, high byte
//   $fd21 write : glyph address, low byte
//   $fd22 read  : first  byte of the 16x16 glyph
//   $fd23 read  : second byte
//
// MAME `kanji_r`/`kanji_w` (fm7.cpp:1054-1094) and CSP `kanjirom.cpp:83` agree
// exactly, including that $fd20/$fd21 are write-only and $fd22/$fd23 are
// read-only. Nothing decodes the write-only pair for reads here, so they fall
// through to core.v's `~IOSn ? 8'hff` default, which is what MAME returns.
//
// The address term: inside IOSn, bits 7:6 = 00 (m54_q11 low), bit 5 = 1,
// bit 4 = 0, bits 3:2 = 00. That is $fd20-$fd23 with bits 1:0 selecting the
// register. Note this deliberately does NOT reuse m22_q8, which is the
// $fd30-$fd3f term.
wire fd2xn = m55_q8 | m54_q11 | ~MADDRBUS[5] | MADDRBUS[4]
                    | MADDRBUS[3] | MADDRBUS[2];

// Writes are qualified by WTQEn so the strobe is asserted only while the CPU is
// driving data, and reads by RDEn -- which core.v wires to RDQEn, the strobe
// that spans the edge mc6809i latches on. Getting that wrong is P0-1, and it
// has already cost this project three separate bugs.
assign WFD20n = ~(~fd2xn & ~MADDRBUS[1] & ~MADDRBUS[0] & ~WTQEn);
assign WFD21n = ~(~fd2xn & ~MADDRBUS[1] &  MADDRBUS[0] & ~WTQEn);
assign RFD22n = ~(~fd2xn &  MADDRBUS[1] & ~MADDRBUS[0] & ~RDEn);
assign RFD23n = ~(~fd2xn &  MADDRBUS[1] &  MADDRBUS[0] & ~RDEn);

// This part was supposed to be implemented in the SOUND page if we follow schematics.

wire [3:0] m32_o1;
wire [3:0] m32_o2;

x74139 x74139_m32(
  .E1 ( ~m22_q12      ),
  .A1 ( MADDRBUS[1:0] ),
  .O1 ( m32_o1        ),
  .E2 ( ~m22_q6       ),
  .A2 ( MADDRBUS[1:0] ),
  .O2 ( m32_o2        )
);

assign RFD0En = m32_o1[2];
assign RFD0Fn = m32_o1[3];
assign WFD0Dn = m32_o2[1];
assign WFD0En = m32_o2[2];
assign WFD0Fn = m32_o2[3];

endmodule
