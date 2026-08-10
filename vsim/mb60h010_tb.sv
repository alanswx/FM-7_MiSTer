module mb60h010_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg resetn = 1'b0;
  reg mode_320 = 1'b0;
  reg display_page = 1'b0;
  reg active_page = 1'b0;
  reg [15:0] addr = 16'd0;
  reg [7:0] data = 8'd0;
  reg sregh_n = 1'b1, sregl_n = 1'b1, adrsel = 1'b0;
  wire [13:0] vram_addr, vram_offset, vram_offset0, vram_offset1;
  wire sftstep;
  wire sftclk, sclk1, sclk2, svideoclk;
  wire svsync_n, shsync_n, svdhalt, sftlod_n, sblank_n, scsync_n;
  wire scassel, vblank_n, hblank_n;

  MB60H010 dut(
    .SRESETn(resetn), .CLKSYS(clk), .SADDRBUS(addr), .SDATA(data),
    .AV_MODE_320(mode_320), .AV_DISPLAY_PAGE(display_page),
    .AV_ACTIVE_PAGE(active_page), .SREGLn(sregl_n), .SREGHn(sregh_n),
    .SADRSEL(adrsel), .SFTCLK(sftclk), .SCLK1(sclk1), .SCLK2(sclk2),
    .SVRADRS(vram_addr), .VRAM_OFFSET(vram_offset),
    .VRAM_OFFSET0(vram_offset0), .VRAM_OFFSET1(vram_offset1),
    .SFTSTEP(sftstep),
    .SVIDEOCLK(svideoclk), .SVSYNCn(svsync_n), .SHSYNCn(shsync_n),
    .SVDHALT(svdhalt), .SFTLODn(sftlod_n), .SBLANKn(sblank_n),
    .SCSYNCn(scsync_n), .SCASSEL(scassel), .VBLANKn(vblank_n),
    .HBLANKn(hblank_n)
  );

  task check_address(input [13:0] actual, input [13:0] wanted, input [255:0] label);
    begin
      if (actual !== wanted) begin
        $display("FAIL %s got=%04x wanted=%04x", label, actual, wanted);
        $fatal(1);
      end
      $display("PASS %s = %04x", label, actual);
    end
  endtask

  task check_bit(input actual, input wanted, input [255:0] label);
    begin
      if (actual !== wanted) begin
        $display("FAIL %s got=%b wanted=%b", label, actual, wanted);
        $fatal(1);
      end
      $display("PASS %s = %b", label, actual);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    resetn = 1'b1;

    // One character cell is eight pixels in 640 mode and sixteen clocks in
    // 320 mode because each logical pixel is presented twice.
    force dut.xx = 10'd32;
    force dut.yy = 9'd1;
    #1;
    check_address(vram_addr, 14'd84, "640 raster address");
    check_bit(scassel, 1'b0, "640 active display");
    check_bit(sftstep, 1'b1, "640 shift step");

    mode_320 = 1'b1;
    #1;
    check_address(vram_addr, 14'd42, "320 raster address");
    check_bit(sftstep, 1'b0, "320 held pixel");

    // During blanking the sub CPU owns the address bus. The same transform as
    // the AV main-CPU aperture wraps low 13 bits in 320 mode.
    force dut.VOFFSET = 14'h0120;
    force dut.xx = 10'd700;
    addr = 16'h1f80;
    #1;
    check_bit(scassel, 1'b1, "320 blanking bus handoff");
    check_address(vram_addr, 14'h00a0, "320 sub VRAM transform");
    force dut.xx = 10'd701;
    #1;
    check_bit(sftstep, 1'b1, "320 advancing pixel");

    // The CPU writes the offset pair selected by the access page; the raster
    // selects the pair named by the display page.
    force dut.SRL[0] = 8'h20;
    force dut.SRH[0] = 8'h01;
    force dut.SRL[1] = 8'h40;
    force dut.SRH[1] = 8'h02;
    active_page = 1'b0;
    display_page = 1'b1;
    force dut.xx = 10'd32;
    force dut.yy = 9'd1;
    release dut.VOFFSET;
    #1;
    check_address(vram_addr, 14'h026a, "display-page offset");
    check_address(vram_offset, 14'h0120, "selected active offset");

    display_page = 1'b0;
    force dut.xx = 10'd700;
    force dut.VOFFSET = 14'h0120;
    mode_320 = 1'b0;
    #1;
    check_address(vram_addr, 14'h20a0, "640 sub VRAM transform");

    release dut.xx;
    release dut.yy;
    release dut.VOFFSET;
    release dut.SRL[0];
    release dut.SRH[0];
    release dut.SRL[1];
    release dut.SRH[1];
    $display("MB60H010 TEST PASS");
    $finish;
  end
endmodule
