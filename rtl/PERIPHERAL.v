
module PERIPHERAL(
    // The three write registers below were clocked by their own decode strobes.
    // See the comment on m10/m2/m9 -- that pattern cost a hardware-only OS-9
    // regression in FLAGS.v, so it is retired here too.
    input CLKSYS,
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

// m10 (tape), m2, and m9 ($fd05: sub halt / cancel / Z80) used to be clocked by
// their own write strobes -- `negedge WFD00n`, `posedge WFD01n`, `posedge
// WFD05n`. Those strobes are 74138 chip-select outputs, i.e. combinational
// logic over the address bus, and a LUT-built decode GLITCHES as address bits
// arrive skewed. Verilator gives one clean edge per access; Quartus gives a
// ripple clock on general routing where every glitch is a spurious edge.
//
// This is not theoretical. The identical pattern in FLAGS.v produced an OS-9
// regression that appeared ONLY on real hardware and was invisible in
// simulation, and moving those four flip-flops onto CLKSYS fixed it. m9 is the
// most exposed register in the core after those: it holds SUBHALTREQn and
// CANCELn, so a spurious edge either halts the sub CPU or fires an attention
// interrupt at it -- and FLAGS' m45 now edge-detects CANCELn, so a glitch here
// feeds straight into the flip-flop that regression was about.
//
// Note m9 and m2 also latched on the TRAILING edge of an active-low strobe,
// which is separately the P1-4 hazard: by then the CPU may already have
// released the bus. Sampling on CLKSYS while the strobe is low takes the data
// where it is unambiguously valid, so that risk goes away as well.
// The strobes are FILTERED through a 3-bit shift register rather than merely
// compared against the previous cycle. A decode glitch is one or two CLKSYS
// cycles wide, so a one-cycle detector still reports it as an edge -- the very
// thing being fixed. Taking the edge from the filtered copy makes a transient
// have to persist to be believed. The sample lands two CLKSYS cycles into the
// strobe rather than on its edge, and E-high is about 19 CLKSYS cycles, so it
// stays comfortably inside the access. Shape from DERIVED_CLOCKS.md.
reg [2:0] wfd00_sr, wfd01_sr, wfd05_sr;
always @(posedge CLKSYS) begin
  wfd00_sr <= { wfd00_sr[1:0], WFD00n };
  wfd01_sr <= { wfd01_sr[1:0], WFD01n };
  wfd05_sr <= { wfd05_sr[1:0], WFD05n };
  if (~RESETBn) begin
    m10 <= 8'd0;
    m2  <= 8'd0;
    m9  <= 3'd0;
  end
  else begin
    // filtered LEADING edge (these strobes are active low)
    if (wfd00_sr[2] & ~wfd00_sr[1]) m10 <= MDATABUS_in;                        // $fd00
    if (wfd01_sr[2] & ~wfd01_sr[1]) m2  <= MDATABUS_in;                        // $fd01
    if (wfd05_sr[2] & ~wfd05_sr[1]) m9  <= { MDATABUS_in[7:6], MDATABUS_in[0] }; // $fd05
  end
end

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
