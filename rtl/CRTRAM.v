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
  input PAGE_MASKED,      // $FD37 bit for this gun: 1 = CPU access blocked
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
  input DRAW_PORT_EN,
  input DRAW_INHIBIT,
  input [1:0] DRAW_BLOCK,
  input [12:0] DRAW_ADDR,
  input DRAW_WRITE,
  input [7:0] DRAW_DIN,
  output [7:0] CPU_Q,
  output [7:0] DRAW_Q,
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

// While the AV drawing ALU is enabled it swallows the CPU's data byte and
// substitutes its own read-modify-write, so the plain store must not land --
// and that is true of BOTH ways into VRAM, not just the sub CPU's. 77AVEMU
// returns from the MEMTYPE_SUBSYS_VRAM store as soon as hardDraw is enabled
// (`fm77avmemory.cpp:818-828`), whichever CPU is accessing.
//
// The aperture half of this was missing: Argo halts the sub CPU, drives the ALU
// from the main side and blits through the aperture, so every one of its 58656
// aperture writes landed as an opaque store on top of the masked draw that
// should have replaced it, and each sprite painted its bounding box.
wire cpu_write = AV_VRAM_WRITE && AV_VRAM_SEL && (AV_VRAM_PLANE == COLOR_SEL) &&
                 ~DRAW_INHIBIT && ~PAGE_MASKED;
wire sub_write = ~SVWEn && ~SDRAMn && ~DRAW_INHIBIT && ~PAGE_MASKED;
// The drawing ALU borrows the main-CPU aperture port because it is the only
// one that reaches all three guns at a single address.  It holds the port for
// two clocks per byte, so a main-CPU aperture access landing in exactly those
// two clocks of its own bus cycle is displaced; both CPUs' cycles are tens of
// CLKSYS clocks long, so the access still completes on the surrounding clocks.
wire [1:0] port_block = DRAW_PORT_EN ? DRAW_BLOCK : cpu_block;
wire [12:0] port_addr = DRAW_PORT_EN ? DRAW_ADDR : cpu_offset;
wire port_write = DRAW_PORT_EN ? DRAW_WRITE : cpu_write;

