
// The FM-7's PSG and the FM77AV's YM2203, on one jt03 (jotego/jt12).
//
// The FM-7 has a discrete AY-3-8913 behind $fd0d/$fd0e. The FM77AV replaces it
// with a single YM2203 whose SSG half answers on those same two ports -- masked
// to the AY-compatible two-bit command set -- while $fd15/$fd16 drive the whole
// chip with the four-bit set (CSP sound.cpp:46-50 `opn_psg_77av`, routing
// :107-133; 77AVEMU fm77avsound.cpp:398 "FM77AV and later writes to the
// PSG-part of YM2203C"). So this is one chip with two register windows, not two
// devices.
//
// $fd15/$fd16 were not decoded at all before this. Thexder alone writes $fd15
// 1572 times, and the FM77AV initiator ROM programs the chip at $6009 before it
// does anything else. The cost of the omission was not just silence: Ys
// (FM77AV) polls the status register through command 4 and spins until bit 7
// clears, so an undecoded port returning $ff hung the game outright.
//
// LICENCE: jt12/jt49 are GPLv3-or-later. This repository's LICENSE is GPLv2,
// but FM-7_MiSTer.sv and the MiSTer sys/ framework both read "version 2 ... or
// (at your option) any later version", so the combination is permitted and the
// combined work ships as GPLv3. See rtl/jt12/LICENSE-jt12.
module SOUND(
  input CLKSYS,
  input CLK1_2,
  input RESETBn,
  input machine_av,
  input [7:0] MDATABUS_in,
  output [7:0] MDATABUS_out,

  // $fd0d command / $fd0e data -- the AY-compatible window.
  input RFD0En,
  input WFD0En,
  input WFD0Dn,
  // $fd15 command / $fd16 data -- the full YM2203 window, FM77AV only.
  input RFD16n,
  input WFD16n,
  input WFD15n,

  // Joysticks, MiSTer bit order: [0]=right [1]=left [2]=down [3]=up
  // [4]=button A [5]=button B, active high.
  input [5:0] joystick_0,
  input [5:0] joystick_1,

  output [13:0] mix_audio_o,   // SSG mix, unsigned, 0 = silence
  output [11:0] fm_audio_o,    // FM mix, unsigned, 2048 = silence
  output        FMIRQn
);

wire reset = ~RESETBn;

// jt03's `cen` is the chip master clock; jt12_div then applies the YM2203's own
// prescaler (/4 for the SSG at reset). Feeding it the same 1.2 MHz enable the
// AY-3-8913 had makes the SSG tone divider come out identical to the retired
// ym2149_audio path -- `make sound-test` asserts the divider is 16, and it
// still is. The FM-7's pitch is therefore unchanged by this replacement, which
// is deliberate: the shipped pitch has never had a listening test (TODO.md) and
// this commit is not the place to move it.
//
// The FM77AV is a different story. Its initiator ROM selects registers $2D and
// $2E, which is how a YM2203 is told to run the prescaler at FM 1/3 and SSG
// 1/2, so on the AV the SSG runs an octave above the FM-7's. jt03 models that
// faithfully (jt12_div's table, from the YM2608 manual) and it is left alone,
// but whether the AV's real master clock compensates is UNVERIFIED -- MAME and
// CSP both say 4.9152/4 = 1.2288 MHz, which cannot be reconciled with both
// machines sounding alike. This needs an ear, not another derivation.
// MEASURED, not derived. `make sound-test` programs TP = $0140 and prints the
// tone in Hz for a 48 MHz CLKSYS. With a 1.2 MHz cen it came out at 117.32 Hz
// where an AY-3-8910 at the FM-7's documented 1.2288 MHz PSG clock plays
// 1228800/(16*320) = 240.00 Hz -- exactly half, on every tone period tried.
// Both references give that clock (CSP fm7.cpp:831, MAME fm7.cpp:1893), and the
// retired ym2149_audio was flat by the same factor, so this is an old bug the
// jt03 swap inherited rather than introduced.
//
// The factor of two is jt12's SSG chain: with its jt49 wrapped at CLKDIV=2 and
// sel=1, and the prescaler at its reset /4, the tone counter ends up running at
// cen/2 rather than cen/4. So `cen` has to be twice the nominal chip clock for
// the SSG to land on the AY's rate.
//
// Which is why this is machine-dependent, and it is not arbitrary. The FM77AV
// initiator selects registers $2D and $2E, which halves the YM2203's SSG
// prescaler for the rest of the run -- so on the AV the same chain already
// doubles the rate and the nominal 1.2288 MHz is the right number. The FM-7
// never writes those registers, its prescaler stays at reset, and it needs the
// doubled clock. Both machines end up with the SSG at 1.2288 MHz, which is the
// only arrangement in which FM-7 software plays at the same pitch on both.
//
// Residual, unchanged: 48/40 = 1.2 MHz and 48/20 = 2.4 MHz against a true
// 1.2288/2.4576, so both sit 2.3% flat -- about 0.4 semitone. Fixing that needs
// a fractional divider and is a separate job.
localparam CORE_CLK_2_4 = 19;   // 48/2.4 - 1
wire EN_CLK_1_2, EN_CLK_2_4;
clk_en #(CORE_CLK_1_2) u_ck_en   (.ref_clk(CLKSYS), .cen(EN_CLK_1_2));
clk_en #(CORE_CLK_2_4) u_ck_en_2 (.ref_clk(CLKSYS), .cen(EN_CLK_2_4));
wire YM_CEN = machine_av ? EN_CLK_1_2 : EN_CLK_2_4;

