
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
  input AV_DISPLAY_PAGE,
  input AV_ACTIVE_PAGE,
  input SREGLn,
  input SREGHn,
  input SWTQEn,
  input SADRSEL,
  output SFTCLK, // shift register clock
  output SCLK1,
  output SCLK2, // clock for MB88401 MCU
  output [13:0] SVRADRS, // $0000-$3FFF - 7bits multiplexed on schematics
  output [13:0] SVRADRS0,
  output [13:0] SVRADRS1,
  output [13:0] VRAM_OFFSET,
  output [13:0] VRAM_OFFSET0,
  output [13:0] VRAM_OFFSET1,
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
  output HBLANKn,
  output HBLANK_DISP
);

wire _16128KHz; // bad name, it's a 16MHz clock

clk_en #(CORE_CLK_8) u_ck1_en(.ref_clk(CLKSYS), .clk(SCLK1));
clk_en #(CORE_CLK_4) u_ck2_en(.ref_clk(CLKSYS), .clk(SCLK2));
clk_en #(CORE_CLK_2) u_ck3_en(.ref_clk(CLKSYS), .clk(SVIDEOCLK));
clk_en #(CORE_CLK_16) u_ck_en(.ref_clk(CLKSYS), .clk(_16128KHz));

reg [7:0] SRL [0:1];
reg [7:0] SRH [0:1];
wire [13:0] VOFFSET0 = { SRH[0][5:0], SRL[0][7:5], 5'd0 };
wire [13:0] VOFFSET1 = { SRH[1][5:0], SRL[1][7:5], 5'd0 };
wire [13:0] VOFFSET = AV_ACTIVE_PAGE ? VOFFSET1 : VOFFSET0;
wire [13:0] DISPLAY_OFFSET = AV_DISPLAY_PAGE ? VOFFSET1 : VOFFSET0;
assign VRAM_OFFSET = VOFFSET;
assign VRAM_OFFSET0 = VOFFSET0;
assign VRAM_OFFSET1 = VOFFSET1;
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
reg [2:0] offset_lo_sr, offset_hi_sr;
wire offset_lo_wrn = ~((SADDRBUS == 16'hd40f) && ~SWTQEn);
wire offset_hi_wrn = ~((SADDRBUS == 16'hd40e) && ~SWTQEn);
always @(posedge CLKSYS) begin
  if (~SRESETn) begin
    offset_lo_sr <= 3'b111;
    offset_hi_sr <= 3'b111;
    SRL[0] <= 8'd0;
    SRL[1] <= 8'd0;
    SRH[0] <= 8'd0;
    SRH[1] <= 8'd0;
  end
  else begin
    offset_lo_sr <= { offset_lo_sr[1:0], offset_lo_wrn };
    offset_hi_sr <= { offset_hi_sr[1:0], offset_hi_wrn };
    if (offset_lo_sr[2] & ~offset_lo_sr[1]) SRL[AV_ACTIVE_PAGE] <= SDATA;
    if (offset_hi_sr[2] & ~offset_hi_sr[1]) SRH[AV_ACTIVE_PAGE] <= SDATA;
  end
end


reg [9:0] xx;
reg [8:0] yy;

wire [6:0] char_x = AV_MODE_320 ? {1'b0, xx[9:4]} : xx[9:3];

wire [13:0] line_base = AV_MODE_320 ? yy * 14'd40 : yy * 14'd80;
wire [13:0] SRA0 = VOFFSET0 + line_base + {7'd0, char_x};
wire [13:0] SRA1 = VOFFSET1 + line_base + {7'd0, char_x};
wire [13:0] SRA = DISPLAY_OFFSET + line_base + {7'd0, char_x};
wire [13:0] SUBRA_640 = SADDRBUS[13:0] + VOFFSET;
wire [13:0] SUBRA_320 = {SADDRBUS[13],
                         SADDRBUS[12:0] + VOFFSET[12:0]};

// SVRADRS (VRAM address) mux based on blank (SUB or VIDEO)
assign SVRADRS = SCASSEL ? (AV_MODE_320 ? SUBRA_320 : SUBRA_640) : SRA;
assign SVRADRS0 = SCASSEL ? SVRADRS : (AV_MODE_320 ? SRA0 : SRA);
assign SVRADRS1 = SCASSEL ? SVRADRS : (AV_MODE_320 ? SRA1 : SRA);

// Display blanking, delayed to match the pixel pipeline.
//
// HBLANKn above comes straight off xx, but a pixel does not: the raster address
// leaves this module combinationally, CRTRAM returns the byte one CLKSYS later
// (a synchronous-read RAM), SFTLODn is deliberately held off another CLKSYS so
// that byte can settle, and then PAL adds its own registers. The picture that
// comes out is behind the counter that generates the blanking, so the whole
// screen sat that many pixels to the right of where it belonged.
//
// **640 needs three, 320 needs two**, because the two paths differ by exactly
// one register: 640 goes SFT -> qh -> grb, two SFTCLK edges, while 320 goes
// shift-register -> the palette RAM's output register, one. In 320 mode a
// shift clock is half a logical pixel, so its compensation must also be even --
// an odd one would split each doubled pixel across two logical ones.
//
// Nothing in the screenshot suite could see this, because every reference is
// the core's own output and shifts with it. Measured three ways, all agreeing:
// against 77AVEMU the FM-7 F-BASIC banner peaks 99.8% at dx=+3 (97.5% at 0) and
// Wizardry IV 99.2% at dx=+3; Deep Forest, in 320 mode, 96.8% at dx=0 after
// compensation against 20.8% without, and the 2019 demo 99.9% against 10.8%;
// and `tools/raster_phase.py`, which needs no reference at all, put Wizardry
// IV's own VRAM one column right of its own screenshot until this was 3.
//
// Delay the DISPLAY blanking rather than moving HBLANKn: HBLANKn also drives
// SCASSEL, the VRAM arbitration between the raster and the sub CPU, so moving
// it would change every CPU-timing counter in the suite to fix a display-only
// fault. As it is, the eleven-row gate's counters are byte-identical across
// this change and only the screenshots move. The last pixels of a line survive
// the extension: SBLANKn clears the shift registers at xx=640, but those pixels
// are by then already latched in qh/grb, downstream of the clear.
reg [2:0] hblank_disp_sr;
always @(posedge _16128KHz) begin
  if (~SRESETn) hblank_disp_sr <= 3'b111;
  else          hblank_disp_sr <= { hblank_disp_sr[1:0], ~HBLANKn };
end
assign HBLANK_DISP = AV_MODE_320 ? hblank_disp_sr[1] : hblank_disp_sr[2];

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
