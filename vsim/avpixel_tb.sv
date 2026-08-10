module AVPIXEL_tb;
  reg [7:0] b3 = 0, b2 = 0, b1 = 0, b0 = 0;
  reg [7:0] r3 = 0, r2 = 0, r1 = 0, r0 = 0;
  reg [7:0] g3 = 0, g2 = 0, g1 = 0, g0 = 0;
  reg [2:0] pixel_bit = 3'd0;
  wire [11:0] code;

  AVPIXEL dut(
    .B3(b3), .B2(b2), .B1(b1), .B0(b0),
    .R3(r3), .R2(r2), .R1(r1), .R0(r0),
    .G3(g3), .G2(g2), .G1(g1), .G0(g0),
    .PIXEL_BIT(pixel_bit), .CODE(code)
  );

  task check(input [11:0] wanted, input [255:0] label);
    begin
      #1;
      if (code !== wanted) begin
        $display("FAIL %s got=%03x wanted=%03x", label, code, wanted);
        $fatal(1);
      end
      $display("PASS %s = %03x", label, code);
    end
  endtask

  initial begin
    // One MSB in each reference plane must produce the matching DAC bit.
    b3 = 8'h80; b2 = 8'h80; b1 = 8'h80; b0 = 8'h80;
    r3 = 8'h80; r2 = 8'h80; r1 = 8'h80; r0 = 8'h80;
    g3 = 8'h80; g2 = 8'h80; g1 = 8'h80; g0 = 8'h80;
    check(12'hfff, "all planes, leftmost pixel");

    b3 = 8'h80; b2 = 8'h00; b1 = 8'h00; b0 = 8'h00;
    r3 = 8'h00; r2 = 8'h80; r1 = 8'h00; r0 = 8'h00;
    g3 = 8'h00; g2 = 8'h00; g1 = 8'h80; g0 = 8'h00;
    check(12'h248, "G1/R2/B3 mapping");

    // The rightmost bit is selected from the LSB, matching the shift-register
    // order used by the raster path.
    pixel_bit = 3'd7;
    b3 = 8'h01; b2 = 8'h00; b1 = 8'h00; b0 = 8'h01;
    r3 = 8'h00; r2 = 8'h01; r1 = 8'h00; r0 = 8'h00;
    g3 = 8'h00; g2 = 8'h00; g1 = 8'h00; g0 = 8'h01;
    check(12'h149, "rightmost pixel");

    $display("AVPIXEL TEST PASS");
    $finish;
  end
endmodule