//----------------------------------------------------------------------------
// The two register windows
//
// Both windows are a command register and a data register. The data register
// LATCHES A BYTE and the following command write is what acts on it -- that
// order is not a guess, it is Thexder's own bus traffic:
//
//     $fd0e <- 08     put 8 on the data latch
//     $fd0d <- 03     command 3: latch it as the register address
//     $fd0d <- 00
//     $fd0e <- 1f     data
//     $fd0d <- 02     command 2: write $1f to register 8
//
// and it is CSP's model (sound.cpp:308-348, where set_opn_cmd() consumes the
// byte set_psg() stored on the previous data write). The whole audio path was
// silent for the life of the project because it was implemented the other way
// round. IO_MAP.md used to document the opposite order; that sequence had been
// checked against this core while this code was backwards, so it proved only
// self-consistency.
//
// Commands (CSP sound.cpp:283-291, 324-346):
//   0 inactive   1 read data   2 write data   3 latch address
//   4 read status   9 read joystick port
// $fd0d is masked to two bits, so it reaches only 0-3; $fd15 takes all four.
//
// 77AVEMU defers the effect of commands 2 and 3 until the following command 0
// (fm77avsound.cpp:100-172). CSP acts on the command write itself. Every
// sequence in hand writes 2 or 3 and then 0, so the two models agree on it;
// this follows CSP, which is also what the $fd0d path already did.
reg wfd0d_d, wfd0e_d, wfd15_d, wfd16_d;
always @(posedge CLKSYS) begin
  wfd0d_d <= WFD0Dn;
  wfd0e_d <= WFD0En;
  wfd15_d <= WFD15n;
  wfd16_d <= WFD16n;
end

// Leading edges. The trailing edge is where the CPU has already released the
// bus in zero-delay RTL -- the mistake $fd37 made (see FLAGS.v).
wire wfd0d_stb = ~WFD0Dn & wfd0d_d;
wire wfd0e_stb = ~WFD0En & wfd0e_d;
wire wfd15_stb = ~WFD15n & wfd15_d;
wire wfd16_stb = ~WFD16n & wfd16_d;

