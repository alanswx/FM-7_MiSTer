// FM77AV keyboard encoder register pair.
//
// The base FM-7 exposes a matrix keyboard through D400/D401. The AV adds an
// independent command/data encoder at D431/D432, aliased every 64 bytes in
// the sub-I/O page. Physical key injection remains on the existing keyboard
// path until the scan-code translation is wired in.
//
// The command set is FM77AV40 Hardware Reference pp.230, transcribed in
// 77AVEMU `fm77av/keyboard/fm77avkeyboard.h:42-56` and implemented in CSP
// `fm7/keyboard.cpp:1000-1080`. The parameter COUNTS matter as much as the
// commands: the encoder has no framing, so a command whose parameters this
// module does not consume leaves the next parameter byte to be read as a
// command, and the whole stream slips.
//
//   $00 set coding   1 param        $80 real-time clock  1 param ($00 read ->
//   $01 get coding   0 -> 1 byte        7 bytes; $01 write + 7 more params)
//   $02 set LED      1 param        $81 digitize mode    1 param
//   $03 get LED      0 -> 1 byte    $82 set screen mode  1 param
//   $04 auto repeat  1 param        $83 get screen mode  0 -> 1 byte
//   $05 repeat time  2 params       $84 TV brightness    1 param
//
// $D432: b7 = 0 when a reply byte is waiting, b0 = 0 while the 100 us command
// acknowledge is still running, and EVERY OTHER BIT READS 1. Both references
// build it the same way, from $FF down -- 77AVEMU
// `fm77avkeyboard.cpp:723-736` (`byteData=0xFF; ... &=0xFE; ... &=0x7F`) and
// CSP `keyboard.cpp:690-702` (`data=0xff; if(rxrdy) data&=0x7f; if(!ack)
// data&=0xfe`).
module AVKEYBOARD(
  input        CLKSYS,
  input        RESETBn,
  input        machine_av,
  input [15:0] SADDRBUS,
  input  [7:0] SDATA_in,
  input        SWTQEn,
  input        SRWB,
  output [7:0] DOUT,
  output       SEL,
  // Second, read-only view for the main CPU's MMR window onto the sub I/O
  // page. Woody Poco halts the sub, maps physical $1D000 into $2000-$2FFF and
  // then drives the encoder from the main side, so these registers have to be
  // readable from an address that is not on the sub bus at all.
  input  [7:0] MMR_ADDR,
  output [7:0] MMR_DOUT
);

