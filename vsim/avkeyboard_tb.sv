module avkeyboard_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg resetn = 1'b0;
  reg machine_av = 1'b1;
  reg [15:0] addr = 16'hd431;
  reg [7:0] din = 8'h00;
  reg swtq_en = 1'b1;
  reg srwb = 1'b0;
  wire [7:0] dout;
  wire sel;

  AVKEYBOARD dut(
    .CLKSYS(clk), .RESETBn(resetn), .machine_av(machine_av),
    .SADDRBUS(addr), .SDATA_in(din), .SWTQEn(swtq_en), .SRWB(srwb),
    .DOUT(dout), .SEL(sel)
  );

  task write_data(input [7:0] d);
    begin
      @(negedge clk); addr = 16'hd431; din = d; swtq_en = 1'b0; srwb = 1'b0;
      @(posedge clk);
      @(negedge clk); swtq_en = 1'b1;
    end
  endtask

  task read_reg(input [5:0] a, output [7:0] d);
    begin
      @(negedge clk); addr = {10'h350, a}; srwb = 1'b1; swtq_en = 1'b1;
      #1 d = dout;
      @(posedge clk);
      @(negedge clk); srwb = 1'b0;
    end
  endtask

  reg [7:0] value;
  integer i;
  initial begin
    repeat (2) @(posedge clk);
    resetn = 1'b1;

    if (!sel) $fatal(1, "D431 should select AV encoder");
    write_data(8'h01);             // get coding
    read_reg(6'h32, value);
    if (value[7] !== 1'b0 || value[0] !== 1'b0)
      $fatal(1, "status did not report ready/ack transition: %02x", value);
    read_reg(6'h31, value);
    if (value !== 8'h00) $fatal(1, "default coding = %02x", value);

    write_data(8'h00);             // set coding
    write_data(8'h02);             // scan-code mode
    write_data(8'h01);             // get coding
    read_reg(6'h31, value);
    if (value !== 8'h02) $fatal(1, "scan coding = %02x", value);

    for (i = 0; i < 4801; i = i + 1) @(posedge clk);
    read_reg(6'h32, value);
    if (value[0] !== 1'b1) $fatal(1, "ack did not return high: %02x", value);

    $display("AVKEYBOARD TEST PASS");
    $finish;
  end
endmodule
