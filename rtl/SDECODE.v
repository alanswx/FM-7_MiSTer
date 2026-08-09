
module SDECODE(
  input [15:0] SADDRBUS,
  input SQB,
  input SEB,
  input SBA,
  input SQANDEn,
  input SRWB,
  input VPAGE1n,
  input VPAGE2n,
  input VPAGE3n,
  output SCPUWEn,
  output SRDEn,
  output SROMSELn,
  output SRAM1CSn,
  output SRAM2CSn,
  output SROMDn,
  output SSMEMn,
  output SCRTSWn,
  output SVRACSn,
  output SBUSYSETn,
  output SLEDn,
  output SREGHn,
  output SREGLn,
  output KDATAn,
  output KACKNGn,
  output SIRQCLRn,
  output BUZZERn,
  output ATTENTn,
  output SDRAMGn,
  output SDRAMRn,
  output SDRAMBn,
  output SDRAMV1n,
  output SDRAMV2n,
  output SDRAMV3n
);

wire m86_y6;
wire m80_10 = ~(SQB | SEB);
wire m158_11 = ~&SADDRBUS[15:14];
wire m58_3 = m80_10 | m158_11;
wire m87_3 = SQB | SRWB;
wire m58_6 = m58_3 | m87_3;
// Read qualifier for the sub-CPU I/O decoder (m98 below).
//
// The schematic signal SRDEn is ~(SRWB & SEB), which drops the instant SEB
// falls -- the same instant mc6809i latches the data bus. KDATAn/KACKNGn
// were already high by then and core.v's SDATABUS_in mux had fallen through
// to its 8'hff default, so the sub CPU's keyboard handler read $ffff from
// $d400 instead of the keystroke, decoded it as a function key, and printed
// a garbage string out of the F-key table.
//
// Same bug as the main CPU's RDEn -- see the MDECODE comment in core.v.
// Qualifying with (SEB | SQB) extends the strobe past the latching edge,
// exactly as SRDQEn already does for the sub's ROM/RAM reads.
wire m57_6 = ~(SRWB & SEB);            // schematic SRDEn, exported as-is
wire m57_6_rd = ~(SRWB & (SEB | SQB)); // what actually enables m98
wire m57_8 = ~(&SADDRBUS[15:13] & ~SBA);
wire m58_11 = m57_8 | m80_10;
wire m64_11 = m86_y6 | SADDRBUS[10];
wire m64_8 = m86_y6 | ~SADDRBUS[10];

x74138 m86(
  .G2B ( SBA          ),
  .G2A ( SADDRBUS[13] ),
  .G1  ( SADDRBUS[15] ),
  .A   ( SADDRBUS[11] ),
  .B   ( SADDRBUS[12] ),
  .C   ( SADDRBUS[14] ),
  .Y4  ( SRAM1CSn     ),
  .Y5  ( SRAM2CSn     ),
  .Y6  ( m86_y6       ),
  .Y7  ( SROMDn       )
);

x74138 m87(
  .G2B ( m64_8       ),
  .G2A ( SQANDEn     ),
  .G1  ( SADDRBUS[3] ),
  .A   ( SADDRBUS[0] ),
  .B   ( SADDRBUS[1] ),
  .C   ( SADDRBUS[2] ),
  .Y0  ( SCRTSWn     ),
  .Y1  ( SVRACSn     ),
  .Y2  ( SBUSYSETn   ),
  .Y3  (             ),
  .Y4  (             ),
  .Y5  ( SLEDn       ),
  .Y6  ( SREGHn      ),
  .Y7  ( SREGLn      )
);

x74138 m98(
  .G2B ( m64_8        ),
  .G2A ( m57_6_rd     ),
  .G1  ( ~SADDRBUS[3] ),
  .A   ( SADDRBUS[0]  ),
  .B   ( SADDRBUS[1]  ),
  .C   ( SADDRBUS[2]  ),
  .Y0  ( KDATAn       ),
  .Y1  ( KACKNGn      ),
  .Y2  ( SIRQCLRn     ),
  .Y3  ( BUZZERn      ),
  .Y4  ( ATTENTn      ),
  .Y5  (              ),
  .Y6  (              ),
  .Y7  (              )
);

`ifdef DEBUG_ACK
reg debug_kack_d, debug_sirq_d, debug_attn_d, debug_busy_d;
always @(KACKNGn or SIRQCLRn or ATTENTn or SBUSYSETn) begin
  if (KACKNGn != debug_kack_d)
    $display("SACK t=%0t addr=%04X KACKNGn=%b SEB=%b SQB=%b", $time, SADDRBUS, KACKNGn, SEB, SQB);
  if (SIRQCLRn != debug_sirq_d)
    $display("SACK t=%0t addr=%04X SIRQCLRn=%b SEB=%b SQB=%b", $time, SADDRBUS, SIRQCLRn, SEB, SQB);
  if (ATTENTn != debug_attn_d)
    $display("SACK t=%0t addr=%04X ATTENTn=%b SEB=%b SQB=%b", $time, SADDRBUS, ATTENTn, SEB, SQB);
  if (SBUSYSETn != debug_busy_d)
    $display("SACK t=%0t addr=%04X SBUSYSETn=%b SEB=%b SQB=%b", $time, SADDRBUS, SBUSYSETn, SEB, SQB);
  debug_kack_d = KACKNGn;
  debug_sirq_d = SIRQCLRn;
  debug_attn_d = ATTENTn;
  debug_busy_d = SBUSYSETn;
end
`endif

wire [3:0] m95_y;

x74139 m95(
	.E1 ( SBA             ),
  .A1 ( SADDRBUS[15:14] ),
  .O1 ( m95_y           )
);


assign SCPUWEn = m58_6;
assign SRDEn = m57_6;
assign SROMSELn = m58_11;

assign SDRAMBn = m95_y[0];
assign SDRAMRn = m95_y[1];
assign SDRAMGn = m95_y[2];

assign SDRAMV1n = SDRAMBn | VPAGE1n;
assign SDRAMV2n = SDRAMRn | VPAGE2n;
assign SDRAMV3n = SDRAMGn | VPAGE3n;

assign SSMEMn = m64_11;

endmodule