wire       cmd_stb = wfd0d_stb | wfd15_stb;
wire [3:0] cmd_new = wfd15_stb ? MDATABUS_in[3:0] : { 2'b00, MDATABUS_in[1:0] };
wire       data_stb = wfd0e_stb | wfd16_stb;

reg [7:0] ym_data;    // the latched data byte
reg [3:0] ym_cmd;     // the latched command
reg [7:0] ym_addr;    // the register address latched by command 3

always @(posedge CLKSYS) begin
  if (reset)         ym_data <= 8'd0;
  else if (data_stb) ym_data <= MDATABUS_in;
end

// jt03's bus: `addr` picks the register-select port (0) or the data port (1),
// and a write happens while cs_n and wr_n are both low. One CLKSYS cycle is
// enough and a level would not do -- holding write asserted for a whole 40-cycle
// bus strobe would re-run jt12_mmr's write decode on every one of them.
reg       jt_write;
reg       jt_wr_addr;
reg [7:0] jt_din;
reg       read_status;   // command 4 selected the status port for reads

always @(posedge CLKSYS) begin
  jt_write <= 1'b0;
  if (reset) begin
    ym_cmd      <= 4'd0;
    ym_addr     <= 8'd0;
    jt_wr_addr  <= 1'b0;
    jt_din      <= 8'd0;
    read_status <= 1'b0;
  end
  else if (cmd_stb) begin
    ym_cmd <= cmd_new;
    case (cmd_new)
      4'd1: read_status <= 1'b0;                     // read data
      4'd2: begin                                    // write data
        jt_wr_addr  <= 1'b1;
        jt_din      <= ym_data;
        jt_write    <= 1'b1;
        read_status <= 1'b0;
      end
      4'd3: begin                                    // latch register address
        jt_wr_addr  <= 1'b0;
        jt_din      <= ym_data;
        jt_write    <= 1'b1;
        ym_addr     <= ym_data;
        read_status <= 1'b0;
      end
      4'd4: read_status <= 1'b1;                     // read status
      default: ;
    endcase
  end
end

// Outside the write pulse `addr` only selects what `dout` carries, so it holds
// the data port unless command 4 asked for status. That keeps a read of the
// selected register valid at any time after the address latch, which is how the
// existing joystick sequence reads port A.
wire jt_addr = jt_write ? jt_wr_addr : ~read_status;

//----------------------------------------------------------------------------
// Joysticks
//
// They hang off the chip's own I/O ports; CSP wires exactly this in fm7.cpp:626
// (`opn[0]->set_context_port_b(joystick, ...)`). The protocol, from
// refs/common-src-project/src/vm/fm7/joystick.cpp:
//
//   * writing register 15 (port B) selects the stick -- high nibble $2 for
//     stick 0, $5 for stick 1, anything else none
//   * reading register 14 (port A) returns it, ACTIVE LOW, as
//     { 1, 1, ~buttonB, ~buttonA, ~right, ~left, ~down, ~up }
//
// This used to be done by snooping the $fd0d/$fd0e bus, because ym2149_audio
// has no I/O ports at all. jt03 carries the real ones, so port B's latch drives
// the selection and port A's input carries the answer -- jt49 returns IOA_in
// for a read of register 14 whatever the direction bits say, so this does not
// depend on software programming register 7.
wire [7:0] iob_out;
wire joy0_sel = (iob_out[7:4] == 4'h2);
wire joy1_sel = (iob_out[7:4] == 4'h5);
wire [5:0] joy = joy0_sel ? joystick_0 :
                 joy1_sel ? joystick_1 : 6'd0;

// $ff when no stick is selected, which is what CSP returns.
wire [7:0] joy_port_a = (joy0_sel | joy1_sel)
                      ? { 2'b11, ~joy[5], ~joy[4], ~joy[0], ~joy[1], ~joy[2], ~joy[3] }
                      : 8'hff;

//----------------------------------------------------------------------------
// Reads
//
// Neither port has a side effect, so both are plain combinational muxes and the
// RDQEn two-strobe hazard (docs/REFERENCE.md section 2) cannot bite here.
//
// $fd16 command 9 is the AV's direct joystick port. 77AVEMU ORs in $80 rather
// than $c0 and says why: "It used to be |=0xC0, but Gambler Jikochushinha by
// Game Arts expects it to return non-FF" (fm77avsound.cpp:210-216).
wire [7:0] jt_dout;
wire [7:0] fd16_dout = (ym_cmd == 4'd9) ? (joy_port_a | 8'h80) : jt_dout;

assign MDATABUS_out = ~RFD16n ? fd16_dout : jt_dout;

`ifdef DEBUG_JOY
// `make DEBUG_JOY=1`. One line per register-15 write (which stick the software
// selected) and per register-14 read (what it got back).
reg rfd0e_d;
always @(posedge CLKSYS) begin
  rfd0e_d <= RFD0En;
  if (cmd_stb && cmd_new == 4'd3)
    $display("PSGADDR  <- %0d", ym_data);
  if (cmd_stb && cmd_new == 4'd2)
    $display("PSGWR    reg%0d <- %02x", ym_addr, ym_data);
  if (cmd_stb && cmd_new == 4'd2 && ym_addr == 8'd15)
    $display("JOYSEL port_b=%02x -> %s", ym_data,
             (ym_data[7:4] == 4'h2) ? "stick 0" :
             (ym_data[7:4] == 4'h5) ? "stick 1" : "none");
  if (~RFD0En && rfd0e_d && ym_addr == 8'd14)
    $display("JOYRD  port_b=%02x -> %02x", iob_out, joy_port_a);
end
`endif

//----------------------------------------------------------------------------
// The chip
wire [9:0]  psg_snd;
wire [7:0]  psg_A, psg_B, psg_C;   // per-channel taps, for the sim's audio census
wire signed [15:0] fm_snd;

jt03 u_jt03(
  .rst      ( reset        ),
  .clk      ( CLKSYS       ),
  .cen      ( YM_CEN       ),
  .din      ( jt_din       ),
  .addr     ( jt_addr      ),
  .cs_n     ( ~jt_write    ),
  .wr_n     ( ~jt_write    ),
  .dout     ( jt_dout      ),
  .irq_n    ( FMIRQn       ),
  .IOA_in   ( joy_port_a   ),
  .IOB_in   ( 8'hff        ),
  .IOA_out  (              ),
  .IOB_out  ( iob_out      ),
  .IOA_oe   (              ),
  .IOB_oe   (              ),
  .psg_A    ( psg_A        ),
  .psg_B    ( psg_B        ),
  .psg_C    ( psg_C        ),
  .fm_snd   ( fm_snd       ),
  .psg_snd  ( psg_snd      ),
  .snd      (              ),
  .snd_sample (            ),
  .debug_view (            )
);

// The retired ym2149_audio mix was three 12-bit DACs summed, peaking at 12288
// on a 14-bit bus. jt49 accumulates three linearised 8-bit channels into 10
// bits, so full scale is 3 x 255 = 765 and x16 puts it back at 12240 -- the
// same level, so the top-level headroom sum in FM-7_MiSTer.sv is unchanged.
assign mix_audio_o = { psg_snd, 4'b0000 };

// The FM half is signed; the core's audio bus is unsigned with AUDIO_S = 0, so
// it leaves here as 12 bits around a 2048 midpoint. That is the largest slice
// the top-level sum has room for without overflowing 16 bits.
assign fm_audio_o = fm_snd[15:4] + 12'd2048;

endmodule
