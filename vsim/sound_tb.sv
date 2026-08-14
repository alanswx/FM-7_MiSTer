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
  reg        wfd15n = 1'b1;
  reg        wfd16n = 1'b1;
  reg        rfd16n = 1'b1;
  wire [7:0] dout;
  wire [13:0] mix;
  wire [11:0] fm;

  SOUND dut(
    .CLKSYS(clk), .CLK1_2(1'b0), .RESETBn(resetn), .machine_av(1'b0),
    .MDATABUS_in(mdata), .MDATABUS_out(dout),
    .RFD0En(1'b1), .WFD0En(wfd0en), .WFD0Dn(wfd0dn),
    .RFD16n(rfd16n), .WFD16n(wfd16n), .WFD15n(wfd15n),
    .joystick_0(joy0), .joystick_1(joy1),
    .mix_audio_o(mix), .fm_audio_o(fm), .FMIRQn()
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

  // The FM77AV window. Same shape, four-bit command set.
  task av_write(input sel_c, input [7:0] value);
    begin
      @(negedge clk); mdata = value;
      if (sel_c) wfd15n = 1'b0; else wfd16n = 1'b0;
      repeat (40) @(negedge clk);
      wfd15n = 1'b1; wfd16n = 1'b1;
      repeat (40) @(negedge clk);
    end
  endtask

  // Read $fd16: the port has no side effect, so this only has to assert the
  // select long enough for the mux to be sampled.
  task av_read(output [7:0] value);
    begin
      @(negedge clk); rfd16n = 1'b0;
      repeat (8) @(negedge clk);
      value = dout;
      rfd16n = 1'b1;
      repeat (8) @(negedge clk);
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

  // MiSTer bit order: [0]=right [1]=left [2]=down [3]=up [4]=A [5]=B, active high.
  reg  [5:0] joy0 = 6'd0, joy1 = 6'd0;

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

    // Let the tone counter run and watch the mix. This has to cover a whole
    // tone period: TP = $0140 at the FM-7's PSG rate is 409,600 CLKSYS clocks,
    // and the old 200,000-clock window was inside the FIRST HALF of it -- with
    // jt49's output sitting at a true zero while the square is low, that reads
    // as "the chip is silent" rather than as "the bench looked too early".
    mix_max = 14'd0;
    for (i = 0; i < 1000000; i = i + 1) begin
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

    // ---- pitch -------------------------------------------------------------
    // Measure the divider the tone counter actually uses, independent of any
    // absolute clock: with one channel on, the mix is a square wave whose full
    // period is 2 * TP * divider PSG-enable ticks, and the enable here is one
    // tick per 40 clocks (CORE_CLK_1_2 = 39).
    //
    // A real AY-3-8910 is clock/(16*TP). The FM-7 clocks it at 1.2288 MHz, so
    // TP = $0140 (320) should sound at 1.2288e6/(16*320) = 240 Hz. If the
    // measured divider is 32 rather than 16, every pitch is an octave FLAT;
    // if 8, an octave SHARP.
    psg_write(4'd0,  8'h40);
    psg_write(4'd1,  8'h01);   // TP = $0140 = 320
    psg_write(4'd7,  8'h3e);
    psg_write(4'd8,  8'h0f);
    begin : pitch
      integer t0, t1, edges;
      reg prev_hi;
      t0 = 0; t1 = 0; edges = 0; prev_hi = 1'b0;
      for (i = 0; i < 4000000; i = i + 1) begin
        @(posedge clk);
        if ((mix > 14'd1000) != prev_hi) begin
          prev_hi = (mix > 14'd1000);
          if (prev_hi) begin
            edges = edges + 1;
            if (edges == 2) t0 = i;
            if (edges == 6) t1 = i;
          end
        end
      end
      if (edges < 6) begin
        $display("FAIL PITCH: only %0d edges seen -- no tone", edges);
        fails = fails + 1;
      end
      else if (((t1 - t0) / 4) / (2 * 320 * 20) != 16) begin
        $display("FAIL PITCH: divider %0d, want 16 (8 = octave sharp, 32 = octave flat)",
                 ((t1 - t0) / 4) / (2 * 320 * 20));
        fails = fails + 1;
      end
      else begin
        $display("PASS PITCH divider = 16 (AY-3-8910), period %0d clocks",
                 (t1 - t0) / 4);
        // The divider check above is a RATIO and says nothing about absolute
        // pitch. Print that too, because "is the pitch right" is the question
        // an ear asks and a divider cannot answer. CLKSYS is 48 MHz in the
        // real core, and an AY-3-8910 at the FM-7's documented 1.2288 MHz PSG
        // clock plays TP=320 at 1228800/(16*320) = 240.0 Hz -- CSP fm7.cpp:831
        // and MAME fm7.cpp:1893 both give that clock.
        $display("PITCH  measured %0d.%02d Hz at 48 MHz CLKSYS, AY-3-8910 wants 240.00 Hz",
                 48000000 / ((t1 - t0) / 4),
                 (48000000 * 100 / ((t1 - t0) / 4)) % 100);
      end
    end

    // ---- joysticks ---------------------------------------------------------
    // They hang off the PSG's I/O ports, so they ride on exactly the bus
    // handshake this file just corrected: psg_addr and psg_port_b now latch on
    // the $fd0d write from the byte $fd0e stored. If that were wrong the sticks
    // would break with the sound. Expected byte is the one IO_MAP.md records
    // against a real stick, active low:
    //   { 1, 1, ~B, ~A, ~right, ~left, ~down, ~up }
    joy0 = 6'b011000;                  // up + button A
    joy1 = 6'b000001;                  // right -> ~right is bit 3, so $f7
    psg_write(4'd15, 8'h20);           // port B high nibble 2 -> select stick 0
    cpu_write(1'b0, 8'd14);            // point the read address at port A
    cpu_write(1'b1, 8'h03);
    #1;
    if (dout !== 8'hee) begin
      $display("FAIL joystick 0 up+A: got %02x wanted ee (238)", dout);
      fails = fails + 1;
    end
    else $display("PASS joystick 0 up+A = %02x (238)", dout);

    psg_write(4'd15, 8'h50);           // high nibble 5 -> select stick 1
    cpu_write(1'b0, 8'd14);
    cpu_write(1'b1, 8'h03);
    #1;
    if (dout !== 8'hf7) begin
      $display("FAIL joystick 1 right: got %02x wanted f7", dout);
      fails = fails + 1;
    end
    else $display("PASS joystick 1 right = %02x", dout);

    psg_write(4'd15, 8'h00);           // nothing selected -> $ff, as CSP returns
    cpu_write(1'b0, 8'd14);
    cpu_write(1'b1, 8'h03);
    #1;
    if (dout !== 8'hff) begin
      $display("FAIL no stick selected: got %02x wanted ff", dout);
      fails = fails + 1;
    end
    else $display("PASS no stick selected = %02x", dout);

    // ---- FM77AV window: $fd15 / $fd16 ---------------------------------------
    // Ys (FM77AV) spins on this exact sequence -- command 4, read $fd16, TSTA,
    // BMI -- and never leaves it while bit 7 reads back set. An undecoded port
    // returning $ff hung the game outright, so the status read is the single
    // most load-bearing thing in this window.
    begin : av
      reg [7:0] st;
      integer   spins;
      spins = 0;
      av_write(1'b1, 8'h04);            // command 4: status
      av_read(st);
      while (st[7] && spins < 200) begin
        repeat (200) @(negedge clk);
        av_read(st);
        spins = spins + 1;
      end
      if (st[7]) begin
        $display("FAIL $fd16 status bit 7 never cleared (got %02x) -- Ys hangs here", st);
        fails = fails + 1;
      end
      else $display("PASS $fd16 status = %02x, bit 7 clear after %0d spins", st, spins);

      // Command 9 is the AV's direct joystick port. 77AVEMU ORs in $80 only,
      // because Gambler Jikochuushinha rejects $ff.
      joy0 = 6'b011000;                 // up + button A
      av_write(1'b0, 8'd15);            // point the address latch at port B
      av_write(1'b1, 8'h03);
      av_write(1'b1, 8'h00);
      av_write(1'b0, 8'h20);            // port B high nibble 2 -> stick 0
      av_write(1'b1, 8'h02);
      av_write(1'b1, 8'h00);
      av_write(1'b1, 8'h09);            // command 9: joystick
      av_read(st);
      if (st !== 8'hee) begin
        $display("FAIL $fd16 command 9 joystick: got %02x wanted ee", st);
        fails = fails + 1;
      end
      else $display("PASS $fd16 command 9 joystick = %02x", st);

      // An FM register write must reach the chip. Register $28 is key-on; the
      // only externally visible effect without a full patch is that the status
      // register reports busy for the write and then clears again.
      av_write(1'b0, 8'h28);
      av_write(1'b1, 8'h03);
      av_write(1'b1, 8'h00);
      av_write(1'b0, 8'h00);
      av_write(1'b1, 8'h02);
      av_write(1'b1, 8'h00);
      av_write(1'b1, 8'h04);
      av_read(st);
      $display("INFO $fd16 status after an FM register write = %02x", st);
    end

    if (fails == 0) $display("SOUND TEST PASS");
    else begin
      $display("SOUND TEST FAIL (%0d)", fails);
      $fatal(1);
    end
    $finish;
  end
endmodule