dpram #(8,13) ram0(
  .clock(CLKSYS), .address_a(addr0), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd0)), .q_a(qa0),
  .address_b(port_addr), .data_b(DRAW_PORT_EN ? DRAW_DIN : AV_VRAM_DIN),
  .wren_b(port_write && (port_block == 2'd0)), .q_b(qb0)
);
dpram #(8,13) ram1(
  .clock(CLKSYS), .address_a(addr1), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd1)), .q_a(qa1),
  .address_b(port_addr), .data_b(DRAW_PORT_EN ? DRAW_DIN : AV_VRAM_DIN),
  .wren_b(port_write && (port_block == 2'd1)), .q_b(qb1)
);
dpram #(8,13) ram2(
  .clock(CLKSYS), .address_a(addr2), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd2)), .q_a(qa2),
  .address_b(port_addr), .data_b(DRAW_PORT_EN ? DRAW_DIN : AV_VRAM_DIN),
  .wren_b(port_write && (port_block == 2'd2)), .q_b(qb2)
);
dpram #(8,13) ram3(
  .clock(CLKSYS), .address_a(addr3), .data_a(SDATABUS),
  .wren_a(sub_write && (video_block == 2'd3)), .q_a(qa3),
  .address_b(port_addr), .data_b(DRAW_PORT_EN ? DRAW_DIN : AV_VRAM_DIN),
  .wren_b(port_write && (port_block == 2'd3)), .q_b(qb3)
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
assign DRAW_Q = (port_block == 2'd0) ? qb0 :
                (port_block == 2'd1) ? qb1 :
                (port_block == 2'd2) ? qb2 : qb3;

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
  // $FD37 bits 2:0 (FLAGS.v VPAGE1n/2n/3n), 1 = that gun is closed to the CPU.
  // 77AVEMU suppresses the store and returns $FF on the read, for either CPU
  // (fm77avmemory.cpp:830-878 and :539-575). The mask reached nothing here: the
  // masked selects SUBCRTADDR builds are `SBLANKn & SDRAMVn & SCASSEL`, which
  // were identically zero back when SBLANKn was ~SCASSEL, so CRTRAM ignored
  // them. (SBLANKn and SCASSEL are no longer complements -- SCASSEL now hands
  // the sub every cycle the raster is not fetching -- so SVCASBn/RRn/Gn are no
  // longer always zero. They are still unused inside this module; the ports are
  // kept only because core.v wires them.) The raster is deliberately NOT masked
  // -- $FD37 bits 6:4 do that, and
  // PAL.v already handles them.
  input [2:0] VPAGE_MASK,
  input AV_DISPLAY_PAGE,
  input AV_ACTIVE_PAGE,
  input AV_MODE_320,
  input AV_VRAM_BANK,
  input AV_VRAM_SEL,
  input [1:0] AV_VRAM_PLANE,
  input [13:0] AV_VRAM_ADDR,
  input AV_VRAM_WRITE,
  input [7:0] AV_VRAM_DIN,
  input DRAW_PORT_EN,
  input DRAW_INHIBIT,
  input [1:0] DRAW_BLOCK,
  input [12:0] DRAW_ADDR,
  input DRAW_WRITE_B,
  input DRAW_WRITE_R,
  input DRAW_WRITE_G,
  input [7:0] DRAW_DIN_B,
  input [7:0] DRAW_DIN_R,
  input [7:0] DRAW_DIN_G,
  output [7:0] DRAW_Q_B,
  output [7:0] DRAW_Q_R,
  output [7:0] DRAW_Q_G,
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
  .SCASSEL(SCASSEL), .SDRAMn(SDRAMBn),
  .PAGE_MASKED(VPAGE_MASK[0]), .AV_DISPLAY_PAGE(AV_DISPLAY_PAGE),
  .AV_ACTIVE_PAGE(AV_ACTIVE_PAGE), .AV_MODE_320(AV_MODE_320),
  .AV_VRAM_BANK(AV_VRAM_BANK), .AV_VRAM_SEL(AV_VRAM_SEL), .AV_VRAM_PLANE(AV_VRAM_PLANE),
  .AV_VRAM_ADDR(AV_VRAM_ADDR), .AV_VRAM_WRITE(AV_VRAM_WRITE),
  .COLOR_SEL(2'd0), .AV_VRAM_DIN(AV_VRAM_DIN),
  .DRAW_PORT_EN(DRAW_PORT_EN), .DRAW_INHIBIT(DRAW_INHIBIT),
  .DRAW_BLOCK(DRAW_BLOCK), .DRAW_ADDR(DRAW_ADDR),
  .DRAW_WRITE(DRAW_WRITE_B), .DRAW_DIN(DRAW_DIN_B), .CPU_Q(blue_cpu), .DRAW_Q(DRAW_Q_B),
  .Q640(blue_640), .Q3(blue3), .Q2(blue2), .Q1(blue1), .Q0(blue0)
);
AVCRTRAM_COLOR red(
  .CLKSYS(CLKSYS), .SDATABUS(SDATABUS), .SVRADRS(SVRADRS),
  .SVRADRS0(SVRADRS0), .SVRADRS1(SVRADRS1), .SVWEn(SVWEn),
  .SCASSEL(SCASSEL), .SDRAMn(SDRAMRn),
  .PAGE_MASKED(VPAGE_MASK[1]), .AV_DISPLAY_PAGE(AV_DISPLAY_PAGE),
  .AV_ACTIVE_PAGE(AV_ACTIVE_PAGE), .AV_MODE_320(AV_MODE_320),
  .AV_VRAM_BANK(AV_VRAM_BANK), .AV_VRAM_SEL(AV_VRAM_SEL), .AV_VRAM_PLANE(AV_VRAM_PLANE),
  .AV_VRAM_ADDR(AV_VRAM_ADDR), .AV_VRAM_WRITE(AV_VRAM_WRITE),
  .COLOR_SEL(2'd1), .AV_VRAM_DIN(AV_VRAM_DIN),
  .DRAW_PORT_EN(DRAW_PORT_EN), .DRAW_INHIBIT(DRAW_INHIBIT),
  .DRAW_BLOCK(DRAW_BLOCK), .DRAW_ADDR(DRAW_ADDR),
  .DRAW_WRITE(DRAW_WRITE_R), .DRAW_DIN(DRAW_DIN_R), .CPU_Q(red_cpu), .DRAW_Q(DRAW_Q_R),
  .Q640(red_640), .Q3(red3), .Q2(red2), .Q1(red1), .Q0(red0)
);
AVCRTRAM_COLOR green(
  .CLKSYS(CLKSYS), .SDATABUS(SDATABUS), .SVRADRS(SVRADRS),
  .SVRADRS0(SVRADRS0), .SVRADRS1(SVRADRS1), .SVWEn(SVWEn),
  .SCASSEL(SCASSEL), .SDRAMn(SDRAMGn),
  .PAGE_MASKED(VPAGE_MASK[2]), .AV_DISPLAY_PAGE(AV_DISPLAY_PAGE),
  .AV_ACTIVE_PAGE(AV_ACTIVE_PAGE), .AV_MODE_320(AV_MODE_320),
  .AV_VRAM_BANK(AV_VRAM_BANK), .AV_VRAM_SEL(AV_VRAM_SEL), .AV_VRAM_PLANE(AV_VRAM_PLANE),
  .AV_VRAM_ADDR(AV_VRAM_ADDR), .AV_VRAM_WRITE(AV_VRAM_WRITE),
  .COLOR_SEL(2'd2), .AV_VRAM_DIN(AV_VRAM_DIN),
  .DRAW_PORT_EN(DRAW_PORT_EN), .DRAW_INHIBIT(DRAW_INHIBIT),
  .DRAW_BLOCK(DRAW_BLOCK), .DRAW_ADDR(DRAW_ADDR),
  .DRAW_WRITE(DRAW_WRITE_G), .DRAW_DIN(DRAW_DIN_G), .CPU_Q(green_cpu), .DRAW_Q(DRAW_Q_G),
  .Q640(green_640), .Q3(green3), .Q2(green2), .Q1(green1), .Q0(green0)
);

assign CRTRAMDATA = ~SDRAMBn ? (VPAGE_MASK[0] ? 8'hff : blue_640)  :
                    ~SDRAMRn ? (VPAGE_MASK[1] ? 8'hff : red_640)   :
                    ~SDRAMGn ? (VPAGE_MASK[2] ? 8'hff : green_640) : 8'h00;
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

assign AV_VRAM_DOUT = (AV_VRAM_PLANE == 2'd0) ? (VPAGE_MASK[0] ? 8'hff : blue_cpu)  :
                      (AV_VRAM_PLANE == 2'd1) ? (VPAGE_MASK[1] ? 8'hff : red_cpu)   :
                      (AV_VRAM_PLANE == 2'd2) ? (VPAGE_MASK[2] ? 8'hff : green_cpu) : 8'hff;

endmodule
