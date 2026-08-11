// Shared video RAM for the FM-7 three-gun raster and FM77AV 320x200 mode.
//
// In 640x200 mode each gun is two 16-KB pages.  In 320x200/4096-colour mode
// those same 32 KB become four 8-KB bit-planes.  Splitting each gun into four
// 8-KB memories lets the FPGA read all four AV planes in parallel without
// duplicating the stored VRAM.

module AVCRTRAM_COLOR(
  input CLKSYS,
  input [7:0] SDATABUS,
  input [13:0] SVRADRS,
  input [13:0] SVRADRS0,
  input [13:0] SVRADRS1,
  input SVWEn,
  input SCASSEL,
  input SDRAMn,
  input AV_DISPLAY_PAGE,
  input AV_ACTIVE_PAGE,
  input AV_MODE_320,
  input AV_VRAM_BANK,
  input AV_VRAM_SEL,
  input [1:0] AV_VRAM_PLANE,
  input [13:0] AV_VRAM_ADDR,
  input AV_VRAM_WRITE,
  input [1:0] COLOR_SEL,
  input [7:0] AV_VRAM_DIN,
  output [7:0] CPU_Q,
  output [7:0] Q640,
  output [7:0] Q3,
  output [7:0] Q2,
  output [7:0] Q1,
  output [7:0] Q0
);

wire [1:0] video_block = {SCASSEL ? AV_ACTIVE_PAGE : AV_DISPLAY_PAGE,
                          SVRADRS[13]};
wire [12:0] video_offset = SVRADRS[12:0];
wire [1:0] cpu_block = {AV_VRAM_BANK, AV_VRAM_ADDR[13]};
wire [12:0] cpu_offset = AV_VRAM_ADDR[12:0];
wire [12:0] raster_offset0 = SVRADRS0[12:0];
wire [12:0] raster_offset1 = SVRADRS1[12:0];

wire [7:0] qa0, qa1, qa2, qa3;
wire [7:0] qb0, qb1, qb2, qb3;

// In 320 mode blocks 0/1 use the page-0 scroll offset and blocks 2/3 use
// page-1's offset.  In 640 mode all four read ports follow the normal
// page/address path; Q640 then selects the active 16-KB page half.
wire [12:0] addr0 = AV_MODE_320 ? raster_offset0 : video_offset;
wire [12:0] addr1 = AV_MODE_320 ? raster_offset0 : video_offset;
wire [12:0] addr2 = AV_MODE_320 ? raster_offset1 : video_offset;
wire [12:0] addr3 = AV_MODE_320 ? raster_offset1 : video_offset;

wire cpu_write = AV_VRAM_WRITE && AV_VRAM_SEL && (AV_VRAM_PLANE == COLOR_SEL);
wire sub_write = ~SVWEn && ~SDRAMn;

