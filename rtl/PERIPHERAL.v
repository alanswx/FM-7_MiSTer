
module PERIPHERAL(
    input [7:0] MDATABUS_in,
    output [7:0] MDATABUS_out,
    input WFD00n,
    input WFD01n,
    input WFD05n,
    input RFD02n,
    input RFD03n,
    input RESETBn,
    input LPMASKn,
    output reg LPINTn,
    output IRQCLRn,
    output reg LPBUSY,
    output GHn,
    output Z80W,
    output CANCELn,
    output SUBHALTREQn,
    output motor,
    input cin
);

reg [7:0] m10;
reg [7:0] m2;
reg [2:0] m9;
wire reset = ~RESETBn;

assign motor = m10[1];

// m10: TAPE
always @(negedge WFD00n or negedge RESETBn)
  if (~RESETBn) m10 <= 8'd0;
  else m10 <= MDATABUS_in;

always @(posedge WFD01n or posedge reset)
  if (reset) m2 <= 8'd0;
  else m2 <= MDATABUS_in;

always @(posedge WFD05n or posedge reset)
  if (reset) m9 <= 3'd0;
  else m9 <= { MDATABUS_in[7:6], MDATABUS_in[0] };

wire [8:1] CN3;

// Expansion connector. Nothing in this core drives it, so it is tied off
// explicitly rather than left floating: CN2[16] is the printer ACK line,
// which clocks the LPINT flip-flop below, and an undriven wire there is an
// undefined clock. Idle high = no acknowledge pulse.
wire [34:1] CN2 = {34{1'b1}};

// $FD02 read.
//   bit 7    cassette input
//   bit 6-4  always 1
//   bit 3    printer PE      bit 2  printer ACK
//   bit 1    printer /ERROR  bit 0  printer BUSY
//
// This used to read bits 6..1 out of `CN2`, an expansion-connector bus that
// is declared in this module and never driven anywhere -- so all six read
// back as 0. MAME's cassette_printer_r forces bits 6..4 high (`ret |= 0x70`)
// and takes 3..0 from the Centronics device. With no printer attached those
// lines idle high, so they are tied high here and the connector bus is gone.
//
// Bit 7 also reads high whenever the motor is off: MAME notes "cassette input
// is high when not in use", and t77_decode drives `cin` regardless of the
// relay, so without this the port reports tape data while stopped.
wire tape_in = cin | ~motor;

assign MDATABUS_out = RFD02n ? 8'hff : { tape_in, 6'b111111, LPBUSY };

assign CN3[4] = m10[0]; // TAPEOUT
assign CN3[6] = m10[1]; // MOTOR

assign GHn = ~m9[0];
assign Z80W = m9[0];
assign CANCELn = ~m9[1];
assign SUBHALTREQn = ~m9[2];

// ack or reset
wire m39_q11 = ~(CN2[16] & RESETBn);

wire s0 = ~m10[6];
always @(posedge s0 or posedge m39_q11)
  if (m39_q11) LPBUSY <= 1'b0;
  else LPBUSY <= 1'b1;

assign IRQCLRn = RFD03n & RESETBn;
wire s1 = ~IRQCLRn;

// m15
always @(posedge CN2[16] or posedge s1)
  if (s1) LPINTn <= 1'b1;
  else LPINTn <= LPMASKn;

endmodule
