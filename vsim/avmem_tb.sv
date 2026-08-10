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
  wire [7:0] dout;
  wire [7:0] iodout;
  wire       iosel;
  wire       twrsel;

  AVMEM dut(
    .CLKSYS(clk), .RESETBn(resetn), .machine_av(machine_av),
    .bootrom_sel(bootrom_sel), .MADDRBUS(addr), .DIN(din),
    .RWBn(rwb_n), .WTQEn(wtq_en), .RDQEn(rdq_en),
    .DOUT(dout), .IODOUT(iodout), .IOSEL(iosel), .TWRSEL(twrsel)
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

    $display("AVMEM TEST PASS");
    $finish;
  end
endmodule
