module smem_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg [15:0] addr = 16'hd800;
  reg [7:0] data_in = 8'h00;
  reg resetn = 1'b0;
  reg machine_av = 1'b1;
  reg [1:0] submon_sel = 2'd0;
  reg submon_status = 1'b0;
  reg sblank_n = 1'b1, svsync_n = 1'b1;
  reg sram1_n = 1'b1, sram2_n = 1'b1;
  reg swtq_n = 1'b1, srdq_n = 1'b1;
  reg sromsel_n = 1'b1, sromd_n = 1'b0;
  wire [7:0] data_out;
  wire [7:0] d430_out;
  wire display_page, active_page;
  wire vram_bank;

  SMEM dut(
    // The $D430 latch sits on the sub-system register bus, which core.v
    // multiplexes between the sub CPU and the main CPU's MMR view of the sub
    // I/O page.  Drive it from the same stimulus the sub CPU would.
    .SREGADDR(addr), .SREGDIN(data_in), .SREGWEn(swtq_n), .alu_busy(1'b0),
    .CLKSYS(clk), .SADDRBUS(addr), .SDATABUS_in(data_in),
    .SDATABUS_out(data_out), .SRAM1CSn(sram1_n), .SRAM2CSn(sram2_n),
    .SWTQEn(swtq_n), .SRDQEn(srdq_n), .SROMSELn(sromsel_n),
    .SROMDn(sromd_n), .machine_av(machine_av), .submon_sel(submon_sel),
    .submon_status(submon_status), .SBLANKn(sblank_n), .SVSYNCn(svsync_n),
    .RESETBn(resetn), .av_d430_out(d430_out),
    .av_display_page(display_page), .av_active_page(active_page),
    .av_vram_bank(vram_bank)
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
    check(d430_out, 8'h7a, "D430 live status");
    font_read(16'hdd30, value);
    check(value, 8'h00, "Type-C font ignores CG bank");

    // Monitor A uses the D430-selected character-generator bank.
    submon_sel = 2'd1;
    font_read(16'hdd30, value);
    check(value, 8'h08, "Monitor-A font bank 1");

    @(negedge clk); addr = 16'hd430; data_in = 8'h61; swtq_n = 1'b0;
    @(posedge clk); #1 swtq_n = 1'b1;
    check({7'd0, display_page}, 8'h01, "AV display page");
    check({7'd0, active_page}, 8'h01, "AV active page");
    check({7'd0, vram_bank}, 8'h01, "AV VRAM bank");

    @(negedge clk); addr = 16'hd430; data_in = 8'h02; swtq_n = 1'b0;
    @(posedge clk); #1 swtq_n = 1'b1;
    font_read(16'hd800, value);
    check(value, 8'h7e, "AV font bank 2");

    $display("SMEM TEST PASS");
    $finish;
  end
endmodule
