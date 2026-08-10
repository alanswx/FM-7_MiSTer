// Small directed check for rtl/AVMEM.v. It exercises the stateful parts of the
// AV map without needing to release the incomplete full-machine AV gate.
module avmem_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg        resetn = 1'b0;
  reg        machine_av = 1'b1;
  reg [1:0]  bootrom_sel = 2'd0;
  reg [15:0] addr = 16'd0;
  reg  [7:0] din = 8'd0;
  reg        rwb_n = 1'b0;
  reg        wtq_en = 1'b1;
  reg        rdq_en = 1'b1;
  reg [13:0] vram_offset = 14'd0;
  reg [7:0]  vram_dout = 8'h00;
  wire [7:0] dout;
  wire [7:0] iodout;
  wire       iosel;
  wire       twrsel;
  wire [1:0] submon_sel;
  wire       submon_reset;
  wire       av_mode_320;
  wire       vram_sel;
  wire [1:0] vram_plane;
  wire [13:0] vram_addr;
  wire       vram_write;
  wire [7:0] vram_din;

  AVMEM dut(
    .CLKSYS(clk), .RESETBn(resetn), .machine_av(machine_av),
    .bootrom_sel(bootrom_sel), .MADDRBUS(addr), .DIN(din),
    .RWBn(rwb_n), .WTQEn(wtq_en), .RDQEn(rdq_en),
    .VRAM_OFFSET(vram_offset),
    .VRAM_DOUT(vram_dout),
    .DOUT(dout), .IODOUT(iodout), .IOSEL(iosel), .TWRSEL(twrsel),
    .SUBMON_SEL(submon_sel), .SUBMON_RESET(submon_reset),
    .AV_MODE_320(av_mode_320),
    .VRAM_SEL(vram_sel), .VRAM_PLANE(vram_plane), .VRAM_ADDR(vram_addr),
    .VRAM_WRITE(vram_write), .VRAM_DIN(vram_din)
  );

  task write_bus(input [15:0] a, input [7:0] d);
    begin
      @(negedge clk); addr = a; din = d; rwb_n = 1'b1; wtq_en = 1'b0;
      @(negedge clk); wtq_en = 1'b1; rwb_n = 1'b0;
    end
  endtask

  task read_bus(input [15:0] a, output [7:0] d);
    begin
      // RDQEn is the active-high read qualifier in this core (the RAM wrapper
      // receives its inverted form as rd_n).
      @(negedge clk); addr = a; rdq_en = 1'b1;
      @(posedge clk); #1 d = dout;
      @(negedge clk); rdq_en = 1'b0;
    end
  endtask

  task check_value(input [7:0] actual, input [7:0] wanted, input [255:0] label);
    begin
      if (actual !== wanted) begin
        $display("FAIL %s got=%02x wanted=%02x", label, actual, wanted);
        $fatal(1);
      end
      $display("PASS %s = %02x", label, actual);
    end
  endtask

  task check_address(input [13:0] actual, input [13:0] wanted, input [255:0] label);
    begin
      if (actual !== wanted) begin
        $display("FAIL %s got=%04x wanted=%04x", label, actual, wanted);
        $fatal(1);
      end
      $display("PASS %s = %04x", label, actual);
    end
  endtask

  reg [7:0] value;
  initial begin
    #22 resetn = 1'b1;

    // MMR disabled: logical $0000 is the FM-7 page at physical $30000.
    write_bus(16'h0000, 8'h12);
    read_bus(16'h0000, value);
    check_value(value, 8'h12, "identity RAM");

    // Select physical bank 1 for segment 0 and turn MMR on. The old value must
    // remain at the identity-mapped page while the translated page is new.
    write_bus(16'hfd80, 8'h01);
    write_bus(16'hfd93, 8'h80);
    write_bus(16'h0000, 8'h34);
    read_bus(16'h0000, value);
    check_value(value, 8'h34, "MMR banked RAM");
    write_bus(16'hfd93, 8'h00);
    read_bus(16'h0000, value);
    check_value(value, 8'h12, "MMR disabled identity RAM");

    // MMR bank $10 is physical $10000, the blue plane at offset zero.
    write_bus(16'hfd80, 8'h10);
    write_bus(16'hfd93, 8'h80);
    addr = 16'h0000;
    #1;
    check_value({7'd0, vram_sel}, 8'h01, "AV VRAM aperture");
    check_value({6'd0, vram_plane}, 8'h00, "AV VRAM blue plane");
    check_value({6'd0, vram_addr[1:0]}, 8'h00, "AV VRAM address");
    check_value(vram_din, din, "AV VRAM write data");

    // FD12 bit 6 selects the AV 320x200 address mask. With a non-zero scroll
    // offset, 640 mode wraps at 16 KB while 320 mode wraps at 8 KB.
    write_bus(16'hfd81, 8'h11);
    vram_offset = 14'h0120;
    addr = 16'h1f80;
    #1;
    check_value({7'd0, av_mode_320}, 8'h00, "AV 640x200 mode");
    check_address(vram_addr, 14'h20a0, "AV 640x200 VRAM transform");
    write_bus(16'hfd12, 8'h40);
    check_value({7'd0, av_mode_320}, 8'h01, "AV 320x200 mode");
    addr = 16'h1f80;
    #1;
    check_address(vram_addr, 14'h00a0, "AV 320x200 VRAM transform");
    addr = 16'hfd12;
    #1;
    check_value(iodout, 8'hff, "AV 320x200 mode status");
    write_bus(16'hfd12, 8'h00);
    check_value({7'd0, av_mode_320}, 8'h00, "AV mode restore");

    // TWR offset 1 maps $7c00 to physical $00100.
    write_bus(16'hfd92, 8'h01);
    write_bus(16'hfd93, 8'h40);
    write_bus(16'h7c00, 8'h56);
    read_bus(16'h7c00, value);
    check_value(value, 8'h56, "TWR window");

    // Reset-seeded AV boot RAM is readable and becomes writable only after
    // $FD93 bit 0 is set.
    write_bus(16'hfd93, 8'h00);
    read_bus(16'hfe00, value);
    check_value(value, 8'h20, "BASIC boot RAM seed");
    write_bus(16'hfd93, 8'h01);
    write_bus(16'hfe00, 8'hab);
    read_bus(16'hfe00, value);
    check_value(value, 8'hab, "writable boot RAM");

    // The AV sub-monitor bank is selected from the main CPU side and is
    // consumed by SMEM for the secondary CPU's $E000-$FFFF window.
    write_bus(16'hfd13, 8'h01);
    check_value({6'd0, submon_sel}, 8'h01, "sub-monitor A select");
    check_value({7'd0, submon_reset}, 8'h01, "sub-monitor reset");
    write_bus(16'hfd13, 8'h02);
    check_value({6'd0, submon_sel}, 8'h02, "sub-monitor B select");
    write_bus(16'hfd13, 8'h00);
    check_value({6'd0, submon_sel}, 8'h00, "sub-monitor C select");

    $display("AVMEM TEST PASS");
    $finish;
  end
endmodule
