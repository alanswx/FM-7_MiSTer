module crtram_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg [7:0] sdata = 8'h00;
  reg [13:0] video_addr = 14'd0;
  reg display_page = 1'b0;
  reg active_page = 1'b0;
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

  CRTRAM dut(
    .CLKSYS(clk), .SDATABUS(sdata), .CRTRAMDATA(),
    .SVRADRS(video_addr), .SVWEn(video_we_n), .SCASSEL(scassel),
    .AV_DISPLAY_PAGE(display_page), .AV_ACTIVE_PAGE(active_page),
    .SVCASBn(1'b0), .SVCASRn(1'b0), .SVCASGn(1'b0),
    .SDRAMBn(blue_n), .SDRAMRn(red_n), .SDRAMGn(green_n),
    .AV_VRAM_SEL(av_sel), .AV_VRAM_PLANE(av_plane),
    .AV_VRAM_ADDR(av_addr), .AV_VRAM_WRITE(av_write),
    .AV_VRAM_DIN(av_din), .AV_VRAM_DOUT(av_dout),
    .SVDATAB(video_b), .SVDATAR(video_r), .SVDATAG(video_g)
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

    $display("CRTRAM TEST PASS");
    $finish;
  end
endmodule
