
module KEYBOARD(
  input CLKSYS,
  input RESETBn,
  input  [10:0] ps2_key,
  input [7:0] MDATA_in,
  output [7:0] SKDATA,
  output [7:0] MKDATA,
  input KDATAn,
  input KACKNGn,
  input RFD00n,
  input RFD01n,
  input SCLK2,
  input WFD02n,
  output KSTROBEn,
  output BREAKn,
  input fm8_switch,
  output LPMASKn,
  output TMMASK,
  output KEYINn
);

reg press_btn;
reg [8:0] code;
reg [7:0] kdata = 8'd0;
reg P0 = 0;
reg [2:0] m77;
reg m132;
reg [3:0] modif;
reg input_strobe;

assign MKDATA =
  ~RFD01n ? kdata :
  ~RFD00n ? { P0, 6'd0, ~fm8_switch } : 8'h0;

assign SKDATA =
  ~KACKNGn ? kdata :
  ~KDATAn ? { P0, 7'd0 } : 8'h0;

// Modifier state.
//
// This used to live in the combinational block below and was assigned
// `~press_btn`, i.e. it went TRUE when the modifier was RELEASED, so the shift
// branch could never fire while shift was actually held. Tracking it in a
// clocked block instead makes the polarity explicit and removes a
// read-and-write-in-the-same-comb-block loop.
//
//   alt left = GRAPH, alt right = KANA, ctrl left = CTRL, ctrl right = BREAK
reg shift_h, ctrl_h, graph_h, kana_h, break_h;
always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    shift_h <= 1'b0; ctrl_h <= 1'b0; graph_h <= 1'b0; kana_h <= 1'b0;
    break_h <= 1'b0;
  end
  else if (input_strobe) begin
    case (code)
      9'h012, 9'h059: shift_h <= press_btn;  // shift left / right
      9'h014:         ctrl_h  <= press_btn;  // ctrl left
      9'h011:         graph_h <= press_btn;  // alt left  -> GRAPH
      // KANA is a LOCKING key on the real machine, not a held modifier: CSP
      // toggles it on press and drives a keyboard LED from it
      // (keyboard.cpp:117-125, alongside CAPS which behaves the same way).
      // Holding it would be wrong -- software expects kana mode to persist
      // across keystrokes until it is pressed again.
      9'h111: if (press_btn) kana_h <= ~kana_h;   // alt right -> KANA (lock)
      9'h114:         break_h <= press_btn;       // ctrl right -> BREAK
    endcase
  end
end

// BREAK is a key, not a character: it drives FIRQ on the main CPU and reads
// back on $fd04 bit 1, and sends no scancode. MAME asserts M6809_FIRQ_LINE and
// sets its break flag together (fm7.cpp:1183-1189); TIMER.v already ANDs
// BREAKn into FIRQn and reports it, so wiring the key here is the whole fix.
assign BREAKn = ~break_h;

always @* begin

  if (input_strobe) begin

    // Modifier precedence is CTRL > GRAPH > KANA > plain, with SHIFT selecting
    // the "_shift" variant within each. That is exactly CSP's order in
    // KEYBOARD::scan2fmkeycode (keyboard.cpp:157-183), and it matters: with
    // both CTRL and GRAPH down a real machine sends the control code.
    //
    // The tables below are transcribed from
    // refs/common-src-project/src/vm/fm7/keyboard_tables.h, which is keyed on
    // the FM-7's own physical key number ("phy", an index into vk_matrix_106).
    // Our codes are PS/2 sets, so each entry is translated through the same
    // PS/2 -> physical-key correspondence the unshifted table below already
    // establishes. Keys the FM-7 has and a PS/2 keyboard does not -- KANJI,
    // the JIS \_ key next to right shift, CONVERT/NONCONVERT and the numeric
    // keypad -- have no entry here, which is why some phy numbers are absent.

    // CTRL. For the letters this is just code & $1f; the rest are the JIS
    // punctuation positions that carry the remaining control codes.
    if (ctrl_h && press_btn) begin
      case (code)
        9'h15: begin { P0, kdata } = 9'h11; end // ctrl-Q
        9'h1d: begin { P0, kdata } = 9'h17; end // ctrl-W
        9'h24: begin { P0, kdata } = 9'h05; end // ctrl-E
        9'h2d: begin { P0, kdata } = 9'h12; end // ctrl-R
        9'h2c: begin { P0, kdata } = 9'h14; end // ctrl-T
        9'h35: begin { P0, kdata } = 9'h19; end // ctrl-Y
        9'h3c: begin { P0, kdata } = 9'h15; end // ctrl-U
        9'h43: begin { P0, kdata } = 9'h09; end // ctrl-I
        9'h44: begin { P0, kdata } = 9'h0f; end // ctrl-O
        9'h4d: begin { P0, kdata } = 9'h10; end // ctrl-P
        9'h1c: begin { P0, kdata } = 9'h01; end // ctrl-A
        9'h1b: begin { P0, kdata } = 9'h13; end // ctrl-S
        9'h23: begin { P0, kdata } = 9'h04; end // ctrl-D
        9'h2b: begin { P0, kdata } = 9'h06; end // ctrl-F
        9'h34: begin { P0, kdata } = 9'h07; end // ctrl-G
        9'h33: begin { P0, kdata } = 9'h08; end // ctrl-H
        9'h3b: begin { P0, kdata } = 9'h0a; end // ctrl-J
        9'h42: begin { P0, kdata } = 9'h0b; end // ctrl-K
        9'h4b: begin { P0, kdata } = 9'h0c; end // ctrl-L
        9'h1a: begin { P0, kdata } = 9'h1a; end // ctrl-Z
        9'h22: begin { P0, kdata } = 9'h18; end // ctrl-X
        9'h21: begin { P0, kdata } = 9'h03; end // ctrl-C
        9'h2a: begin { P0, kdata } = 9'h16; end // ctrl-V
        9'h32: begin { P0, kdata } = 9'h02; end // ctrl-B
        9'h31: begin { P0, kdata } = 9'h0e; end // ctrl-N
        9'h3a: begin { P0, kdata } = 9'h0d; end // ctrl-M

        9'h54: begin { P0, kdata } = 9'h00; end // ctrl-@ -> NUL
        9'h5b: begin { P0, kdata } = 9'h1b; end // ctrl-[ -> ESC
        9'h0e: begin { P0, kdata } = 9'h1d; end // ctrl-] -> GS
        9'h4e: begin { P0, kdata } = 9'h1e; end // ctrl-- -> RS
        9'h55: begin { P0, kdata } = 9'h1c; end // ctrl-^ -> FS
      endcase
    end

    // GRAPH. The FM-7's semigraphics set, $80-$fd. graph_shift_key is
    // byte-identical to graph_key except for the four cursor keys and the
    // function keys, so the differences are folded in inline rather than
    // duplicating a 50-entry table.
    else if (graph_h && press_btn) begin
      case (code)
        9'h16: begin { P0, kdata } = 9'h0f9; end // 1
        9'h1e: begin { P0, kdata } = 9'h0fa; end // 2
        9'h26: begin { P0, kdata } = 9'h0fb; end // 3
        9'h25: begin { P0, kdata } = 9'h0fc; end // 4
        9'h2e: begin { P0, kdata } = 9'h0f2; end // 5
        9'h36: begin { P0, kdata } = 9'h0f3; end // 6
        9'h3d: begin { P0, kdata } = 9'h0f4; end // 7
        9'h3e: begin { P0, kdata } = 9'h0f5; end // 8
        9'h46: begin { P0, kdata } = 9'h0f6; end // 9
        9'h45: begin { P0, kdata } = 9'h0f7; end // 0
        9'h4e: begin { P0, kdata } = 9'h08c; end // -
        9'h55: begin { P0, kdata } = 9'h08b; end // ^
        9'h5d: begin { P0, kdata } = 9'h0f1; end // \
        9'h66: begin { P0, kdata } = 9'h008; end // backspace
        9'h0d: begin { P0, kdata } = 9'h009; end // tab

        9'h15: begin { P0, kdata } = 9'h0fd; end // q
        9'h1d: begin { P0, kdata } = 9'h0f8; end // w
        9'h24: begin { P0, kdata } = 9'h0e4; end // e
        9'h2d: begin { P0, kdata } = 9'h0e5; end // r
        9'h2c: begin { P0, kdata } = 9'h09c; end // t
        9'h35: begin { P0, kdata } = 9'h09d; end // y
        9'h3c: begin { P0, kdata } = 9'h0f0; end // u
        9'h43: begin { P0, kdata } = 9'h0e8; end // i
        9'h44: begin { P0, kdata } = 9'h0e9; end // o
        9'h4d: begin { P0, kdata } = 9'h08d; end // p
        9'h54: begin { P0, kdata } = 9'h08a; end // @
        9'h5b: begin { P0, kdata } = 9'h0ed; end // [
        9'h5a: begin { P0, kdata } = 9'h00d; end // enter

        9'h1c: begin { P0, kdata } = 9'h095; end // a
        9'h1b: begin { P0, kdata } = 9'h096; end // s
        9'h23: begin { P0, kdata } = 9'h0e6; end // d
        9'h2b: begin { P0, kdata } = 9'h0e7; end // f
        9'h34: begin { P0, kdata } = 9'h09e; end // g
        9'h33: begin { P0, kdata } = 9'h09f; end // h
        9'h3b: begin { P0, kdata } = 9'h0ea; end // j
        9'h42: begin { P0, kdata } = 9'h0eb; end // k
        9'h4b: begin { P0, kdata } = 9'h08e; end // l
        9'h4c: begin { P0, kdata } = 9'h099; end // ;
        9'h52: begin { P0, kdata } = 9'h094; end // :
        9'h0e: begin { P0, kdata } = 9'h0ec; end // ]

        9'h1a: begin { P0, kdata } = 9'h080; end // z
        9'h22: begin { P0, kdata } = 9'h081; end // x
        9'h21: begin { P0, kdata } = 9'h082; end // c
        9'h2a: begin { P0, kdata } = 9'h083; end // v
        9'h32: begin { P0, kdata } = 9'h084; end // b
        9'h31: begin { P0, kdata } = 9'h085; end // n
        9'h3a: begin { P0, kdata } = 9'h086; end // m
        9'h41: begin { P0, kdata } = 9'h087; end // ,
        9'h49: begin { P0, kdata } = 9'h088; end // .
        9'h4a: begin { P0, kdata } = 9'h097; end // /
        // The keypad '/' is its own physical key on an FM-7 (phy $37) and
        // graph_key gives it $91, not the main '/' key's $97. The unshifted
        // table conflates the two because they both type '/'; under GRAPH they
        // differ. The rest of the numeric keypad has no PS/2 mapping at all.
        9'h14a: begin { P0, kdata } = 9'h091; end // keypad /

        9'h29: begin { P0, kdata } = 9'h020; end // spacebar
        9'h170: begin { P0, kdata } = 9'h012; end // insert
        9'h17d: begin { P0, kdata } = 9'h005; end // page up  (EL)
        9'h17a: begin { P0, kdata } = 9'h00c; end // page down (CLS)
        9'h171: begin { P0, kdata } = 9'h07f; end // delete
        9'h16c: begin { P0, kdata } = 9'h00b; end // home

        // The four cursor keys are the only entries where graph_shift_key
        // differs from graph_key.
        9'h175: begin { P0, kdata } = shift_h ? 9'h019 : 9'h01e; end // up
        9'h172: begin { P0, kdata } = shift_h ? 9'h01a : 9'h01f; end // down
        9'h16b: begin { P0, kdata } = shift_h ? 9'h002 : 9'h01d; end // left
        9'h174: begin { P0, kdata } = shift_h ? 9'h006 : 9'h01c; end // right

        // graph_shift_key has no function-key entries at all.
        9'h05: begin if (!shift_h) { P0, kdata } = 9'h101; end // f1
        9'h06: begin if (!shift_h) { P0, kdata } = 9'h102; end // f2
        9'h04: begin if (!shift_h) { P0, kdata } = 9'h103; end // f3
        9'h0c: begin if (!shift_h) { P0, kdata } = 9'h104; end // f4
        9'h03: begin if (!shift_h) { P0, kdata } = 9'h105; end // f5
        9'h0b: begin if (!shift_h) { P0, kdata } = 9'h106; end // f6
        9'h83: begin if (!shift_h) { P0, kdata } = 9'h107; end // f7
        9'h0a: begin if (!shift_h) { P0, kdata } = 9'h108; end // f8
        9'h01: begin if (!shift_h) { P0, kdata } = 9'h109; end // f9
        9'h09: begin if (!shift_h) { P0, kdata } = 9'h10a; end // f10
      endcase
    end

    // KANA (locking). Half-width katakana, JIS X 0201 $a1-$df. Shifted gives
    // the small kana and the two voicing marks, which is a genuinely different
    // and much smaller table, so it is kept separate.
    else if (kana_h && shift_h && press_btn) begin
      case (code)
        9'h26: begin { P0, kdata } = 9'h0a7; end // 3 -> small a
        9'h25: begin { P0, kdata } = 9'h0a9; end // 4 -> small i
        9'h2e: begin { P0, kdata } = 9'h0aa; end // 5 -> small u
        9'h36: begin { P0, kdata } = 9'h0ab; end // 6 -> small e
        9'h3d: begin { P0, kdata } = 9'h0ac; end // 7 -> small o
        9'h3e: begin { P0, kdata } = 9'h0ad; end // 8 -> small ya
        9'h46: begin { P0, kdata } = 9'h0ae; end // 9 -> small yu
        9'h45: begin { P0, kdata } = 9'h0a6; end // 0 -> small wo
        9'h24: begin { P0, kdata } = 9'h0a8; end // e -> small yo
        9'h5b: begin { P0, kdata } = 9'h0a2; end // [ -> opening bracket
        9'h0e: begin { P0, kdata } = 9'h0a3; end // ] -> closing bracket
        9'h1a: begin { P0, kdata } = 9'h0af; end // z -> small tsu
        9'h41: begin { P0, kdata } = 9'h0a4; end // , -> ideographic comma
        9'h49: begin { P0, kdata } = 9'h0a1; end // . -> ideographic full stop
        9'h4a: begin { P0, kdata } = 9'h0a5; end // / -> middle dot
        9'h14a: begin { P0, kdata } = 9'h02f; end // keypad / (phy $37) stays '/'

        9'h66: begin { P0, kdata } = 9'h008; end // backspace
        9'h0d: begin { P0, kdata } = 9'h009; end // tab
        9'h5a: begin { P0, kdata } = 9'h00d; end // enter
        9'h29: begin { P0, kdata } = 9'h020; end // spacebar
        9'h170: begin { P0, kdata } = 9'h012; end // insert
        9'h17d: begin { P0, kdata } = 9'h005; end // page up
        9'h17a: begin { P0, kdata } = 9'h00c; end // page down
        9'h171: begin { P0, kdata } = 9'h07f; end // delete
        9'h16c: begin { P0, kdata } = 9'h00b; end // home
        9'h175: begin { P0, kdata } = 9'h019; end // up
        9'h172: begin { P0, kdata } = 9'h01a; end // down
        9'h16b: begin { P0, kdata } = 9'h002; end // left
        9'h174: begin { P0, kdata } = 9'h006; end // right
      endcase
    end

    else if (kana_h && press_btn) begin
      case (code)
        9'h16: begin { P0, kdata } = 9'h0c7; end // 1 -> nu
        9'h1e: begin { P0, kdata } = 9'h0cc; end // 2 -> fu
        9'h26: begin { P0, kdata } = 9'h0b1; end // 3 -> a
        9'h25: begin { P0, kdata } = 9'h0b3; end // 4 -> u
        9'h2e: begin { P0, kdata } = 9'h0b4; end // 5 -> e
        9'h36: begin { P0, kdata } = 9'h0b5; end // 6 -> o
        9'h3d: begin { P0, kdata } = 9'h0d4; end // 7 -> ya
        9'h3e: begin { P0, kdata } = 9'h0d5; end // 8 -> yu
        9'h46: begin { P0, kdata } = 9'h0d6; end // 9 -> yo
        9'h45: begin { P0, kdata } = 9'h0dc; end // 0 -> wa
        9'h4e: begin { P0, kdata } = 9'h0ce; end // - -> ho
        9'h55: begin { P0, kdata } = 9'h0cd; end // ^ -> he
        9'h5d: begin { P0, kdata } = 9'h0b0; end // \ -> prolonged sound mark
        9'h66: begin { P0, kdata } = 9'h008; end // backspace
        9'h0d: begin { P0, kdata } = 9'h009; end // tab

        9'h15: begin { P0, kdata } = 9'h0c0; end // q -> ta
        9'h1d: begin { P0, kdata } = 9'h0c3; end // w -> te
        9'h24: begin { P0, kdata } = 9'h0b2; end // e -> i
        9'h2d: begin { P0, kdata } = 9'h0bd; end // r -> su
        9'h2c: begin { P0, kdata } = 9'h0b6; end // t -> ka
        9'h35: begin { P0, kdata } = 9'h0dd; end // y -> n
        9'h3c: begin { P0, kdata } = 9'h0c5; end // u -> na
        9'h43: begin { P0, kdata } = 9'h0c6; end // i -> ni
        9'h44: begin { P0, kdata } = 9'h0d7; end // o -> ra
        9'h4d: begin { P0, kdata } = 9'h0be; end // p -> se
        9'h54: begin { P0, kdata } = 9'h0de; end // @ -> voiced mark
        9'h5b: begin { P0, kdata } = 9'h0df; end // [ -> semi-voiced mark
        9'h5a: begin { P0, kdata } = 9'h00d; end // enter

        9'h1c: begin { P0, kdata } = 9'h0c1; end // a -> chi
        9'h1b: begin { P0, kdata } = 9'h0c4; end // s -> to
        9'h23: begin { P0, kdata } = 9'h0bc; end // d -> shi
        9'h2b: begin { P0, kdata } = 9'h0ca; end // f -> ha
        9'h34: begin { P0, kdata } = 9'h0b7; end // g -> ki
        9'h33: begin { P0, kdata } = 9'h0b8; end // h -> ku
        9'h3b: begin { P0, kdata } = 9'h0cf; end // j -> ma
        9'h42: begin { P0, kdata } = 9'h0c9; end // k -> no
        9'h4b: begin { P0, kdata } = 9'h0d8; end // l -> ri
        9'h4c: begin { P0, kdata } = 9'h0da; end // ; -> re
        9'h52: begin { P0, kdata } = 9'h0b9; end // : -> ke
        9'h0e: begin { P0, kdata } = 9'h0d1; end // ] -> mu

        9'h1a: begin { P0, kdata } = 9'h0c2; end // z -> tsu
        9'h22: begin { P0, kdata } = 9'h0bb; end // x -> sa
        9'h21: begin { P0, kdata } = 9'h0bf; end // c -> so
        9'h2a: begin { P0, kdata } = 9'h0cb; end // v -> hi
        9'h32: begin { P0, kdata } = 9'h0ba; end // b -> ko
        9'h31: begin { P0, kdata } = 9'h0d0; end // n -> mi
        9'h3a: begin { P0, kdata } = 9'h0d3; end // m -> mo
        9'h41: begin { P0, kdata } = 9'h0c8; end // , -> ne
        9'h49: begin { P0, kdata } = 9'h0d9; end // . -> ru
        9'h4a: begin { P0, kdata } = 9'h0d2; end // / -> me
        9'h14a: begin { P0, kdata } = 9'h02f; end // keypad / (phy $37) stays '/'

        9'h29: begin { P0, kdata } = 9'h020; end // spacebar
        9'h170: begin { P0, kdata } = 9'h012; end // insert
        9'h17d: begin { P0, kdata } = 9'h005; end // page up
        9'h17a: begin { P0, kdata } = 9'h00c; end // page down
        9'h171: begin { P0, kdata } = 9'h07f; end // delete
        9'h16c: begin { P0, kdata } = 9'h00b; end // home
        9'h175: begin { P0, kdata } = 9'h01e; end // up
        9'h172: begin { P0, kdata } = 9'h01f; end // down
        9'h16b: begin { P0, kdata } = 9'h01d; end // left
        9'h174: begin { P0, kdata } = 9'h01c; end // right

        9'h05: begin { P0, kdata } = 9'h101; end // f1
        9'h06: begin { P0, kdata } = 9'h102; end // f2
        9'h04: begin { P0, kdata } = 9'h103; end // f3
        9'h0c: begin { P0, kdata } = 9'h104; end // f4
        9'h03: begin { P0, kdata } = 9'h105; end // f5
        9'h0b: begin { P0, kdata } = 9'h106; end // f6
        9'h83: begin { P0, kdata } = 9'h107; end // f7
        9'h0a: begin { P0, kdata } = 9'h108; end // f8
        9'h01: begin { P0, kdata } = 9'h109; end // f9
        9'h09: begin { P0, kdata } = 9'h10a; end // f10
      endcase
    end

    // SHIFT. JIS layout, matching the unshifted table below: the codes here are
    // what the FM-7 keyboard MCU sends, i.e. plain ASCII for these keys.
    else if (shift_h && press_btn) begin
      case (code)
        9'h1c: begin { P0, kdata } = 9'h41; end // A
        9'h32: begin { P0, kdata } = 9'h42; end // B
        9'h21: begin { P0, kdata } = 9'h43; end // C
        9'h23: begin { P0, kdata } = 9'h44; end // D
        9'h24: begin { P0, kdata } = 9'h45; end // E
        9'h2b: begin { P0, kdata } = 9'h46; end // F
        9'h34: begin { P0, kdata } = 9'h47; end // G
        9'h33: begin { P0, kdata } = 9'h48; end // H
        9'h43: begin { P0, kdata } = 9'h49; end // I
        9'h3b: begin { P0, kdata } = 9'h4a; end // J
        9'h42: begin { P0, kdata } = 9'h4b; end // K
        9'h4b: begin { P0, kdata } = 9'h4c; end // L
        9'h3a: begin { P0, kdata } = 9'h4d; end // M
        9'h31: begin { P0, kdata } = 9'h4e; end // N
        9'h44: begin { P0, kdata } = 9'h4f; end // O
        9'h4d: begin { P0, kdata } = 9'h50; end // P
        9'h15: begin { P0, kdata } = 9'h51; end // Q
        9'h2d: begin { P0, kdata } = 9'h52; end // R
        9'h1b: begin { P0, kdata } = 9'h53; end // S
        9'h2c: begin { P0, kdata } = 9'h54; end // T
        9'h3c: begin { P0, kdata } = 9'h55; end // U
        9'h2a: begin { P0, kdata } = 9'h56; end // V
        9'h1d: begin { P0, kdata } = 9'h57; end // W
        9'h22: begin { P0, kdata } = 9'h58; end // X
        9'h35: begin { P0, kdata } = 9'h59; end // Y
        9'h1a: begin { P0, kdata } = 9'h5a; end // Z

        // JIS number row: 1..9 give ! " # $ % & ' ( ) ; shift-0 is unassigned.
        9'h16: begin { P0, kdata } = 9'h21; end // !
        9'h1e: begin { P0, kdata } = 9'h22; end // "
        9'h26: begin { P0, kdata } = 9'h23; end // #
        9'h25: begin { P0, kdata } = 9'h24; end // $
        9'h2e: begin { P0, kdata } = 9'h25; end // %
        9'h36: begin { P0, kdata } = 9'h26; end // &
        9'h3d: begin { P0, kdata } = 9'h27; end // '
        9'h3e: begin { P0, kdata } = 9'h28; end // (
        9'h46: begin { P0, kdata } = 9'h29; end // )

        9'h4e: begin { P0, kdata } = 9'h3d; end // - -> =
        9'h55: begin { P0, kdata } = 9'h7e; end // ^ -> ~
        9'h5d: begin { P0, kdata } = 9'h7c; end // \ -> |
        9'h54: begin { P0, kdata } = 9'h60; end // @ -> `
        9'h5b: begin { P0, kdata } = 9'h7b; end // [ -> {
        9'h4c: begin { P0, kdata } = 9'h2b; end // ; -> +
        9'h52: begin { P0, kdata } = 9'h2a; end // : -> *
        9'h41: begin { P0, kdata } = 9'h3c; end // , -> <
        9'h49: begin { P0, kdata } = 9'h3e; end // . -> >
        9'h4a: begin { P0, kdata } = 9'h3f; end // / -> ?

        9'h29: begin { P0, kdata } = 9'h20; end // spacebar
        9'h5a: begin { P0, kdata } = 9'h0d; end // enter
      endcase
    end
    // normal
    else if (press_btn) begin
		  case (code)
	      9'h76: begin { P0, kdata } = 9'h1b; end // esc ??
	      9'h05: begin { P0, kdata } = 9'h101; end // f1
	      9'h06: begin { P0, kdata } = 9'h102; end // f2
	      9'h04: begin { P0, kdata } = 9'h103; end // f3
	      9'h0c: begin { P0, kdata } = 9'h104; end // f4
	      9'h03: begin { P0, kdata } = 9'h105; end // f5
	      9'h0b: begin { P0, kdata } = 9'h106; end // f6
	      9'h83: begin { P0, kdata } = 9'h107; end // f7
	      9'h0a: begin { P0, kdata } = 9'h108; end // f8
	      9'h01: begin { P0, kdata } = 9'h109; end // f9
	      9'h09: begin { P0, kdata } = 9'h10a; end // f10

	      9'h16: begin { P0, kdata } = 9'h31; end // 1
	      9'h1e: begin { P0, kdata } = 9'h32; end // 2
	      9'h26: begin { P0, kdata } = 9'h33; end // 3
	      9'h25: begin { P0, kdata } = 9'h34; end // 4
	      9'h2e: begin { P0, kdata } = 9'h35; end // 5
	      9'h36: begin { P0, kdata } = 9'h36; end // 6
	      9'h3d: begin { P0, kdata } = 9'h37; end // 7
	      9'h3e: begin { P0, kdata } = 9'h38; end // 8
	      9'h46: begin { P0, kdata } = 9'h39; end // 9
	      9'h45: begin { P0, kdata } = 9'h30; end // 0
				9'h4e: begin { P0, kdata } = 9'h2d; end // -
	      9'h55: begin { P0, kdata } = 9'h5e; end // =
	      9'h5d: begin { P0, kdata } = 9'h5c; end // \


	      9'h15: begin { P0, kdata } = 9'h71; end // q
	      9'h1d: begin { P0, kdata } = 9'h77; end // w
	      9'h24: begin { P0, kdata } = 9'h65; end // e
	      9'h2d: begin { P0, kdata } = 9'h72; end // r
	      9'h2c: begin { P0, kdata } = 9'h74; end // t
	      9'h35: begin { P0, kdata } = 9'h79; end // y
	      9'h3c: begin { P0, kdata } = 9'h75; end // u
	      9'h43: begin { P0, kdata } = 9'h69; end // i
	      9'h44: begin { P0, kdata } = 9'h6f; end // o
	      9'h4d: begin { P0, kdata } = 9'h70; end // p
	      9'h54: begin { P0, kdata } = 9'h40; end // [
	      9'h5b: begin { P0, kdata } = 9'h5b; end // ]

		    9'h1c: begin { P0, kdata } = 9'h61; end // a
	      9'h1b: begin { P0, kdata } = 9'h73; end // s
	      9'h23: begin { P0, kdata } = 9'h64; end // d
	      9'h2b: begin { P0, kdata } = 9'h66; end // f
	      9'h34: begin { P0, kdata } = 9'h67; end // g
	      9'h33: begin { P0, kdata } = 9'h68; end // h
	      9'h3b: begin { P0, kdata } = 9'h6a; end // j
	      9'h42: begin { P0, kdata } = 9'h6b; end // k
	      9'h4b: begin { P0, kdata } = 9'h6c; end // l
	      9'h4c: begin { P0, kdata } = 9'h3b; end // ;
	      9'h52: begin { P0, kdata } = 9'h3a; end // '
	      9'h0e: begin { P0, kdata } = 9'h5b; end // `

	      9'h1a: begin { P0, kdata } = 9'h7a; end // z
	      9'h22: begin { P0, kdata } = 9'h78; end // x
	      9'h21: begin { P0, kdata } = 9'h63; end // c
	      9'h2a: begin { P0, kdata } = 9'h76; end // v
		    9'h32: begin { P0, kdata } = 9'h62; end // b
	      9'h31: begin { P0, kdata } = 9'h6e; end // n
	      9'h3a: begin { P0, kdata } = 9'h6d; end // m
	      9'h41: begin { P0, kdata } = 9'h2c; end // ,
	      9'h49: begin { P0, kdata } = 9'h2e; end // .
	      9'h14a: begin { P0, kdata } = 9'h2f; end // .
	      9'h04a: begin { P0, kdata } = 9'h2f; end // / (was '"'; " is shift-2)

	      9'h29: begin { P0, kdata } = 9'h20; end // spacebar
	      9'h5a: begin { P0, kdata } = 9'h0d; end // enter
	      9'h0d: begin { P0, kdata } = 9'h09; end // tab
	      9'h66: begin { P0, kdata } = 9'h08; end // backspace
	      9'h175: begin { P0, kdata } = 9'h1e; end // up
	      9'h174: begin { P0, kdata } = 9'h1c; end // right
	      9'h16b: begin { P0, kdata } = 9'h1d; end // left
	      9'h172: begin { P0, kdata } = 9'h1f; end // down
	      9'h58: begin { P0, kdata } = 9'h00; end // caps lock ?
	      9'h16c: begin { P0, kdata } = 9'h0b; end // home
	      9'h17d: begin { P0, kdata } = 9'h00; end // page up ?
	      9'h17a: begin { P0, kdata } = 9'h00; end // page down ?
	      9'h170: begin { P0, kdata } = 9'h12; end // insert
	      9'h171: begin { P0, kdata } = 9'h7f; end // delete
	      // 9'h114: BREAKn = ~press_btn; // ctrl right => break
		  endcase
	  end

		else begin
			{ P0, kdata } <= 9'h0;
		end

	end
end

always @(posedge CLKSYS) begin
	reg old_state;

	old_state <= ps2_key[10];
	input_strobe <= 1'b0;


	if(old_state != ps2_key[10]) begin
		press_btn <= ps2_key[9];
		code <= ps2_key[8:0];
	  input_strobe <= 1'b1;
	end
end

// $fd02 resets with the keyboard routed to the SUB CPU, not the main one.
//
// m77[0] picks the route: set = main (KEYINn), clear = sub (KSTROBEn). This
// reset value was 3'b111, i.e. keyboard-to-main, and both references say the
// opposite:
//
//   MAME  m_irq_mask = 0x00 at reset (fm7.cpp:1792), and the delivery path is
//         `if(m_irq_mask & IRQ_FLAG_KEY) main_irq_set_flag(...); else
//          m_sub->set_input_line(M6809_FIRQ_LINE, ASSERT_LINE);` (:1120-1126).
//         Mask 0 therefore takes the else branch -> the SUB.
//   CSP   reset() sets `irqmask_keyboard = true` (fm7_mainio.cpp:268), and
//         set_fd02 clears it only when bit 0 is set (:500-503). The same flag
//         drives the sub as SIG_FM7_SUB_KEY_MASK with `firq_mask = !flag`, so
//         the reset state leaves the sub's FIRQ ENABLED.
//
// It matters because a title that never writes $fd02 inherits this, and several
// do exactly that. The sub monitor ROM's input wait at $fd76 is
//
//     $fd76  ORCC  #$40        mask FIRQ
//     $fd78  LDB   <$04        $d004
//     $fd7a  BNE   $fd86
//     $fd7c  BCC   $fd92
//     $fd7e  LDB   <$00        $d000
//     $fd80  BNE   $fd92
//     $fd82  ANDCC #$bf        unmask FIRQ
//     $fd84  BRA   $fd76
//
// which spins until its FIRQ handler puts a byte in $d000/$d004. Route the
// keyboard to the main CPU instead and that byte never arrives, so the sub
// waits forever and the main waits on it -- the BUSY=1/SHALTACn=1 stall in
// P4-16. Only bit 0 is changed here; LPMASKn and TMMASK keep their old reset
// value, since nothing has been measured about those.
// $fd02, converted off its decode strobe -- see DERIVED_CLOCKS.md.
//
// THIS ONE DOES NOT USE THE FILTERED-EDGE RECIPE, because both edges were tried
// on hardware and both regressed OS-9 (0 boots in 8 tries each). Sampling on an
// edge at all is the thing those two attempts had in common, and each edge has
// its own hazard:
//
//   leading edge  -- the 74138 decode is still settling, which is exactly the
//                    glitch window, and the 6809 may not yet be driving write
//                    data. The original latched on the TRAILING edge for that
//                    second reason: a 74LS374 captures where the data is known
//                    good.
//   trailing edge -- a filtered detector only recognises the edge two CLKSYS
//                    cycles after the strobe has already risen, by which point
//                    the bus may no longer be driven and any tracked copy is at
//                    risk of having been re-sampled from a released bus.
//
// So latch in the MIDDLE of the access instead of at either end: require the
// strobe to have been stably low for three CLKSYS cycles, commit exactly once,
// and re-arm only after it has been stably high for three. That is past the
// leading-edge glitch window, comfortably before the trailing edge (WFD02n is
// qualified by WTQEn = Q&E, so it is roughly 19 CLKSYS cycles wide against
// E = 1.2288 MHz), and it cannot double-write within one access.
//
// Sampling only once WTQEn has asserted also means Q and E are both already
// high, which is the point at which the 6809 has committed its write data --
// so the data-validity reason the original chose the trailing edge is satisfied
// without having to sit on that edge.
//
// NOT VERIFIABLE FROM SIMULATION. vsim reproduces the recipe-verbatim version
// byte-for-byte, OS-9 shell included, so sim cannot tell any of these three
// designs apart. This is reasoning about the hardware failure, not a proven
// fix, and it needs a .rbf to judge.
wire s0 = ~RESETBn;
reg [2:0] wfd02_sr;
reg       wfd02_armed;
always @(posedge CLKSYS) begin
  wfd02_sr <= { wfd02_sr[1:0], WFD02n };
  if (~RESETBn) begin
    m77         <= 3'b110;
    wfd02_armed <= 1'b1;
  end
  else if (&wfd02_sr) begin
    wfd02_armed <= 1'b1;                       // stably high: arm for next access
  end
  else if (~|wfd02_sr & wfd02_armed) begin     // stably low, once per access
    $display("FD02 Write: %02X", MDATA_in);
    m77         <= MDATA_in[2:0];
    wfd02_armed <= 1'b0;
  end
end

wire clr = ~(RESETBn & RFD01n & KACKNGn);

// "A code is waiting", driven by a real keystroke rather than by
// `posedge press_btn`.
//
// The edge-triggered version latched on ANY key going down, including the
// modifiers -- so pressing SHIFT presented whatever stale code was still in
// kdata, and the letter that followed produced no new edge at all (press_btn
// was already high), so it was never delivered. Shifted characters therefore
// did nothing. The real MB88401 keyboard MCU sends nothing for a modifier on
// its own.
//
// Setting also wins over clearing, so a keystroke that lands in the same cycle
// the CPU acknowledges the previous one is not silently dropped.
wire is_modifier = (code == 9'h012) || (code == 9'h059) ||  // shift L/R
                   (code == 9'h014) || (code == 9'h114) ||  // ctrl L/R
                   (code == 9'h011) || (code == 9'h111);    // alt L/R

reg key_stb;
always @(posedge CLKSYS)
  key_stb <= input_strobe & press_btn & ~is_modifier;

always @(posedge CLKSYS) begin
  if (key_stb)  m132 <= 1'b1;
  else if (clr) m132 <= 1'b0;
end

assign KSTROBEn = ~(m132 & ~m77[0]);
assign KEYINn = ~(m132 & m77[0]);
assign LPMASKn = m77[1];
assign TMMASK = m77[2];

endmodule
