
module PAL(
  input CLKSYS,
  input SVDOFFn,
  input SBLANKn,
  input [7:0] SVDATAB,
  input [7:0] SVDATAR,
  input [7:0] SVDATAG,
  input SFTCLK,
  input SFTLODn,
  input DPAGE1,
  input DPAGE2,
  input DPAGE3,
  input [7:0] MDATA,
  output reg [7:0] PALDATA,
  input [15:0] MADDRBUS,
  input PLTREGn,
  input RDQEn,
  input WTQEn,
  input RESETBn,
  output reg [2:0] grb
);

wire SFTCLKn = ~SFTCLK;
reg [2:0] rst_idx;

reg [2:0] pal[7:0];
reg [7:0] SFT1;
reg [7:0] SFT2;
reg [7:0] SFT3;

wire m25_3 = ~(SVDOFFn & SBLANKn);

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    pal[rst_idx] <= rst_idx;
    rst_idx <= rst_idx + 3'b1;
  end
  if (~PLTREGn && ~SFTCLKn) begin
    pal[MADDRBUS[2:0]] <= MDATA[2:0];
  end
end

// RDQEn is a decode strobe, not a clock -- see DERIVED_CLOCKS.md. A LUT-built
// decode glitches as its inputs arrive skewed, so this read-back register could
// latch the palette entry at an address that was never on the bus.
//
// On CLKSYS with the strobe filtered through a shift register, so a one or two
// cycle glitch cannot be mistaken for a read. The capture lands two CLKSYS
// cycles into the strobe instead of exactly on its falling edge, which is still
// early in the access -- E is 1.2288 MHz against 48 MHz -- so PALDATA is ready
// long before the CPU latches the bus.
//
// The `posedge SFTCLK` block below is left alone deliberately: SFTCLK is the
// video shift clock, a real clock, not an address decode.
reg [2:0] rdqe_sr;
always @(posedge CLKSYS) begin
  rdqe_sr <= { rdqe_sr[1:0], RDQEn };
  if (rdqe_sr[2] & ~rdqe_sr[1] & ~PLTREGn)   // filtered leading edge of the read
    PALDATA <= pal[MADDRBUS[2:0]];
end

wire clr1 = DPAGE1|m25_3;
wire clr2 = DPAGE2|m25_3;
wire clr3 = DPAGE3|m25_3;

reg qh1;
reg qh2;
reg qh3;

wire [2:0] color = { qh3, qh2, qh1 };

always @(posedge SFTCLK) begin
//$display("pal[color] %x",pal[color]);
  grb <= pal[color];
  qh1 <= SFT1[7];
  qh2 <= SFT2[7];
  qh3 <= SFT3[7];
end

wire sftlod = ~SFTLODn;

always @(posedge SFTCLK, posedge sftlod, posedge clr1) begin
  if (clr1) SFT1 <= 8'd0;
  else if (sftlod) SFT1 <= SVDATAB;
  else SFT1 <= { SFT1[6:0], 1'b0 };
end

always @(posedge SFTCLK, posedge sftlod, posedge clr2) begin
  if (clr2) SFT2 <= 8'd0;
  else if (sftlod) SFT2 <= SVDATAR;
  else SFT2 <= { SFT2[6:0], 1'b0 };
end

always @(posedge SFTCLK, posedge sftlod, posedge clr3) begin
  if (clr3) SFT3 <= 8'd0;
  else if (sftlod) SFT3 <= SVDATAG;
  else SFT3 <= { SFT3[6:0], 1'b0 };
end


endmodule

