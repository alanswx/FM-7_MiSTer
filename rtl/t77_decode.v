
module t77_decode(
  input CLKSYS,
  input start,
  input [15:0] data,
  input data_stb,
  input rewind,
  input [24:0] image_size,   // bytes loaded over ioctl; 0 = unknown
  output eot,                // end of tape reached
  output reg [24:0] sdram_addr,
  output reg sdram_rd,
  output sout
);

reg clk_9us = 0;
reg pstart;
reg [15:0] counter = 0;
reg s;
reg [14:0] len;
reg sending;
// Start past the 16-byte "XM7 TAPE IMAGE 0" header, the same place the
// rewind path below uses. This was 25'h62, which skipped 82 bytes of real
// tape data on the first play after power-on.
reg [24:0] addr = 25'd16;
reg [15:0] init;

assign sout = s;

`ifdef DEBUG_TAPE
reg [24:0] dbg_entries   = 0;   // entries latched
reg [31:0] dbg_ticks     = 0;   // sum of the `len` values we loaded
reg [31:0] dbg_tick_count = 0;  // clk_9us periods actually elapsed
always @(posedge clk_9us) dbg_tick_count <= dbg_tick_count + 32'd1;
`endif

// Without this the address counter ran forever: a 238 KB image played out
// and then kept reading whatever else happened to be in SDRAM. image_size
// is latched from the ioctl download by the top level.
assign eot = (image_size != 25'd0) && (addr >= image_size);

always @(posedge CLKSYS) begin
  if (counter >= DIV_9us) begin
    counter <= 16'd0;
    clk_9us <= ~clk_9us;
  end
  else begin
    counter <= counter + 16'd1;
  end
end

always @(posedge CLKSYS) begin
  pstart <= start;
  if (~pstart & start) begin
    init <= 16'h4000;
    $display("--------- motor on ---------");
  end
  if (~start & pstart) begin
    sending <= 1'b0;
    $display("--------- motor off---------");
  end
  if (init) begin
    init <= init - 16'h1;
    if (init == 16'h1) sending <= 1'b1;
  end
end

always @(posedge clk_9us, posedge rewind) begin
  if (rewind) begin
    addr <= 25'd16;
    sdram_addr <= addr;
  end
  else begin
    if (sdram_rd) begin
      if (data_stb) begin
        sdram_rd <= 1'b0;
        s <= data[7];
        len <= { data[6:0], data[15:8] };
`ifdef DEBUG_TAPE
        // Every entry as it is actually latched, against what the file holds.
        // `len` is in 9.125 us ticks; a 1200 baud half-bit is ~47 and a 2400
        // baud half-bit is ~25, so anything near 0 means the word is wrong.
        dbg_entries <= dbg_entries + 25'd1;
        dbg_ticks   <= dbg_ticks + { 10'd0, data[6:0], data[15:8] };
        if (dbg_entries < 25'd24)
          $display("T77 entry %0d addr=$%06x data=$%04x -> level=%0d len=%0d",
                   dbg_entries, sdram_addr, data, data[7], {data[6:0], data[15:8]});
        if (eot)
          $display("T77SUM entries=%0d summed_len=%0d ticks_elapsed=%0d",
                   dbg_entries, dbg_ticks, dbg_tick_count);
`endif
      end
    end
    else if (sending && ~eot) begin
      if (len) begin
        len <= len - 15'd1;
      end
      else begin
        sdram_addr <= addr;
        sdram_rd <= 1'b1;
        addr <= addr + 25'd2;
      end
    end
  end
end


endmodule
