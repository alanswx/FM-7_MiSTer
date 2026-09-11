
// A `rom` whose contents can be replaced at run time.
//
// The read path is character-for-character the same as rom.v -- same inferred
// memory, same synthesis-time $readmemh image -- with one write port added so
// a ROM set uploaded from the SD card can overwrite it.
//
// The $readmemh image is still the power-up content. That is what makes the
// uploaded set OPTIONAL rather than required: with no ROM set on the card the
// machine comes up on the ROMs baked into the .rbf, exactly as it did before
// this module existed. Nothing about an existing install changes.
//
// Read and write share `clk` deliberately. That makes this a simple dual-port
// memory, which is what an M10K already is -- a Cyclone V block is true
// dual-port whether or not you use the second port -- so the write port is
// expected to cost no additional blocks. Do not take that on trust; the FPGA
// fit section in TODO.md prices every change from the map report's RAM
// summary, and this one is priced there too.
//
// This is a separate module from rom.v rather than a parameter on it so that
// the eight ROMs which are NOT overridable (the whole FM77AV set, the two PCM
// tables) keep their read-only inference and gain no dangling ports.

module rom_loadable #(
  parameter memfile="",
  parameter addr_width=12,
  parameter data_width=8
)
(
  input clk,
  input [addr_width-1:0] addr,
  output [data_width-1:0] dout,
  input ce_n,

  // ROM-set load port, driven by ROMLOAD.v out of SDRAM.
  input                   ld_wr,
  input [addr_width-1:0]  ld_addr,
  input [data_width-1:0]  ld_data
);

reg [data_width-1:0] q;
reg [data_width-1:0] mem[(1<<addr_width)-1:0];

assign dout = ce_n ? 0 : q;

initial begin
  $readmemh(memfile, mem);
end

always @(posedge clk) begin
  if (ld_wr) mem[ld_addr] <= ld_data;
  q <= mem[addr];
end

endmodule
