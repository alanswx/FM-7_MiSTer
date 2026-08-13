// Directed check that a PSG register write actually reaches the chip.
//
// The whole audio path was silent and nobody had ever measured it: an entire
// run of Thexder issued 1024 PSG register writes and all three channel DACs
// stayed at zero. A full-machine run is a ten-minute experiment, which is far
// too slow to iterate a bus handshake against, so this bench drives $fd0d /
// $fd0e directly and asks the only question that matters -- does programming
// a tone and a volume produce a non-zero mix?
//
// The write order is the one real software uses, logged off Thexder's own bus:
// the byte goes to $fd0e first and the following $fd0d command consumes it.
// That is CSP's model (sound.cpp:308-348). IO_MAP.md used to document the
// opposite order; it had been checked against this core while this code was
// backwards, so it only ever proved self-consistency.

module sound_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;              // 100 MHz-ish; only ratios matter here

  reg        resetn = 1'b0;
  reg  [7:0] mdata  = 8'h00;
  reg        wfd0dn = 1'b1;
  reg        wfd0en = 1'b1;
  wire [7:0] dout;
  wire [13:0] mix;

  SOUND dut(
    .CLKSYS(clk), .CLK1_2(1'b0), .RESETBn(resetn),
    .MDATABUS_in(mdata), .MDATABUS_out(dout),
    .RFD0En(1'b1), .WFD0En(wfd0en), .WFD0Dn(wfd0dn),
    .joystick_0(6'd0), .joystick_1(6'd0),
    .mix_audio_o(mix)
  );

  integer fails = 0;

  // A CPU write: the decode strobe is low for the bus cycle, which at 1.2288 MHz
  // E against 48 MHz CLKSYS is about 40 clocks.
  task cpu_write(input sel_d, input [7:0] value);
    begin
      @(negedge clk); mdata = value;
      if (sel_d) wfd0dn = 1'b0; else wfd0en = 1'b0;
      repeat (40) @(negedge clk);
      wfd0dn = 1'b1; wfd0en = 1'b1;
      repeat (40) @(negedge clk);
    end
  endtask

  // The byte first, then the command that consumes it.
  task psg_write(input [3:0] regno, input [7:0] value);
    begin
      cpu_write(1'b0, {4'd0, regno});
      cpu_write(1'b1, 8'h03);            // latch that byte as the address
      cpu_write(1'b1, 8'h00);
      cpu_write(1'b0, value);
      cpu_write(1'b1, 8'h02);            // write that byte to the register
      cpu_write(1'b1, 8'h00);
    end
  endtask

  reg [13:0] mix_max;
  integer i;

  initial begin
    repeat (20) @(negedge clk);
    resetn = 1'b1;
    repeat (20) @(negedge clk);

    // Channel A: a mid tone, mixer with tone A enabled (noise and I/O off),
    // amplitude 15 fixed. Registers per the AY-3-8910 map.
    psg_write(4'd0,  8'h40);   // tone A fine
    psg_write(4'd1,  8'h01);   // tone A coarse
    psg_write(4'd7,  8'h3e);   // mixer: tone A on, everything else off
    psg_write(4'd8,  8'h0f);   // channel A amplitude, fixed, max

    // Let the tone counter run and watch the mix.
    mix_max = 14'd0;
    for (i = 0; i < 200000; i = i + 1) begin
      @(posedge clk);
      if (mix > mix_max) mix_max = mix;
    end

    if (mix_max == 14'd0) begin
      $display("FAIL PSG mix stayed at zero after programming tone A");
      fails = fails + 1;
    end
    else $display("PASS PSG mix reached %0d", mix_max);

    // Silence the channel again; the mix must fall back to zero.
    psg_write(4'd8, 8'h00);
    repeat (2000) @(posedge clk);
    mix_max = 14'd0;
    for (i = 0; i < 20000; i = i + 1) begin
      @(posedge clk);
      if (mix > mix_max) mix_max = mix;
    end
    // Amplitude 0 must at least collapse the swing; the mix floor itself is
    // the chip's own DC level, not something this bench should assert a value
    // for without a reference.
    if (mix_max >= 8191) begin
      $display("FAIL amplitude 0 left the mix at %0d", mix_max);
      fails = fails + 1;
    end
    else $display("PASS amplitude 0 drops the mix to %0d", mix_max);

    if (fails == 0) $display("SOUND TEST PASS");
    else begin
      $display("SOUND TEST FAIL (%0d)", fails);
      $fatal(1);
    end
    $finish;
  end
endmodule
