
module SDECODE(
  input [15:0] SADDRBUS,
  input machine_av,
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
// On the FM77AV the sub I/O page is $D400-$D4FF ONLY.
//
// m98/m87 below decode SADDRBUS[3:0] and nothing between bits 9 and 4, which is
// the FM-7's 16-byte aliasing across the whole $D400-$D7FF MMIO region. The AV
// turns $D500-$D7FF into 768 bytes of hidden RAM (CSP `fm7_display.h:264`,
// `display.cpp:2628,3169`) and narrows the alias to 64 bytes inside the I/O page
// (`display.cpp:2753-2759`), so those reads must have no I/O side effect at all.
//
// They had one, and it was fatal. Every Y-output of m98 is a READ side effect --
// KDATAn, KACKNGn, SIRQCLRn, BUZZERn and ATTENTn -- so a sub-CPU read anywhere
// in $D500-$D7FF whose low nibble happens to be 4 raised the main CPU's
// attention FIRQ. The Fujitsu FM77AV demo disk reads $D7F4 exactly once; that
// spurious FIRQ ran the demo's handler at $0f35, which called the BIOS disk
// read, which asked for cylinder 0 with the head parked on track 14 and hung
// retrying for ever. 77AVEMU never raises attention on that disk at all: zero
// accesses to $D404 in its whole run.
// Bits 5:4 as well as 9:8. The AV's 64-byte alias unit is $D400-$D43F, and
// inside it only $D400-$D40F is this FM-7-compatible block -- $D410-$D42F is
// the drawing ALU and $D430-$D43F the AV registers, both decoded elsewhere.
//
// Leaving 5:4 out is not a smaller version of the same bug, it is a second one.
// m87's Y0 is SCRTSWn, the CRT on/off latch ($D408: read = on, write = off),
// so with 16-byte aliasing every ALU write to $D428 -- the line-draw Y1
// coordinate, 84 of them in ten frames -- switched the display OFF, and the
// screen only came back because some unrelated read in $D500-$D7FF switched it
// on again by the same accident.
wire subio_alias_block = machine_av &
                         (SADDRBUS[9] | SADDRBUS[8] | SADDRBUS[5] | SADDRBUS[4]);
wire m64_8 = m86_y6 | ~SADDRBUS[10] | subio_alias_block;

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
