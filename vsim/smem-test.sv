module smem_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg [15:0] addr = 16'hd800;
  reg [7:0] data_in = 8'h00;
  reg resetn = 1'b0;
  reg machine_av = 1'b1;
  reg [1:0] submon_sel = 2'd0;
  reg sram1_n = 1'b1, sram2_n = 1'b1;
  reg swtq_n = 1'b1, srdq_n = 1'b1;
  reg sromsel_n = 1'b1, sromd_n = 1'b0;
  wire [7:0] data_out;
  wire [7:0] d430_out;

  SMEM dut(
    .CLKSYS(clk), .SADDRBUS(addr), .SDATABUS_in(data_in),
    .SDATABUS_out(data_out), .SRAM1CSn(sram1_n), .SRAM2CSn(sram2_n),
    .SWTQEn(swtq_n), .SRDQEn(srdq_n), .SROMSELn(sromsel_n),
    .SROMDn(sromd_n), .machine_av(machine_av), .submon_sel(submon_sel),
    .RESETBn(resetn), .av_d430_out(d430_out)
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

  task font_read(input [15:0] a, output [7:0] value);
    begin
      @(negedge clk); addr = a; sromd_n = 1'b0;
      @(posedge clk); #1 value = data_out;
    end
  endtask

  reg [7:0] value;
  initial begin
    #12 resetn = 1'b1;

    // Bank 0 is the AV character generator's base font.
    font_read(16'hd800, value);
    check(value, 8'h00, "AV font bank 0");

    // D430 is a sub-CPU I/O write despite not being in the FM-7 decoder's
    // ordinary low-page strobe range; it selects the four 2 KB font banks.
    @(negedge clk); addr = 16'hd430; data_in = 8'h01; swtq_n = 1'b0;
    @(posedge clk); #1 swtq_n = 1'b1;
    check(d430_out, 8'h6b, "D430 font-bank status");
    font_read(16'hdd30, value);
    check(value, 8'h08, "AV font bank 1");

    @(negedge clk); addr = 16'hd430; data_in = 8'h02; swtq_n = 1'b0;
    @(posedge clk); #1 swtq_n = 1'b1;
    font_read(16'hd800, value);
    check(value, 8'h7e, "AV font bank 2");

    $display("SMEM TEST PASS");
    $finish;
  end
endmodule
