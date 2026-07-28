
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

assign BREAKn = 1;

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
//   alt left = GRAPH, alt right = KANA, ctrl left = CTRL
reg shift_h, ctrl_h, graph_h, kana_h;
always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    shift_h <= 1'b0; ctrl_h <= 1'b0; graph_h <= 1'b0; kana_h <= 1'b0;
  end
  else if (input_strobe) begin
    case (code)
      9'h012, 9'h059: shift_h <= press_btn;  // shift left / right
      9'h014:         ctrl_h  <= press_btn;  // ctrl left
      9'h011:         graph_h <= press_btn;  // alt left
      9'h111:         kana_h  <= press_btn;  // alt right
    endcase
  end
end

always @* begin

  if (input_strobe) begin

    // SHIFT. JIS layout, matching the unshifted table below: the codes here are
    // what the FM-7 keyboard MCU sends, i.e. plain ASCII for these keys.
    // CTRL / GRAPH / KANA are still unimplemented -- see TODO.md P2-1.
    if (shift_h && press_btn) begin
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

wire s0 = ~RESETBn;
always @(posedge WFD02n, posedge s0) begin
  if (s0) m77 <= 3'b111;
  else begin
		$display("FD02 Write: %02X", MDATA_in);
		m77 <= MDATA_in[2:0];
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
