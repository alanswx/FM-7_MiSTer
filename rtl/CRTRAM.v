
// Video ram, three 1bit color areas for blue, red & green.
// "CRT RAM" page 15 on schematics.

module CRTRAM(
  input CLKSYS,
  input [7:0] SDATABUS,
  output [7:0] CRTRAMDATA,
  input [13:0] SVRADRS,
  input SVWEn,
  input SCASSEL,
  input SVCASBn,
  input SVCASRn,
  input SVCASGn,
  input AV_DISPLAY_PAGE,
  input AV_ACTIVE_PAGE,
  input AV_VRAM_BANK,
  input SDRAMBn,
  input SDRAMRn,
  input SDRAMGn,
  input AV_VRAM_SEL,
  input [1:0] AV_VRAM_PLANE,
  input [13:0] AV_VRAM_ADDR,
  input AV_VRAM_WRITE,
  input [7:0] AV_VRAM_DIN,
  output [7:0] AV_VRAM_DOUT,
  output [7:0] SVDATAB,
  output [7:0] SVDATAR,
  output [7:0] SVDATAG
);

assign CRTRAMDATA =
  ~SDRAMBn ? SVDATAB :
  ~SDRAMRn ? SVDATAR :
  ~SDRAMGn ? SVDATAG :
  8'h0;

// The original FM-7 has one sub/raster port. The AV adds a main-CPU MMR
// aperture to the same physical planes. Use the existing bidirectional dual
// port RAM wrapper so the FPGA keeps the VRAM in block memory.
wire [7:0] av_blue_q, av_red_q, av_green_q;

dpram #(8,15) ramb(
  .clock    ( CLKSYS          ),
  .address_a( {SCASSEL ? AV_ACTIVE_PAGE : AV_DISPLAY_PAGE, SVRADRS} ),
  .data_a   ( SDATABUS        ),
  .wren_a   ( ~SVWEn & ~SDRAMBn ),
  .q_a      ( SVDATAB         ),
  .address_b( {AV_VRAM_BANK, AV_VRAM_ADDR} ),
  .data_b   ( AV_VRAM_DIN     ),
  .wren_b   ( AV_VRAM_WRITE & AV_VRAM_SEL & (AV_VRAM_PLANE == 2'd0) ),
  .q_b      ( av_blue_q       )
);

dpram #(8,15) ramr(
  .clock    ( CLKSYS          ),
  .address_a( {SCASSEL ? AV_ACTIVE_PAGE : AV_DISPLAY_PAGE, SVRADRS} ),
  .data_a   ( SDATABUS        ),
  .wren_a   ( ~SVWEn & ~SDRAMRn ),
  .q_a      ( SVDATAR         ),
  .address_b( {AV_VRAM_BANK, AV_VRAM_ADDR} ),
  .data_b   ( AV_VRAM_DIN     ),
  .wren_b   ( AV_VRAM_WRITE & AV_VRAM_SEL & (AV_VRAM_PLANE == 2'd1) ),
  .q_b      ( av_red_q        )
);

dpram #(8,15) ramg(
  .clock    ( CLKSYS          ),
  .address_a( {SCASSEL ? AV_ACTIVE_PAGE : AV_DISPLAY_PAGE, SVRADRS} ),
  .data_a   ( SDATABUS        ),
  .wren_a   ( ~SVWEn & ~SDRAMGn ),
  .q_a      ( SVDATAG         ),
  .address_b( {AV_VRAM_BANK, AV_VRAM_ADDR} ),
  .data_b   ( AV_VRAM_DIN     ),
  .wren_b   ( AV_VRAM_WRITE & AV_VRAM_SEL & (AV_VRAM_PLANE == 2'd2) ),
  .q_b      ( av_green_q      )
);

assign AV_VRAM_DOUT = (AV_VRAM_PLANE == 2'd0) ? av_blue_q :
                      (AV_VRAM_PLANE == 2'd1) ? av_red_q :
                      (AV_VRAM_PLANE == 2'd2) ? av_green_q : 8'hff;

endmodule
