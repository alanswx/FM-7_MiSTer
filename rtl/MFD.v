
module MFD(
  input CLKSYS,
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
// past the `~(IOSn | FD1Fn) ? MFD_out` term. Keep this status-window decode
// alive through the latch edge so the CPU sees the controller status bits.
//
// This is P0-1 / P0-4 a third time. Q falls a quarter cycle after E, so (E|Q)
// still covers the latching edge, exactly as RDQEn does for ROM/RAM.
wire m2_8  = ~(m14_6 & ~m13_3 & m7_3 & EAB[0] & (EE | EQ) & ERW);

wire m12_3 = ~(~EIOSn & ~m8_12); // $FD18-$FD1D
wire m12_6 = ~(~EIOSn & ~m2_8);  // $FD1F & E

// The WD chip-select ends at $FD1B, but the FM-7 board registers at
// $FD1C-$FD1F share the same bus strobes. Keep one explicit eight-byte
// window select here so FDC.v receives the side/drive/mode writes without
// treating every high I/O address as an auxiliary access.
wire fd1x = ~EIOSn & (MADDRBUS[15:3] == 13'h1fa3);
wire fd1x_n = ~fd1x;

wire m14_12 = &(~EAB[4:2]);
wire m8_8   = ~(m14_6 & m14_12 & EAB[1]);
wire m14_8  = ~IOSn & ~m8_8 & ~EAB[0]; // $FD02

wire m7_8 = m14_8 & ~ERW;
wire m13_6 = EE & m7_8;

// IRQ mask.
//
// m13_6 is `EE & m7_8` -- an address decode ANDed with E -- so it is a gated
// clock, not a clock. See DERIVED_CLOCKS.md: a LUT-built decode glitches as its
// inputs arrive skewed and every glitch was a spurious write to this register,
// which gates the FDC's interrupt to the CPU.
//
// On CLKSYS now, with the strobe filtered through a shift register so a one or
// two cycle glitch cannot be mistaken for an access. The sample lands two
// CLKSYS cycles after m13_6 rises rather than exactly on the edge: E is
// 1.2288 MHz against 48 MHz, so E-high is ~19 CLKSYS cycles and this is still
// comfortably inside it, but no longer at the very instant the decode settles.
reg m6_q;
reg [2:0] m13_6_sr;
always @(posedge CLKSYS) begin
  m13_6_sr <= { m13_6_sr[1:0], m13_6 };
  if (~ERESETn)                          m6_q <= 1'b1;
  else if (~m13_6_sr[2] & m13_6_sr[1])   m6_q <= EDB[4];
end

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
assign FD_CSn = m12_3 & fd1x_n;

assign MFD_out = ERW & (fd1x | ~m12_3 | ~m12_6) ?
  (fd1x ? FD_Din : {
    ~m12_6 ? ~FD_DRQn   : FD_Din[7],
    ~m12_6 ? ~FD_INTRQn : FD_Din[6],
    FD_Din[5:0]
  }) : 8'h00;

endmodule
