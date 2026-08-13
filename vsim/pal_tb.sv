module PAL_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg resetn = 1'b0;
  reg machine_av = 1'b1;
  reg mode_320 = 1'b0;
  wire [11:0] code;
  reg [15:0] addr = 16'hfd30;
  reg [7:0] data = 8'h00;
  reg pltreg_n = 1'b1;
  reg wtqe_n = 1'b1;
  reg sftclk = 1'b0;
  reg sftlod_n = 1'b1;
  reg svdoff_n = 1'b1;
  reg sblank_n = 1'b1;
  reg dp1 = 1'b0, dp2 = 1'b0, dp3 = 1'b0;
  reg [7:0] sdatab = 8'h00, sdatar = 8'h00, sdatag = 8'h00;
  // 320-mode plane inputs, MSB-first: the bench shifts a real pixel through
  // rather than forcing the internal code register, because the palette is a
  // block RAM whose read is clocked -- forcing the register bypasses it.
  reg [7:0] b3 = 8'h00, b2 = 8'h00, b1 = 8'h00, b0 = 8'h00;
  reg [7:0] r3 = 8'h00, r2 = 8'h00, r1 = 8'h00, r0 = 8'h00;
  reg [7:0] g3 = 8'h00, g2 = 8'h00, g1 = 8'h00, g0 = 8'h00;
  reg [7:0] mdata = 8'h00;
  wire [7:0] paldata;
  wire [2:0] grb;
  wire [23:0] analog_rgb;

  PAL dut(
    .CLKSYS(clk), .SVDOFFn(svdoff_n), .SBLANKn(sblank_n),
    .SVDATAB(sdatab), .SVDATAR(sdatar), .SVDATAG(sdatag),
    .SVDATAB3(b3), .SVDATAB2(b2), .SVDATAB1(b1), .SVDATAB0(b0),
    .SVDATAR3(r3), .SVDATAR2(r2), .SVDATAR1(r1), .SVDATAR0(r0),
    .SVDATAG3(g3), .SVDATAG2(g2), .SVDATAG1(g1), .SVDATAG0(g0),
    .SFTCLK(sftclk), .machine_av(machine_av), .AV_MODE_320(mode_320),
    .SFTSTEP(1'b1), .SFTLODn(sftlod_n), .DPAGE1(dp1), .DPAGE2(dp2),
    .DPAGE3(dp3), .MDATA(mdata), .PALDATA(paldata), .MADDRBUS(addr),
    .PLTREGn(pltreg_n), .RDQEn(1'b1), .WTQEn(wtqe_n), .RESETBn(resetn),
    .grb(grb), .ANALOG_CODE(code), .ANALOG_RGB(analog_rgb)
  );

  task write_reg(input [2:0] regno, input [7:0] value);
    begin
      @(negedge clk);
      addr = 16'hfd30 + {13'd0, regno};
      mdata = value;
      pltreg_n = 1'b0;
      wtqe_n = 1'b0;
      @(posedge clk); #1;
      pltreg_n = 1'b1;
      wtqe_n = 1'b1;
    end
  endtask

  // Present one 12-bit pixel code {G[3:0],R[3:0],B[3:0]} on the plane inputs
  // and clock it through the load/shift path, exactly as the raster does.
  task drive_code(input [11:0] code);
    begin
      g3 = {code[11], 7'd0}; g2 = {code[10], 7'd0};
      g1 = {code[9],  7'd0}; g0 = {code[8],  7'd0};
      r3 = {code[7],  7'd0}; r2 = {code[6],  7'd0};
      r1 = {code[5],  7'd0}; r0 = {code[4],  7'd0};
      b3 = {code[3],  7'd0}; b2 = {code[2],  7'd0};
      b1 = {code[1],  7'd0}; b0 = {code[0],  7'd0};
      sftlod_n = 1'b0; #1;            // load the shift registers
      sftlod_n = 1'b1; #1;
      sftclk = 1'b1; #1;              // latch code + palette entry together
      sftclk = 1'b0; #1;
    end
  endtask

  initial begin
    // The hardware's reset state is the identity ramp.  Let the sequential
    // reset scrub finish before checking an untouched entry.
    repeat (4097) @(posedge clk);
    resetn = 1'b1;
    mode_320 = 1'b1;
    drive_code(12'h123);
    if (analog_rgb !== 24'h2f_1f_3f) begin
      $display("FAIL reset ramp got=%06x wanted=2f1f3f", analog_rgb);
      $fatal(1);
    end
    $display("PASS reset ramp = %06x", analog_rgb);

    // Program index 0x123: B=4, R=5, G=6.  The output is RGB and uses the
    // CSP 4-to-8-bit expansion documented for the analog DAC model.
    write_reg(3'd0, 8'h01);
    write_reg(3'd1, 8'h23);
    write_reg(3'd2, 8'h04);
    write_reg(3'd3, 8'h05);
    write_reg(3'd4, 8'h06);
    drive_code(12'h123);
    if (analog_rgb !== 24'h5f_6f_4f) begin
      $display("FAIL programmed palette got=%06x wanted=5f6f4f", analog_rgb);
      $fatal(1);
    end
    $display("PASS programmed palette = %06x", analog_rgb);

    // An FM-7 digital-palette write must not disturb the AV analog state.
    machine_av = 1'b0;
    @(negedge clk);
    addr = 16'hfd38;
    mdata = 8'h05;
    pltreg_n = 1'b0;
    wtqe_n = 1'b0;
    @(posedge clk); #1;
    pltreg_n = 1'b1;
    wtqe_n = 1'b1;
    machine_av = 1'b1;
    drive_code(12'h123);
    if (analog_rgb !== 24'h5f_6f_4f) begin
      $display("FAIL digital write disturbed analog palette");
      $fatal(1);
    end
    // The code register must track what was shifted in.
    if (code !== 12'h123) begin
      $display("FAIL ANALOG_CODE got=%03x wanted=123", code);
      $fatal(1);
    end
    $display("PASS ANALOG_CODE = %03x", code);
    $display("PAL TEST PASS");
    $finish;
  end
endmodule