dpram #(8,13) ram0(
  .clock(CLKSYS), .address_a(addr0), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd0)), .q_a(qa0),
  .address_b(cpu_offset), .data_b(AV_VRAM_DIN),
  .wren_b(cpu_write && (cpu_block == 2'd0)), .q_b(qb0)
);
dpram #(8,13) ram1(
  .clock(CLKSYS), .address_a(addr1), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd1)), .q_a(qa1),
  .address_b(cpu_offset), .data_b(AV_VRAM_DIN),
  .wren_b(cpu_write && (cpu_block == 2'd1)), .q_b(qb1)
);
dpram #(8,13) ram2(
  .clock(CLKSYS), .address_a(addr2), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd2)), .q_a(qa2),
  .address_b(cpu_offset), .data_b(AV_VRAM_DIN),
  .wren_b(cpu_write && (cpu_block == 2'd2)), .q_b(qb2)
);
dpram #(8,13) ram3(
  .clock(CLKSYS), .address_a(addr3), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd3)), .q_a(qa3),
  .address_b(cpu_offset), .data_b(AV_VRAM_DIN),
  .wren_b(cpu_write && (cpu_block == 2'd3)), .q_b(qb3)
);

assign Q640 = (video_block == 2'd0) ? qa0 :
              (video_block == 2'd1) ? qa1 :
              (video_block == 2'd2) ? qa2 : qa3;
assign Q3 = qa0;
assign Q2 = qa1;
assign Q1 = qa2;
assign Q0 = qa3;
assign CPU_Q = (cpu_block == 2'd0) ? qb0 :
               (cpu_block == 2'd1) ? qb1 :
               (cpu_block == 2'd2) ? qb2 : qb3;

endmodule

module CRTRAM(
  input CLKSYS,
  input [7:0] SDATABUS,
  output [7:0] CRTRAMDATA,
  input [13:0] SVRADRS,
  input [13:0] SVRADRS0,
  input [13:0] SVRADRS1,
  input SVWEn,
  input SCASSEL,
  input SVCASBn,
  input SVCASRn,
  input SVCASGn,
  input SDRAMBn,
  input SDRAMRn,
  input SDRAMGn,
  input AV_DISPLAY_PAGE,
  input AV_ACTIVE_PAGE,
  input AV_MODE_320,
  input AV_VRAM_BANK,
  input AV_VRAM_SEL,
  input [1:0] AV_VRAM_PLANE,
  input [13:0] AV_VRAM_ADDR,
  input AV_VRAM_WRITE,
  input [7:0] AV_VRAM_DIN,
  output [7:0] AV_VRAM_DOUT,
  output [7:0] SVDATAB,
  output [7:0] SVDATAB3,
  output [7:0] SVDATAR,
  output [7:0] SVDATAR3,
  output [7:0] SVDATAG,
  output [7:0] SVDATAG3,
  output [7:0] SVDATAB2,
  output [7:0] SVDATAB1,
  output [7:0] SVDATAB0,
  output [7:0] SVDATAR2,
  output [7:0] SVDATAR1,
  output [7:0] SVDATAR0,
  output [7:0] SVDATAG2,
  output [7:0] SVDATAG1,
  output [7:0] SVDATAG0
);

wire [7:0] blue_cpu, red_cpu, green_cpu;
wire [7:0] blue_640, red_640, green_640;
wire [7:0] blue3, blue2, blue1, blue0;
wire [7:0] red3, red2, red1, red0;
wire [7:0] green3, green2, green1, green0;

AVCRTRAM_COLOR blue(
  .CLKSYS(CLKSYS), .SDATABUS(SDATABUS), .SVRADRS(SVRADRS),
  .SVRADRS0(SVRADRS0), .SVRADRS1(SVRADRS1), .SVWEn(SVWEn),
  .SCASSEL(SCASSEL), .SDRAMn(SDRAMBn), .AV_DISPLAY_PAGE(AV_DISPLAY_PAGE),
  .AV_ACTIVE_PAGE(AV_ACTIVE_PAGE), .AV_MODE_320(AV_MODE_320),
  .AV_VRAM_BANK(AV_VRAM_BANK), .AV_VRAM_SEL(AV_VRAM_SEL), .AV_VRAM_PLANE(AV_VRAM_PLANE),
  .AV_VRAM_ADDR(AV_VRAM_ADDR), .AV_VRAM_WRITE(AV_VRAM_WRITE),
  .COLOR_SEL(2'd0), .AV_VRAM_DIN(AV_VRAM_DIN), .CPU_Q(blue_cpu),
  .Q640(blue_640), .Q3(blue3), .Q2(blue2), .Q1(blue1), .Q0(blue0)
);
AVCRTRAM_COLOR red(
  .CLKSYS(CLKSYS), .SDATABUS(SDATABUS), .SVRADRS(SVRADRS),
  .SVRADRS0(SVRADRS0), .SVRADRS1(SVRADRS1), .SVWEn(SVWEn),
  .SCASSEL(SCASSEL), .SDRAMn(SDRAMRn), .AV_DISPLAY_PAGE(AV_DISPLAY_PAGE),
  .AV_ACTIVE_PAGE(AV_ACTIVE_PAGE), .AV_MODE_320(AV_MODE_320),
  .AV_VRAM_BANK(AV_VRAM_BANK), .AV_VRAM_SEL(AV_VRAM_SEL), .AV_VRAM_PLANE(AV_VRAM_PLANE),
  .AV_VRAM_ADDR(AV_VRAM_ADDR), .AV_VRAM_WRITE(AV_VRAM_WRITE),
  .COLOR_SEL(2'd1), .AV_VRAM_DIN(AV_VRAM_DIN), .CPU_Q(red_cpu),
  .Q640(red_640), .Q3(red3), .Q2(red2), .Q1(red1), .Q0(red0)
);
AVCRTRAM_COLOR green(
  .CLKSYS(CLKSYS), .SDATABUS(SDATABUS), .SVRADRS(SVRADRS),
  .SVRADRS0(SVRADRS0), .SVRADRS1(SVRADRS1), .SVWEn(SVWEn),
  .SCASSEL(SCASSEL), .SDRAMn(SDRAMGn), .AV_DISPLAY_PAGE(AV_DISPLAY_PAGE),
  .AV_ACTIVE_PAGE(AV_ACTIVE_PAGE), .AV_MODE_320(AV_MODE_320),
  .AV_VRAM_BANK(AV_VRAM_BANK), .AV_VRAM_SEL(AV_VRAM_SEL), .AV_VRAM_PLANE(AV_VRAM_PLANE),
  .AV_VRAM_ADDR(AV_VRAM_ADDR), .AV_VRAM_WRITE(AV_VRAM_WRITE),
  .COLOR_SEL(2'd2), .AV_VRAM_DIN(AV_VRAM_DIN), .CPU_Q(green_cpu),
  .Q640(green_640), .Q3(green3), .Q2(green2), .Q1(green1), .Q0(green0)
);

assign CRTRAMDATA = ~SDRAMBn ? blue_640 :
                    ~SDRAMRn ? red_640 :
                    ~SDRAMGn ? green_640 : 8'h00;
assign SVDATAB = blue_640;
assign SVDATAR = red_640;
assign SVDATAG = green_640;
assign SVDATAB3 = blue3;
assign SVDATAR3 = red3;
assign SVDATAG3 = green3;
assign SVDATAB2 = blue2;
assign SVDATAB1 = blue1;
assign SVDATAB0 = blue0;
assign SVDATAR2 = red2;
assign SVDATAR1 = red1;
assign SVDATAR0 = red0;
assign SVDATAG2 = green2;
assign SVDATAG1 = green1;
assign SVDATAG0 = green0;

assign AV_VRAM_DOUT = (AV_VRAM_PLANE == 2'd0) ? blue_cpu :
                      (AV_VRAM_PLANE == 2'd1) ? red_cpu :
                      (AV_VRAM_PLANE == 2'd2) ? green_cpu : 8'hff;

endmodule
