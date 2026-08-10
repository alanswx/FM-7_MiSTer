
// 640x200 x 8 colors or 8-level grayscale (80 digits x 25 lines)
// 40 x 12

// H=15.75KHz (16.128/1024)
//  |<- 384 (23.8us) ->|<- 640 (39.7us) ->|
// HSync = <9.9us><sync 4us><9.9us> = 23.8 (159.73px,64.53px,159.73px)


// V=60.1145Hz (15.75KHz/262)
// |<- 62 (3.937ms) ->|<- 200 (12.698ms) ->|
// VSync = <1.524ms (24)><sync 0.508ms(8)><1.505ms(30)>


module MB60H010(
  input SRESETn,
  input CLKSYS,
  input [15:0] SADDRBUS,
  input [7:0] SDATA,
  input AV_MODE_320,
  input SREGLn,
  input SREGHn,
  input SADRSEL,
  output SFTCLK, // shift register clock
  output SCLK1,
  output SCLK2, // clock for MB88401 MCU
  output [13:0] SVRADRS, // $0000-$3FFF - 7bits multiplexed on schematics
  output [13:0] VRAM_OFFSET,
  output SFTSTEP,
  output SVIDEOCLK, // video clock
  output SVSYNCn,
  output SHSYNCn,
  output SVDHALT,
  output SFTLODn, // shift registers load signal
  output SBLANKn,
  output SCSYNCn,
  output SCASSEL,
  output VBLANKn,
  output HBLANKn
);

wire _16128KHz; // bad name, it's a 16MHz clock

clk_en #(CORE_CLK_8) u_ck1_en(.ref_clk(CLKSYS), .clk(SCLK1));
clk_en #(CORE_CLK_4) u_ck2_en(.ref_clk(CLKSYS), .clk(SCLK2));
clk_en #(CORE_CLK_2) u_ck3_en(.ref_clk(CLKSYS), .clk(SVIDEOCLK));
clk_en #(CORE_CLK_16) u_ck_en(.ref_clk(CLKSYS), .clk(_16128KHz));

reg [7:0] SRL;
reg [7:0] SRH;
wire [13:0] VOFFSET = { SRH[5:0], SRL[7:5], 5'd0 };
assign VRAM_OFFSET = VOFFSET;
// 320x200 keeps the 15.75 kHz line timing but presents each logical pixel
// twice on the 16 MHz shift clock. PAL uses this to hold each bit for two
// clocks while the raster address below advances in 40 bytes per line.
assign SFTSTEP = ~AV_MODE_320 | xx[0];

assign SFTCLK = _16128KHz;

// SREGLn/SREGHn are decode strobes, not clocks -- see DERIVED_CLOCKS.md. These
// two registers form VOFFSET, the display scroll offset, so a glitch-induced
// write jumps the whole screen to a wrong address.
//
// On CLKSYS with each strobe filtered through a 3-stage shift register, so a
// one or two cycle decode glitch cannot be mistaken for a write. The capture
// lands two CLKSYS cycles into the strobe rather than exactly on its falling
// edge; the sub's E is far slower than the 48 MHz CLKSYS, so this is still well
// inside the access while no longer sampling at the instant the decode settles.
reg [2:0] sregl_sr, sregh_sr;
always @(posedge CLKSYS) begin
  sregl_sr <= { sregl_sr[1:0], SREGLn };
  sregh_sr <= { sregh_sr[1:0], SREGHn };
  if (sregl_sr[2] & ~sregl_sr[1]) SRL <= SDATA;
  if (sregh_sr[2] & ~sregh_sr[1]) SRH <= SDATA;
end


reg [9:0] xx;
reg [8:0] yy;

wire [6:0] char_x = AV_MODE_320 ? {1'b0, xx[9:4]} : xx[9:3];

wire [13:0] line_base = AV_MODE_320 ? yy * 14'd40 : yy * 14'd80;
wire [13:0] SRA = VOFFSET + line_base + {7'd0, char_x};
wire [13:0] SUBRA_640 = SADDRBUS[13:0] + VOFFSET;
wire [13:0] SUBRA_320 = {SADDRBUS[13],
                         SADDRBUS[12:0] + VOFFSET[12:0]};

// SVRADRS (VRAM address) mux based on blank (SUB or VIDEO)
assign SVRADRS = SCASSEL ? (AV_MODE_320 ? SUBRA_320 : SUBRA_640) : SRA;

assign SHSYNCn = ~(xx >= 10'd800 && xx < 10'd864);
assign SVSYNCn = ~(yy >= 9'd224 && yy < 9'd233);

assign HBLANKn = ~(xx > 10'd639);
assign VBLANKn = ~(yy > 9'd199);
assign SCASSEL = ~(HBLANKn & VBLANKn);
assign SBLANKn = ~SCASSEL;
assign SVDHALT =
  yy < 9'd200 ? (xx < 10'd639 || xx > 10'd930) :
  yy < 9'd261 ? 1'b0 :
  xx > 10'd930;

// Shift-register load, delayed one CLKSYS past the character boundary.
//
// CRTRAM's VRAM is a synchronous-read RAM: q follows addr by one CLKSYS.
// SVRADRS is combinational on xx, so at the instant xx crosses a cell
// boundary the RAM has only just sampled the new address and its output
// still holds the PREVIOUS cell. Loading the shift registers on that same
// edge therefore latched the wrong byte, which showed up as a duplicated
// column in every character ("FUJIITSU" instead of "FUJITSU").
//
// One CLKSYS of delay is a third of a pixel and lets q settle first.
reg sftlodn_d;
always @(posedge CLKSYS)
  sftlodn_d <= AV_MODE_320 ? |xx[3:0] : |xx[2:0];
assign SFTLODn = sftlodn_d;

always @(posedge _16128KHz) begin
`ifdef DEBUG_MB60H010
  // One line per pixel clock -- 16M lines per simulated second.
  // vsim: enable with `make DEBUG_VIDEO=1`.
  $display("xx %x yy %x HBLANKn %x",xx,yy,HBLANKn);
`endif
  if (~SRESETn) begin
    xx <= 0;
    yy <= 0;
  end
  else begin
	  xx <= xx + 10'd1;
	  if (xx == 1023) begin
	    xx <= 10'd0;
	    yy <= yy + 9'd1;
	    if (yy == 261) begin
	      yy <= 9'd0;
	    end
	  end
	end
end
endmodule