wire io_window = machine_av && (SADDRBUS[15:8] == 8'hd4);
wire data_sel  = io_window && (SADDRBUS[5:0] == 6'h31);
wire stat_sel  = io_window && (SADDRBUS[5:0] == 6'h32);
// Commands arrive on $D431 ONLY. $D432 is status, and a write to it is a
// no-op on both references -- 77AVEMU's `WriteD432` has an empty body
// (`fm77avkeyboard.cpp:703-705`) and CSP routes only $D431 into the command
// FIFO (`keyboard.cpp:1143-1160`). This used to accept either address, which
// was invisible while every command was stateless; with a parameter counter a
// stray $D432 write would slip the whole command stream.
wire write     = data_sel && ~SWTQEn;

// SWTQEn is a decode window, not a clock: it is low for the whole of the ~2 MHz
// Q&E write phase, which is dozens of 48 MHz CLKSYS cycles. Every earlier user
// of it in this module happened to be idempotent, so the level was harmless.
// A parameter COUNTER is not -- one write would advance it dozens of times --
// so everything below runs off the edge. FLAGS.v's $fd37 register carries the
// same warning for the same reason.
reg  write_d;
wire write_stb = write && !write_d;

reg [7:0] command;
reg [7:0] mode;
reg [7:0] leds;
reg [7:0] screen_mode;
reg [7:0] brightness;
reg       command_pending;
reg [3:0] param_n;      // parameter bytes consumed so far
reg [3:0] param_need;   // how many this command takes
reg [12:0] acknowledge_timer;

// The reply queue. Only the RTC read is longer than one byte and it is seven,
// so a 7-byte shift register is the whole of it -- the MSB byte leaves first.
reg [55:0] out_shift;
reg  [2:0] out_count;
reg [12:0] data_timer;

// 77AVEMU restarts a 100 us timer after EVERY $D431 read and holds b7 high
// until it expires (`AfterReadD431`, `fm77avkeyboard.cpp:707-715`), so the sub
// monitor's seven-byte RTC read is paced, not burst. The first byte is not
// delayed: nothing has been read yet, so the timer has already expired.
wire data_ready = (out_count != 3'd0) && (data_timer == 13'd0);

wire [7:0] status = {~data_ready, 6'b111111,
                     (acknowledge_timer == 13'd0)};

assign SEL  = data_sel || stat_sel;
assign DOUT = data_sel ? out_shift[55:48] : status;
// A main-CPU read through the MMR aperture SEES the reply byte but does not pop
// the queue -- the pop below is on the sub bus. That was true of the single-byte
// register this replaced too, and no title has been shown to read a multi-byte
// reply from the main side -- Woody Poco does drive the encoder from there, but
// it writes a command and then polls the ACK bit, never the data queue. Wire a
// second pop here if a title that reads one turns up.
assign MMR_DOUT = (MMR_ADDR[5:0] == 6'h31) ? out_shift[55:48] : status;

// One pop per bus cycle. `data_sel & SRWB` is a level that stands for the whole
// of a ~2 MHz sub-CPU cycle against a 48 MHz CLKSYS, so the queue would empty in
// a single read without this edge. The address does change between accesses --
// the sub polls $D432 between every $D431 read -- so the edge is real.
reg d431_rd_d;
wire d431_rd = data_sel && SRWB;

// The real-time clock, as the encoder reports it. Seven bytes, packed BCD:
//
//   0  year mod 100      1  month           2  day
//   3  day-of-week b7:4, 24-hour flag b3, PM b2, hour tens b1:0
//   4  hour units b7:4, minute tens b3:0
//   5  minute units b7:4, second tens b3:0
//   6  second units b7:4
//
// **The references disagree on byte 3 and this follows CSP**, the primary
// authority for this core (REFERENCE.md section 6). CSP `keyboard.cpp:888-898`
// puts the day of week in b7:4 with the 24-hour flag at b3 and PM at b2;
// 77AVEMU `fm77avkeyboard.cpp:653` puts the day of week in b7:5 with the
// 24-hour flag at b4 and no PM bit at all. CSP's packing is the one that leaves
// room for both flags. The other six bytes are identical in both.
//
// The DATE is a fixed constant -- 1988-01-01, a Friday -- because this core has
// no host clock and the screenshot gate needs the machine to be deterministic.
// The TIME runs. A stopped clock is not a neutral simplification: software that
// waits for the second to change would hang on one, exactly as the sub monitor
// hung here on a clock that answered nothing at all.
//
// Counters are held in BCD so the reply is a wiring job and there is no divider
// and no binary-to-BCD conversion in the read path.
localparam [7:0] RTC_YEAR  = 8'h88;
localparam [7:0] RTC_MONTH = 8'h01;
localparam [7:0] RTC_DAY   = 8'h01;
localparam [3:0] RTC_WDAY  = 4'd5;    // Friday, 1988-01-01

// 48 MHz CLKSYS, so one second is 48e6 ticks.
localparam [25:0] TICKS_PER_SECOND = 26'd48000000;
reg [25:0] tick_div;
reg  [7:0] rtc_sec;    // BCD 00-59
reg  [7:0] rtc_min;    // BCD 00-59
reg  [7:0] rtc_hour;   // BCD 00-23

wire [55:0] rtc_reply = { RTC_YEAR,
                          RTC_MONTH,
                          RTC_DAY,
                          {RTC_WDAY, 1'b1, 1'b0, rtc_hour[5:4]},
                          {rtc_hour[3:0], rtc_min[7:4]},
                          {rtc_min[3:0],  rtc_sec[7:4]},
                          {rtc_sec[3:0],  4'd0} };

// The RTC WRITE command extends its own parameter count from 1 to 8, and it has
// to do so where the terminate test below can see it in the same cycle -- a
// non-blocking assignment to param_need would not be visible until the next.
reg [3:0] param_need_eff;
always @* begin
  param_need_eff = param_need;
  if (write_stb && command_pending && (command == 8'h80) &&
      (param_n == 4'd0) && (SDATA_in == 8'h01))
    param_need_eff = 4'd8;
end

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    command           <= 8'd0;
    mode              <= 8'd0; // FM-7 coding at power-on
    leds              <= 8'd0;
    screen_mode       <= 8'd0; // computer only
    brightness        <= 8'd0;
    command_pending   <= 1'b0;
    param_n           <= 4'd0;
    param_need        <= 4'd0;
    acknowledge_timer <= 13'd0;
    out_shift         <= 56'd0;
    out_count         <= 3'd0;
    data_timer        <= 13'd0;
    d431_rd_d         <= 1'b0;
    write_d           <= 1'b0;
    tick_div          <= 26'd0;
    rtc_sec           <= 8'h00;
    rtc_min           <= 8'h00;
    rtc_hour          <= 8'h00;
  end
  else begin
    if (acknowledge_timer != 13'd0)
      acknowledge_timer <= acknowledge_timer - 13'd1;
    if (data_timer != 13'd0)
      data_timer <= data_timer - 13'd1;

    if (tick_div == TICKS_PER_SECOND - 26'd1) begin
      tick_div <= 26'd0;
      if (rtc_sec == 8'h59) begin
        rtc_sec <= 8'h00;
        if (rtc_min == 8'h59) begin
          rtc_min <= 8'h00;
          rtc_hour <= (rtc_hour == 8'h23) ? 8'h00 :
                      (rtc_hour[3:0] == 4'd9) ? {rtc_hour[7:4] + 4'd1, 4'd0} :
                                                {rtc_hour[7:4], rtc_hour[3:0] + 4'd1};
        end
        else rtc_min <= (rtc_min[3:0] == 4'd9) ? {rtc_min[7:4] + 4'd1, 4'd0} :
                                                 {rtc_min[7:4], rtc_min[3:0] + 4'd1};
      end
      else rtc_sec <= (rtc_sec[3:0] == 4'd9) ? {rtc_sec[7:4] + 4'd1, 4'd0} :
                                               {rtc_sec[7:4], rtc_sec[3:0] + 4'd1};
    end
    else tick_div <= tick_div + 26'd1;

    write_d <= write;
    if (write_stb) begin
      acknowledge_timer <= 13'd4800; // approximately 100 us at 48 MHz
      if (!command_pending) begin
        command <= SDATA_in;
        param_n <= 4'd0;
        case (SDATA_in)
          8'h01: begin out_shift <= {mode,        48'd0}; out_count <= 3'd1;
                       command <= 8'd0; param_need <= 4'd0; end
          8'h03: begin out_shift <= {leds,        48'd0}; out_count <= 3'd1;
                       command <= 8'd0; param_need <= 4'd0; end
          8'h83: begin out_shift <= {screen_mode, 48'd0}; out_count <= 3'd1;
                       command <= 8'd0; param_need <= 4'd0; end
          8'h05: begin command_pending <= 1'b1; param_need <= 4'd2; end
          8'h00, 8'h02, 8'h04, 8'h80,
          8'h81, 8'h82, 8'h84:
                 begin command_pending <= 1'b1; param_need <= 4'd1; end
          default: begin command <= 8'd0; param_need <= 4'd0; end
        endcase
      end
      else begin
        param_n    <= param_n + 4'd1;
        param_need <= param_need_eff;
        case (command)
          8'h00: if (SDATA_in <= 8'd2) mode <= SDATA_in;
          8'h02: if (SDATA_in <= 8'd3) leds <= SDATA_in;
          8'h04: ; // repeat enable/disable, accepted
          8'h05: ; // repeat start time and interval, accepted as a stub
          8'h80:
            // $00 reads the clock, $01 sets it and takes seven more bytes,
            // anything else is illegal and ends the command
            // (CSP `keyboard.cpp:1052-1070`). The set payload is swallowed:
            // 77AVEMU takes the same position -- "Supposed to set RTC, but
            // I'll take it from host clock" (`fm77avkeyboard.cpp:676`).
            if ((param_n == 4'd0) && (SDATA_in == 8'h00)) begin
              out_shift <= rtc_reply;
              out_count <= 3'd7;
            end
          8'h81: ; // digitize mode, no video capture in this core
          8'h82: screen_mode <= SDATA_in;
          8'h84: brightness  <= SDATA_in;
          default: ;
        endcase
        if (param_n + 4'd1 >= param_need_eff) begin
          command         <= 8'd0;
          command_pending <= 1'b0;
          param_need      <= 4'd0;
        end
      end
    end

    d431_rd_d <= d431_rd;
    if (d431_rd && !d431_rd_d && data_ready) begin
      out_shift  <= {out_shift[47:0], 8'd0};
      out_count  <= out_count - 3'd1;
      data_timer <= 13'd4800;
    end
  end
end

endmodule
