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
  reg [7:0] rtc [0:6];
  integer i;
  integer j;
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

    // $D432's unused bits read 1, not 0. Both references build the byte down
    // from $FF (77AVEMU fm77avkeyboard.cpp:723-736, CSP keyboard.cpp:690-702).
    read_reg(6'h32, value);
    if (value[6:1] !== 6'b111111)
      $fatal(1, "status bits 6:1 must read 1, got %02x", value);

    // Command $05 takes TWO parameters. If only one is consumed the second is
    // read as a command and every later command is off by one -- which is how
    // an encoder with no framing loses a whole session.
    write_data(8'h05);
    write_data(8'h46);             // repeat start time
    write_data(8'h05);             // repeat interval, NOT a second command
    write_data(8'h01);             // get coding -- must still answer
    for (i = 0; i < 4801; i = i + 1) @(posedge clk);
    read_reg(6'h31, value);
    if (value !== 8'h02) $fatal(1, "coding after $05 2-param = %02x", value);

    // The real-time clock read: command $80, parameter $00, seven bytes back.
    // The sub monitor's $DF89 loop waits on b7 for each one, so a model that
    // answers nothing wedges the sub CPU and, through BUSY, the main CPU too.
    write_data(8'h80);
    write_data(8'h00);
    for (i = 0; i < 4801; i = i + 1) @(posedge clk);
    read_reg(6'h32, value);
    if (value[7] !== 1'b0) $fatal(1, "no RTC reply waiting: %02x", value);
    for (i = 0; i < 7; i = i + 1) begin
      read_reg(6'h32, value);
      if (value[7] !== 1'b0) $fatal(1, "RTC byte %0d not ready: %02x", i, value);
      read_reg(6'h31, rtc[i]);
      // 77AVEMU paces the bytes 100 us apart (AfterReadD431), so b7 goes back
      // high in between.
      read_reg(6'h32, value);
      if (i < 6 && value[7] !== 1'b1)
        $fatal(1, "RTC byte %0d was not paced: %02x", i, value);
      for (j = 0; j < 4801; j = j + 1) @(posedge clk);
    end
    read_reg(6'h32, value);
    if (value[7] !== 1'b1) $fatal(1, "queue should be empty: %02x", value);
    // 1988-01-01, Friday, 24-hour, and the clock has not yet reached a second.
    // Byte 3 is CSP's packing: wday b7:4, 24-hour b3, PM b2, hour tens b1:0.
    if (rtc[0] !== 8'h88) $fatal(1, "RTC year = %02x",  rtc[0]);
    if (rtc[1] !== 8'h01) $fatal(1, "RTC month = %02x", rtc[1]);
    if (rtc[2] !== 8'h01) $fatal(1, "RTC day = %02x",   rtc[2]);
    if (rtc[3] !== 8'h58) $fatal(1, "RTC wday/hour = %02x", rtc[3]);
    if (rtc[4] !== 8'h00 || rtc[5] !== 8'h00 || rtc[6] !== 8'h00)
      $fatal(1, "RTC time = %02x %02x %02x", rtc[4], rtc[5], rtc[6]);

    // And the encoder is still in sync afterwards.
    write_data(8'h01);
    for (i = 0; i < 4801; i = i + 1) @(posedge clk);
    read_reg(6'h31, value);
    if (value !== 8'h02) $fatal(1, "coding after RTC read = %02x", value);

    $display("AVKEYBOARD TEST PASS");
    $finish;
  end
endmodule
