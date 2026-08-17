module crtram_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg [7:0] sdata = 8'h00;
  reg [13:0] video_addr = 14'd0;
  reg [13:0] video_addr0 = 14'd0, video_addr1 = 14'd0;
  reg display_page = 1'b0;
  reg active_page = 1'b0;
  reg vram_bank = 1'b0;
  reg mode_320 = 1'b0;
  reg scassel = 1'b0;
  reg video_we_n = 1'b1;
  reg blue_n = 1'b1;
  reg red_n = 1'b1;
  reg green_n = 1'b1;
  reg av_sel = 1'b0;
  reg [1:0] av_plane = 2'd0;
  reg [13:0] av_addr = 14'd0;
  reg av_write = 1'b0;
  reg [7:0] av_din = 8'h00;
  wire [7:0] av_dout;
  wire [7:0] video_b, video_r, video_g;
  wire [7:0] video_b2, video_b1, video_b0;
  wire [7:0] video_r2, video_r1, video_r0;
  wire [7:0] video_g2, video_g1, video_g0;
  reg [12:0] ref_addr0, ref_addr1;
  reg  [2:0] vpage_mask = 3'b000;   // $FD37 b2:0, 1 = gun closed to the CPU
  wire [7:0] crtram_data;

  CRTRAM dut(
    .CLKSYS(clk), .SDATABUS(sdata), .CRTRAMDATA(crtram_data),
    .SVRADRS(video_addr), .SVRADRS0(video_addr0), .SVRADRS1(video_addr1),
    .SVWEn(video_we_n), .SCASSEL(scassel), .AV_MODE_320(mode_320),
    .AV_DISPLAY_PAGE(display_page), .AV_ACTIVE_PAGE(active_page),
    .AV_VRAM_BANK(vram_bank),
    .SVCASBn(1'b0), .SVCASRn(1'b0), .SVCASGn(1'b0),
    .SDRAMBn(blue_n), .SDRAMRn(red_n), .SDRAMGn(green_n),
    .VPAGE_MASK(vpage_mask),
    .AV_VRAM_SEL(av_sel), .AV_VRAM_PLANE(av_plane),
    .AV_VRAM_ADDR(av_addr), .AV_VRAM_WRITE(av_write),
    .AV_VRAM_DIN(av_din), .AV_VRAM_DOUT(av_dout),
    // The drawing-ALU port is exercised by avhdraw-test; hold it idle here so
    // this bench measures the raster/CPU paths on their own.
    .DRAW_PORT_EN(1'b0), .DRAW_INHIBIT(1'b0), .DRAW_BLOCK(2'd0),
    .DRAW_ADDR(13'd0), .DRAW_WRITE_B(1'b0), .DRAW_WRITE_R(1'b0),
    .DRAW_WRITE_G(1'b0), .DRAW_DIN_B(8'h00), .DRAW_DIN_R(8'h00),
    .DRAW_DIN_G(8'h00), .DRAW_Q_B(), .DRAW_Q_R(), .DRAW_Q_G(),
    .SVDATAB(video_b), .SVDATAR(video_r), .SVDATAG(video_g),
    .SVDATAB2(video_b2), .SVDATAB1(video_b1), .SVDATAB0(video_b0),
    .SVDATAR2(video_r2), .SVDATAR1(video_r1), .SVDATAR0(video_r0),
    .SVDATAG2(video_g2), .SVDATAG1(video_g1), .SVDATAG0(video_g0)
  );

  task check(input [7:0] actual, input [7:0] wanted, input [255:0] label);
    begin
      if (actual !== wanted) begin
        $display("FAIL %s got=%02x wanted=%02x", label, actual, wanted);
        $fatal(1);
      end
      $display("PASS %s = %02x", label, actual);
    end
  endtask

  // 77AVEMU's TransformVRAMAddress() for 320x200 mode preserves the plane
  // high bits and wraps the byte address at 8 KB.  The four local CRTRAM
  // slices correspond to the reference renderer's B3/B2/B1/B0 offsets
  // (0x0000/0x2000/0xc000/0xe000), so all four slices see these low 13 bits.
  function [12:0] ref_320_offset(input [12:0] addr_base,
                                  input [12:0] vram_offset);
    reg [13:0] sum;
    begin
      sum = addr_base + vram_offset;
      ref_320_offset = sum[12:0];
    end
  endfunction

  initial begin
    // Write/read each physical plane through the AV main-CPU port.
    @(negedge clk); av_sel = 1'b1; av_write = 1'b1; av_plane = 2'd0;
      av_addr = 14'h0123; av_din = 8'ha5;
    @(posedge clk); #1;
    av_write = 1'b0; @(posedge clk); #1;
    check(av_dout, 8'ha5, "AV blue plane");

    @(negedge clk); av_plane = 2'd1; av_addr = 14'h0124; av_din = 8'h5a;
      av_write = 1'b1;
    @(posedge clk); #1;
    av_write = 1'b0; @(posedge clk); #1;
    check(av_dout, 8'h5a, "AV red plane");

    @(negedge clk); av_plane = 2'd2; av_addr = 14'h0125; av_din = 8'h3c;
      av_write = 1'b1;
    @(posedge clk); #1;
    av_write = 1'b0; @(posedge clk); #1;
    check(av_dout, 8'h3c, "AV green plane");

    // D430 bit 5 selects the second 64 KB VRAM bank for the main-CPU aperture.
    @(negedge clk); vram_bank = 1'b1; av_plane = 2'd0; av_addr = 14'h0007;
      av_din = 8'h96; av_write = 1'b1; av_sel = 1'b1;
    @(posedge clk); #1 av_write = 1'b0;
    @(posedge clk); #1;
    check(av_dout, 8'h96, "AV VRAM bank 1");

    // In 320 mode the same per-gun 32 KB is four 8 KB bit-planes.  Verify
    // the four CPU address slices arrive at the four parallel raster bytes.
    @(negedge clk); vram_bank = 1'b0; av_plane = 2'd0; av_addr = 14'h0001;
      av_din = 8'h13; av_write = 1'b1; av_sel = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); vram_bank = 1'b0; av_addr = 14'h2001;
      av_din = 8'h24; av_write = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); vram_bank = 1'b1; av_addr = 14'h0001;
      av_din = 8'h35; av_write = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); vram_bank = 1'b1; av_addr = 14'h2001;
      av_din = 8'h46; av_write = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); mode_320 = 1'b1; scassel = 1'b0;
      video_addr0 = 14'h0001; video_addr1 = 14'h0001;
    @(posedge clk); #1;
    check(video_b, 8'h13, "320 B3 raster byte");
    check(video_b2, 8'h24, "320 B2 raster byte");
    check(video_b1, 8'h35, "320 B1 raster byte");
    check(video_b0, 8'h46, "320 B0 raster byte");

    // Reference-derived scroll check.  The first address wraps at 0x2000;
    // the second does not.  The bank bit selects B3/B2 versus B1/B0 through
    // the same four-slice mapping as 77AVEMU's 0x0000/0x2000/0xc000/0xe000
    // layout.
    ref_addr0 = ref_320_offset(13'h1ff0, 13'h0040);
    ref_addr1 = ref_320_offset(13'h0720, 13'h0120);

    @(negedge clk); vram_bank = 1'b0; av_plane = 2'd0;
      av_addr = {1'b0, ref_addr0}; av_din = 8'h53; av_write = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); vram_bank = 1'b0;
      av_addr = {1'b1, ref_addr0}; av_din = 8'h64; av_write = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); vram_bank = 1'b1;
      av_addr = {1'b0, ref_addr1}; av_din = 8'h75; av_write = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); vram_bank = 1'b1;
      av_addr = {1'b1, ref_addr1}; av_din = 8'h86; av_write = 1'b1;
    @(posedge clk); #1; av_write = 1'b0;
    @(negedge clk); video_addr0 = {1'b0, ref_addr0};
      video_addr1 = {1'b0, ref_addr1};
    @(posedge clk); #1;
    check(video_b, 8'h53, "77AVEMU B3 wrapped offset");
    check(video_b2, 8'h64, "77AVEMU B2 wrapped offset");
    check(video_b1, 8'h75, "77AVEMU B1 offset");
    check(video_b0, 8'h86, "77AVEMU B0 offset");

    // The sub/raster port uses the active page during blanking. The raster
    // port then sees the same byte only when the display page is selected.
    @(negedge clk); scassel = 1'b1; active_page = 1'b1;
      video_addr = 14'h0042; sdata = 8'hc3; video_we_n = 1'b0; blue_n = 1'b0;
    @(posedge clk); #1;
    video_we_n = 1'b1; blue_n = 1'b1;
    @(posedge clk); #1;
    check(video_b, 8'hc3, "active VRAM page");

    @(negedge clk); scassel = 1'b0; display_page = 1'b1;
      video_addr = 14'h0042;
    @(posedge clk); #1;
    check(video_b, 8'hc3, "display VRAM page");

    // ---------------------------------------------------------------------
    // $FD37 bits 2:0, the CPU access mask.
    //
    // This reached nothing at all until it was wired here: SUBCRTADDR builds
    // the masked selects as `SBLANKn & SDRAMVn & SCASSEL`, and SBLANKn is
    // ~SCASSEL, so all three were identically zero and CRTRAM ignored them.
    // 77AVEMU suppresses the store and returns $ff on the read, for either CPU
    // (fm77avmemory.cpp:830-878 and :539-575).
    //
    // No title in hand writes $fd37, so the breadth sweep cannot cover this and
    // a directed check is the only evidence there is.
    // ---------------------------------------------------------------------
    @(negedge clk); scassel = 1'b1; active_page = 1'b0; display_page = 1'b0;
      vpage_mask = 3'b000;
      video_addr = 14'h0100; sdata = 8'h5a; video_we_n = 1'b0; blue_n = 1'b0;
    @(posedge clk); #1;
      video_we_n = 1'b1; blue_n = 1'b1;
    @(posedge clk); #1;
    check(video_b, 8'h5a, "unmasked gun takes the sub write");

    // Masked: the write must not land, so the old byte survives.
    @(negedge clk); vpage_mask = 3'b001;
      video_addr = 14'h0100; sdata = 8'ha5; video_we_n = 1'b0; blue_n = 1'b0;
    @(posedge clk); #1;
      video_we_n = 1'b1;
    @(posedge clk); #1;
      vpage_mask = 3'b000; blue_n = 1'b1;
    @(posedge clk); #1;
    check(video_b, 8'h5a, "masked gun refuses the sub write");

    // ...and a masked gun reads back $ff rather than its contents.
    @(negedge clk); vpage_mask = 3'b001; blue_n = 1'b0; video_addr = 14'h0100;
    @(posedge clk); #1;
    check(crtram_data, 8'hff, "masked gun reads back $ff");
    @(negedge clk); vpage_mask = 3'b000;
    @(posedge clk); #1;
    check(crtram_data, 8'h5a, "unmasked gun reads its byte");
    @(negedge clk); blue_n = 1'b1;

    // The mask covers the main-CPU aperture too, not just the sub CPU.
    @(negedge clk); vpage_mask = 3'b010; av_sel = 1'b1; av_plane = 2'd1;
      av_addr = 14'h0100; av_din = 8'h3c; av_write = 1'b1;
    @(posedge clk); #1;
      av_write = 1'b0;
    @(posedge clk); #1;
    check(av_dout, 8'hff, "masked gun reads back $ff through the aperture");
    @(negedge clk); vpage_mask = 3'b000;
    @(posedge clk); #1;
    check(av_dout, 8'h00, "masked gun refused the aperture write");
    @(negedge clk); av_sel = 1'b0;

    $display("CRTRAM TEST PASS");
    $finish;
  end
endmodule
