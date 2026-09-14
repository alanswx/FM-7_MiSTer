// Directed check for KEYBOARD.v: the table entries that were checked against the
// Fujitsu manuals and XM7, what $FD01 reads across a key release and a reset,
// and the auto-repeat timer.
//
//   make keyboard-test
//
// Every check reports, and the run fails at the end if any did, so a regression
// shows everything it broke at once.
module keyboard_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg        resetn = 1'b0;
  reg [10:0] ps2_key = 11'd0;
  reg        rfd00n = 1'b1, rfd01n = 1'b1;
  reg        rpt_mode_stb = 1'b0, rpt_mode_on = 1'b1, rpt_time_stb = 1'b0;
  reg  [7:0] rpt_delay = 8'd0, rpt_interval = 8'd0;
  wire [7:0] mkdata, skdata;
  wire       kstroben, breakn, lpmaskn, tmmask, keyinn;

  KEYBOARD dut(
    .CLKSYS(clk), .RESETBn(resetn), .ps2_key(ps2_key), .MDATA_in(8'h00),
    .SKDATA(skdata), .MKDATA(mkdata), .KDATAn(1'b1), .KACKNGn(1'b1),
    .RFD00n(rfd00n), .RFD01n(rfd01n), .EB(1'b0), .SEB(1'b0), .SCLK2(1'b0),
    .WFD02n(1'b1), .KSTROBEn(kstroben), .BREAKn(breakn), .fm8_switch(1'b1),
    .LPMASKn(lpmaskn), .TMMASK(tmmask), .KEYINn(keyinn),
    .RPT_MODE_STB(rpt_mode_stb), .RPT_MODE_ON(rpt_mode_on),
    .RPT_TIME_STB(rpt_time_stb), .RPT_DELAY(rpt_delay), .RPT_INTERVAL(rpt_interval)
  );

  // One count per code delivered, key press or repeat.
  integer strobes = 0;
  always @(posedge clk) if (dut.key_stb) strobes <= strobes + 1;

  integer errors = 0;
  reg [8:0] v;
  integer n0;   // strobes at the start of a check ('before' is a keyword)

  // PS/2 codes, 9-bit {E0, code}
  localparam [8:0] SHIFT = 9'h012, CTRL = 9'h014, GRAPH = 9'h011, KANA = 9'h111,
                   ESC = 9'h076, BS = 9'h066, TAB = 9'h00d, BACKTICK = 9'h00e,
                   INS = 9'h170, DEL = 9'h171, HOME = 9'h16c, PGUP = 9'h17d,
                   PGDN = 9'h17a, UP = 9'h175, LEFT = 9'h16b, DOWN = 9'h172,
                   RIGHT = 9'h174, KEY_2 = 9'h01e, MINUS = 9'h04e, EQUALS = 9'h055,
                   BACKSLASH = 9'h05d, KEY_A = 9'h01c, RETURN = 9'h05a, F1 = 9'h005;

  task automatic ev(input [8:0] code, input press);
    begin
      @(negedge clk); ps2_key = {~ps2_key[10], press, code};
      repeat (4) @(posedge clk);
    end
  endtask

  task automatic tap(input [8:0] code);
    begin ev(code, 1'b1); ev(code, 1'b0); end
  endtask

  // { $FD00 b7, $FD01 }
  task automatic read_fd(output [8:0] d);
    begin
      @(negedge clk); rfd01n = 1'b0; #1 d[7:0] = mkdata; rfd01n = 1'b1;
      #1 rfd00n = 1'b0; #1 d[8] = mkdata[7]; rfd00n = 1'b1;
    end
  endtask

  task automatic fail(input string what);
    begin errors = errors + 1; $display("FAIL %s", what); end
  endtask

  // Tap a key: exactly one code, and $FD01 still holds it after the release.
  task automatic expect_key(input [8:0] code, input [8:0] want, input string what);
    begin
      n0 = strobes;
      tap(code);
      read_fd(v);
      if (strobes != n0 + 1 || v !== want)
        fail($sformatf("%s: %0d code(s), $FD00b7:$FD01 = %03x, want 1 and %03x",
                       what, strobes - n0, v, want));
    end
  endtask

  task automatic expect_silent(input [8:0] code, input string what);
    reg [8:0] was;
    begin
      read_fd(was);
      n0 = strobes;
      tap(code);
      read_fd(v);
      if (strobes != n0 || v !== was)
        fail($sformatf("%s: %0d code(s), $FD01 %03x -> %03x, want none",
                       what, strobes - n0, was, v));
    end
  endtask

  task automatic wait_ms(input integer ms);
    begin repeat (ms * 48000) @(posedge clk); end   // CLKSYS is 48 MHz
  endtask

  task automatic set_repeat_time(input [7:0] delay_10ms, input [7:0] interval_10ms);
    begin
      @(negedge clk); rpt_delay = delay_10ms; rpt_interval = interval_10ms; rpt_time_stb = 1'b1;
      @(negedge clk); rpt_time_stb = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (4) @(posedge clk);

    read_fd(v);
    if (v !== 9'h0ff) fail($sformatf("power-on $FD00b7:$FD01 = %03x, want 0ff", v));

    // Plain EL and CLS: $05 and $0C in the character code table, System
    // Specifications 1.9.5 p.1-31. They sent $00.
    expect_key(PGUP, 9'h005, "PgUp = EL");
    expect_key(PGDN, 9'h00c, "PgDn = CLS");

    // The SHIFT layer for keys with no upper legend (1.9.6 p.1-32), ']' -> '}',
    // and the shifted cursor codes F-BASIC's sub-system acts on (Phase III
    // Table 3-6-1, printed p.220). All of these sent nothing.
    ev(SHIFT, 1'b1);
    expect_key(ESC,      9'h01b, "SHIFT+ESC");
    expect_key(BS,       9'h008, "SHIFT+BS");
    expect_key(TAB,      9'h009, "SHIFT+TAB");
    expect_key(BACKTICK, 9'h07d, "SHIFT+] = }");
    expect_key(INS,      9'h012, "SHIFT+INS");
    expect_key(DEL,      9'h07f, "SHIFT+DEL");
    expect_key(HOME,     9'h00b, "SHIFT+HOME");
    expect_key(PGUP,     9'h005, "SHIFT+EL");
    expect_key(PGDN,     9'h00c, "SHIFT+CLS");
    expect_key(UP,       9'h019, "SHIFT+UP");
    expect_key(LEFT,     9'h002, "SHIFT+LEFT");
    expect_key(DOWN,     9'h01a, "SHIFT+DOWN");
    expect_key(RIGHT,    9'h006, "SHIFT+RIGHT");
    expect_key(KEY_2,    9'h022, "SHIFT+2 = \"");
    ev(SHIFT, 1'b0);

    // CTRL gives the key's displayed code minus $40, and the control-mode
    // drawing (1.9.9 p.1-34) marks '^' and '\' (yen) -- not '-'.
    ev(CTRL, 1'b1);
    expect_key(EQUALS,    9'h01e, "CTRL+^ = RS");
    expect_key(BACKSLASH, 9'h01c, "CTRL+YEN = FS");
    expect_silent(MINUS,  "CTRL+-");
    expect_key(KEY_A,     9'h001, "CTRL+A");
    ev(CTRL, 1'b0);

    // ESC in the other modes (drawn on the GRAPH layout, 1.9.8 p.1-33).
    ev(GRAPH, 1'b1);
    expect_key(ESC, 9'h01b, "GRAPH+ESC");
    ev(GRAPH, 1'b0);
    tap(KANA);                                   // KANA locks on
    expect_key(ESC, 9'h01b, "KANA+ESC");
    ev(SHIFT, 1'b1);
    expect_key(ESC, 9'h01b, "KANA+SHIFT+ESC");
    ev(SHIFT, 1'b0);
    tap(KANA);                                   // and off
    expect_key(KEY_A, 9'h061, "a after KANA off");

    // $FD01 keeps the last code after a release (FM-Techknow 5-1-5, p.118) --
    // expect_key reads it after the release -- but a reset puts back the
    // power-on value, as XM7's keyboard_reset does.
    expect_key(F1, 9'h101, "PF1");
    @(negedge clk); resetn = 1'b0;
    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (4) @(posedge clk);
    read_fd(v);
    if (v !== 9'h0ff) fail($sformatf("after reset $FD00b7:$FD01 = %03x, want 0ff", v));

    // Auto-repeat: the first repeat 0.7 s after the press (1.9.4 p.1-30).
    n0 = strobes;
    ev(KEY_A, 1'b1);
    wait_ms(690);
    if (strobes != n0 + 1) fail($sformatf("repeat inside 0.7 s: %0d codes", strobes - n0));
    wait_ms(20);
    if (strobes != n0 + 2) fail($sformatf("no repeat by 0.71 s: %0d codes", strobes - n0));
    ev(KEY_A, 1'b0);

    // FM77AV encoder $05 shortening the delay while a key is already past the
    // new value: the repeat is due at once, not after the counter wraps.
    set_repeat_time(8'd255, 8'd255);             // 2.55 s / 2.55 s
    n0 = strobes;
    ev(KEY_A, 1'b1);
    wait_ms(1000);
    set_repeat_time(8'd50, 8'd10);               // 0.5 s / 0.1 s
    wait_ms(50);
    if (strobes != n0 + 2)
      fail($sformatf("repeat time shortened mid-hold: %0d repeat(s) in 50 ms, want 1", strobes - n0 - 1));
    ev(KEY_A, 1'b0);
    set_repeat_time(8'd0, 8'd0);                 // back to 0.7 s / 0.07 s

    if (errors != 0) $fatal(1, "KEYBOARD TEST: %0d failure(s)", errors);
    $display("KEYBOARD TEST PASS");
    $finish;
  end
endmodule
