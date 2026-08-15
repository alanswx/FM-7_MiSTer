// FM77AV keyboard encoder register pair.
//
// The base FM-7 exposes a matrix keyboard through D400/D401. The AV adds an
// independent command/data encoder at D431/D432, aliased every 64 bytes in
// the sub-I/O page. Physical key injection remains on the existing keyboard
// path until the scan-code translation is wired in.
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
wire write     = (data_sel || stat_sel) && ~SWTQEn;

reg [7:0] command;
reg [7:0] mode;
reg [7:0] leds;
reg [7:0] data_reg;
reg       data_valid;
reg       command_pending;
reg [12:0] acknowledge_timer;

wire [7:0] status = {~data_valid, 6'd0,
                     (acknowledge_timer == 13'd0)};

assign SEL  = data_sel || stat_sel;
assign DOUT = data_sel ? data_reg : status;
assign MMR_DOUT = (MMR_ADDR[5:0] == 6'h31) ? data_reg : status;

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    command           <= 8'd0;
    mode              <= 8'd0; // FM-7 coding at power-on
    leds              <= 8'd0;
    data_reg          <= 8'd0;
    data_valid        <= 1'b0;
    command_pending   <= 1'b0;
    acknowledge_timer <= 13'd0;
  end
  else begin
    if (acknowledge_timer != 13'd0)
      acknowledge_timer <= acknowledge_timer - 13'd1;

    if (write) begin
      acknowledge_timer <= 13'd4800; // approximately 100 us at 48 MHz
      if (!command_pending) begin
        command <= SDATA_in;
        case (SDATA_in)
          8'h01: begin data_reg <= mode; data_valid <= 1'b1; command <= 8'd0; end
          8'h03: begin data_reg <= leds; data_valid <= 1'b1; command <= 8'd0; end
          // RTC and video-control commands are accepted as base-AV stubs.
          8'h00, 8'h02, 8'h04, 8'h05, 8'h80: command_pending <= 1'b1;
          8'h81, 8'h82, 8'h83, 8'h84: command <= 8'd0;
          default: command <= 8'd0;
        endcase
      end
      else begin
        case (command)
          8'h00: if (SDATA_in <= 8'd2) mode <= SDATA_in;
          8'h02: if (SDATA_in <= 8'd3) leds <= SDATA_in;
          8'h04: ; // repeat enable/disable, accepted
          8'h05: ; // repeat timing, accepted as a stub
          8'h80: ; // RTC write payload, accepted as a stub
          default: ;
        endcase
        command <= 8'd0;
        command_pending <= 1'b0;
      end
    end

    if (data_sel && SRWB && data_valid)
      data_valid <= 1'b0;
  end
end

endmodule
