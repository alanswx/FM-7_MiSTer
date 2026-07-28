
module MFD(
  input [15:0] MADDRBUS,
  input [7:0] MDATABUS_out,
  output [7:0] MFD_out,
  input IOSn,
  input EB,
  input QB,
  input RESETBn,
  input RWB,
  output EIRQn,
  output FD1Fn,

  // to floppy disk
  output FD_CSn,
  output [7:0] FD_Dout,
  input [7:0] FD_Din,
  output [2:0] FD_RS,
  input FD_DRQn,
  input FD_INTRQn,
  output FD_MRn,
  output FD_WEn,
  output FD_REn
);

wire [15:0] EAB = MADDRBUS;
wire  [7:0] EDB = MDATABUS_out;

wire EIOSn           = IOSn;
wire EE              = EB;
wire EQ              = QB;
wire ERESETn         = RESETBn;
wire ERW             = RWB;

wire m14_6 = &(~EAB[7:5]);
wire m7_3  = &EAB[4:3];
wire m13_3 = ~&EAB[2:0];
wire m8_12 = ~(m14_6 & m7_3 & m13_3);

// $fd1f's decode is qualified by the read strobe, and it has to span the edge
// on which mc6809i latches the data bus (`always @(negedge E)`). Qualifying on
// E alone deasserts at exactly that edge, so core.v's read mux falls through
// past the `~(IOSn | FD1Fn) ? MFD_out` term -- $fd1f is outside FD_CSn, so the
// next term that matches is the `~IOSn ? 8'hff` default and the CPU latches
// $ff. That reads as "DRQ set, INTRQ set, always", which makes the boot ROM's
// sector-read loop take a byte every pass and never see the command end.
//
// This is P0-1 / P0-4 a third time. Q falls a quarter cycle after E, so (E|Q)
// still covers the latching edge, exactly as RDQEn does for ROM/RAM.
wire m2_8  = ~(m14_6 & ~m13_3 & m7_3 & EAB[0] & (EE | EQ) & ERW);

wire m12_3 = ~(~EIOSn & ~m8_12); // $FD18-$FD1D
wire m12_6 = ~(~EIOSn & ~m2_8);  // $FD1F & E

wire m14_12 = &(~EAB[4:2]);
wire m8_8   = ~(m14_6 & m14_12 & EAB[1]);
wire m14_8  = ~IOSn & ~m8_8 & ~EAB[0]; // $FD02

wire m7_8 = m14_8 & ~ERW;
wire m13_6 = EE & m7_8;

// IRQ mask
reg m6_q;
wire s0 = ~ERESETn;
always @(posedge m13_6 or posedge s0)
  if (s0) m6_q <= 1'b1;
  else m6_q <= EDB[4];

wire m7_6 = EQ & ~ERW;
wire m3_3 = ~(EE & m7_6);
wire m3_6 = ~(ERW & EE);

assign EIRQn = ~(m6_q & ~FD_INTRQn);

// The write data path to the controller. This was declared and never driven,
// which did not matter while rtl/FDC.v was a stub: every write to $fd18-$fd1f
// reached the FDC as $00, so every command byte was $00 (RESTORE) and the drive
// and side latches could never be set. Nothing on a disk could ever be read.
assign FD_Dout = EDB;

assign FD_MRn = ERESETn;
assign FD_WEn = m3_3;
assign FD_REn = m3_6;
assign FD_RS  = EAB[2:0];

assign FD1Fn = m12_6;
assign FD_CSn = m12_3;

assign MFD_out = ERW & ~(m12_3 & m12_6) ? {
  ~m12_6 ? ~FD_DRQn   : FD_Din[7],
  ~m12_6 ? ~FD_INTRQn : FD_Din[6],
  FD_Din[5:0]
} : 8'h00;

endmodule
