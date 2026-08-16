// Directed check for the FM77AV MB61VH010 drawing ALU.
//
// The 2019 AV demo drives this block through the byte read-modify-write path,
// not the line drawer: it never writes $D42B.  So the cases that matter are
// "an intercepted VRAM access combines one byte across all three planes" and
// "the $D412 write mask, the $D41B plane disable and the compare slots gate
// which bits move".  Expected values come from 77AVEMU's VRAMDummyRead()
// (`fm77avcrtc.cpp:331-446`).
//
// A tiny behavioural stand-in for CRTRAM's port B supplies DRAW_Q_* one cycle
// after DRAW_ADDR, matching the registered dpram the real core uses.

module avhdraw_tb;
  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg        resetn = 1'b0;
  reg [15:0] saddr = 16'h0000;
  reg  [7:0] sdata = 8'h00;
  reg        swtqen = 1'b1;
  reg        seb = 1'b0;
  reg        scassel = 1'b1;
  reg        sub_vram_sel = 1'b0;
  reg [13:0] svradrs = 14'h0000;
  reg        mode_320 = 1'b0;
  reg        active_page = 1'b0;
  reg [13:0] vram_offset = 14'h0000;
  reg  [2:0] vpage_mask = 3'b000;

  wire        port_en;
  wire  [1:0] blk;
  wire [12:0] addr;
  wire        wr_b, wr_r, wr_g;
  wire  [7:0] din_b, din_r, din_g;
  wire        inhibit;
  wire        busy;
  wire  [7:0] dout;

  // One 8 KB byte per plane per block is enough for these cases.
  reg [7:0] mem_b [0:3][0:15];
  reg [7:0] mem_r [0:3][0:15];
  reg [7:0] mem_g [0:3][0:15];
  reg [7:0] q_b, q_r, q_g;

  always @(posedge clk) begin
    if (wr_b) mem_b[blk][addr[3:0]] <= din_b;
    if (wr_r) mem_r[blk][addr[3:0]] <= din_r;
    if (wr_g) mem_g[blk][addr[3:0]] <= din_g;
    q_b <= wr_b ? din_b : mem_b[blk][addr[3:0]];
    q_r <= wr_r ? din_r : mem_r[blk][addr[3:0]];
    q_g <= wr_g ? din_g : mem_g[blk][addr[3:0]];
  end

  AVHDRAW dut(
    .CLKSYS(clk), .RESETBn(resetn), .MACHINE_AV(1'b1),
    .SADDRBUS(saddr), .SDATA(sdata), .SWTQEn(swtqen),
    .SEB(seb), .SCASSEL(scassel), .SUB_VRAM_SEL(sub_vram_sel),
    .SVRADRS(svradrs), .AV_MODE_320(mode_320),
    .AV_ACTIVE_PAGE(active_page), .AV_VRAM_OFFSET(vram_offset),
    .VPAGE_MASK(vpage_mask),
    .DRAW_Q_B(q_b), .DRAW_Q_R(q_r), .DRAW_Q_G(q_g),
    .DRAW_PORT_EN(port_en), .DRAW_BLOCK(blk), .DRAW_ADDR(addr),
    .DRAW_WRITE_B(wr_b), .DRAW_WRITE_R(wr_r), .DRAW_WRITE_G(wr_g),
    .DRAW_DIN_B(din_b), .DRAW_DIN_R(din_r), .DRAW_DIN_G(din_g),
    .DRAW_INHIBIT(inhibit), .DRAW_BUSY(busy), .DRAW_DOUT(dout)
  );

  integer fails = 0;

  task check(input [7:0] actual, input [7:0] wanted, input [255:0] label);
    begin
      if (actual !== wanted) begin
        $display("FAIL %0s got=%02x wanted=%02x", label, actual, wanted);
        fails = fails + 1;
      end
      else $display("PASS %0s = %02x", label, actual);
    end
  endtask

  // The register write strobe is filtered through a three-stage shift
  // register, so hold it for several clocks the way a real sub-CPU E does.
  task reg_write(input [15:0] a, input [7:0] d);
    begin
      @(negedge clk);
      saddr = a; sdata = d; swtqen = 1'b0;
      repeat (6) @(negedge clk);
      swtqen = 1'b1;
      saddr = 16'h0000;
      repeat (4) @(negedge clk);
    end
  endtask

  // One intercepted sub-CPU VRAM access: E rises with the plane decode
  // asserted, and the engine's read-modify-write must complete inside it.
  task vram_access(input [13:0] a);
    begin
      @(negedge clk);
      svradrs = a; sub_vram_sel = 1'b1; seb = 1'b1;
      repeat (10) @(negedge clk);
      seb = 1'b0; sub_vram_sel = 1'b0;
      repeat (4) @(negedge clk);
    end
  endtask

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;
    repeat (4) @(negedge clk);

    // Seed the target byte on all three planes.
    mem_b[0][0] = 8'h0f;
    mem_r[0][0] = 8'hf0;
    mem_g[0][0] = 8'hcc;

    // ---- PSET, colour = B only, no mask ------------------------------------
    // 77AVEMU: v = (v & ~writeBits) | (rgb & writeBits), writeBits = ~maskBits.
    reg_write(16'hd412, 8'h00);  // write mask: touch every pixel
    reg_write(16'hd41b, 8'h00);  // all three planes enabled
    reg_write(16'hd411, 8'h01);  // colour = blue
    reg_write(16'hd410, 8'h80);  // enable, compare off, op 0 = PSET
    check(inhibit, 8'h01, "ALU enabled inhibits the plain sub write");
    vram_access(14'h0000);
    check(mem_b[0][0], 8'hff, "PSET blue plane");
    check(mem_r[0][0], 8'h00, "PSET red plane");
    check(mem_g[0][0], 8'h00, "PSET green plane");

    // ---- Write mask preserves the masked pixels ----------------------------
    mem_b[0][1] = 8'h00;
    mem_r[0][1] = 8'h00;
    mem_g[0][1] = 8'h00;
    reg_write(16'hd412, 8'hf0);  // 1 = preserve, so only the low nibble moves
    reg_write(16'hd411, 8'h07);  // colour = white
    vram_access(14'h0001);
    check(mem_b[0][1], 8'h0f, "masked PSET blue");
    check(mem_r[0][1], 8'h0f, "masked PSET red");
    check(mem_g[0][1], 8'h0f, "masked PSET green");

    // ---- Plane disable ------------------------------------------------------
    mem_b[0][2] = 8'h00;
    mem_r[0][2] = 8'h00;
    mem_g[0][2] = 8'h00;
    reg_write(16'hd412, 8'h00);
    reg_write(16'hd41b, 8'h02);  // red disabled
    vram_access(14'h0002);
    check(mem_b[0][2], 8'hff, "plane-disable leaves blue written");
    check(mem_r[0][2], 8'h00, "plane-disable holds red");
    check(mem_g[0][2], 8'hff, "plane-disable leaves green written");
    reg_write(16'hd41b, 8'h00);

    // ---- XOR ----------------------------------------------------------------
    mem_b[0][3] = 8'ha5;
    mem_r[0][3] = 8'h00;
    mem_g[0][3] = 8'h00;
    reg_write(16'hd411, 8'h01);  // colour = blue
    reg_write(16'hd410, 8'h84);  // op 4 = XOR
    vram_access(14'h0003);
    check(mem_b[0][3], 8'h5a, "XOR blue plane");
    check(mem_r[0][3], 8'h00, "XOR leaves red");

    // ---- TILE ---------------------------------------------------------------
    mem_b[0][4] = 8'h00;
    mem_r[0][4] = 8'h00;
    mem_g[0][4] = 8'h00;
    reg_write(16'hd41c, 8'h3c);  // tile B
    reg_write(16'hd41d, 8'hc3);  // tile R
    reg_write(16'hd41e, 8'h81);  // tile G
    reg_write(16'hd410, 8'h86);  // op 6 = TILEPAINT
    vram_access(14'h0004);
    check(mem_b[0][4], 8'h3c, "TILE blue plane");
    check(mem_r[0][4], 8'hc3, "TILE red plane");
    check(mem_g[0][4], 8'h81, "TILE green plane");

    // ---- Compare gates the write, and $D413 reports which pixels passed -----
    // Source colour is per pixel {G,R,B}.  Seed blue = $f0 with red and green
    // clear, so the left four pixels are colour 1 and the right four are 0.
    mem_b[0][5] = 8'hf0;
    mem_r[0][5] = 8'h00;
    mem_g[0][5] = 8'h00;
    reg_write(16'hd413, 8'h01);  // slot 0 matches colour 1
    reg_write(16'hd414, 8'h80);  // remaining slots disabled (b7 set)
    reg_write(16'hd415, 8'h80);
    reg_write(16'hd416, 8'h80);
    reg_write(16'hd417, 8'h80);
    reg_write(16'hd418, 8'h80);
    reg_write(16'hd419, 8'h80);
    reg_write(16'hd41a, 8'h80);
    reg_write(16'hd411, 8'h02);  // colour = red
    reg_write(16'hd410, 8'hc0);  // enable, compare on, sense = match, PSET
    vram_access(14'h0005);
    check(mem_r[0][5], 8'hf0, "compare passes only the matching pixels");
    check(mem_b[0][5], 8'h00, "compare-gated PSET clears blue where it wrote");
    saddr = 16'hd413;
    #1 check(dout, 8'hf0, "$D413 compare result");
    saddr = 16'h0000;

    // ---- Disabling the ALU releases the plain sub-CPU write ----------------
    reg_write(16'hd410, 8'h00);
    check(inhibit, 8'h00, "ALU disabled releases the sub write");
    mem_b[0][6] = 8'h11;
    vram_access(14'h0006);
    check(mem_b[0][6], 8'h11, "disabled ALU does not touch VRAM");

    if (fails == 0) $display("AVHDRAW TEST PASS");
    else begin
      $display("AVHDRAW TEST FAIL (%0d)", fails);
      $fatal(1);
    end
    $finish;
  end
endmodule
