module PAL_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg resetn = 1'b0;
  reg machine_av = 1'b1;
  reg mode_320 = 1'b0;
  reg [11:0] code = 12'h123;
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
  reg [7:0] mdata = 8'h00;
  wire [7:0] paldata;
  wire [2:0] grb;
  wire [23:0] analog_rgb;

  PAL dut(
    .CLKSYS(clk), .SVDOFFn(svdoff_n), .SBLANKn(sblank_n),
    .SVDATAB(sdatab), .SVDATAR(sdatar), .SVDATAG(sdatag),
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

  initial begin
    // The hardware's reset state is the identity ramp.  Let the sequential
    // reset scrub finish before checking an untouched entry.
    repeat (4097) @(posedge clk);
    resetn = 1'b1;
    #1;
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
    #1;
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
    if (analog_rgb !== 24'h5f_6f_4f) begin
      $display("FAIL digital write disturbed analog palette");
      $fatal(1);
    end
    $display("PAL TEST PASS");
    $finish;
  end
endmodule
