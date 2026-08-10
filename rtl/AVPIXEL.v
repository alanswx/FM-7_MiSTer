// FM77AV 320x200 analog pixel-code combiner.
//
// The 4096-colour mode stores four bit-planes for each gun.  The reference
// renderer labels the planes 3..0 and assembles the DAC index as
// {G3,G2,G1,G0,R3,R2,R1,R0,B3,B2,B1,B0}.  Each input byte is a horizontal
// run of eight pixels; PIXEL_BIT selects the current pixel, MSB first.

module AVPIXEL(
  input [7:0] B3,
  input [7:0] B2,
  input [7:0] B1,
  input [7:0] B0,
  input [7:0] R3,
  input [7:0] R2,
  input [7:0] R1,
  input [7:0] R0,
  input [7:0] G3,
  input [7:0] G2,
  input [7:0] G1,
  input [7:0] G0,
  input [2:0] PIXEL_BIT,
  output [11:0] CODE
);

wire [2:0] bit_index = 3'd7 - PIXEL_BIT;

assign CODE = {
  G3[bit_index], G2[bit_index], G1[bit_index], G0[bit_index],
  R3[bit_index], R2[bit_index], R1[bit_index], R0[bit_index],
  B3[bit_index], B2[bit_index], B1[bit_index], B0[bit_index]
};

endmodule
