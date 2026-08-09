
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
reg next_s;
reg [14:0] next_len;
reg next_valid;
reg fetch_next;
// Start past the 18-byte XM7 header. The final two bytes are header metadata
// and are part of the file header, not a tape segment.
reg [24:0] addr = 25'd18;
reg [15:0] init;

assign sout = s;

wire decoded_s = !((data[7:0] < 8'h40) ||
                   ((data[7:0] == 8'h7f) && (data[15:8] == 8'hff)));
wire [14:0] decoded_len = { 7'd0, data[15:8] };

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
    addr <= 25'd18;
    sdram_addr <= 25'd18;
    sdram_rd <= 1'b0;
    len <= 15'd0;
    next_valid <= 1'b0;
    fetch_next <= 1'b0;
  end
  else begin
    if (sdram_rd) begin
      if (data_stb) begin
        sdram_rd <= 1'b0;
        if (fetch_next) begin
          // Prefetches complete while the current segment is still running.
          // If the boundary is already due, consume the just-arrived entry
          // directly; otherwise retain it for the exact boundary below.
          if (len == 15'd1) begin
            s <= decoded_s;
            len <= decoded_len;
            next_valid <= 1'b0;
          end
          else begin
            next_s <= decoded_s;
            next_len <= decoded_len;
            next_valid <= 1'b1;
          end
        end
        else begin
          // A T77 entry is stored as (level byte, duration byte). The SDRAM
          // interface presents the byte at the even address in data[7:0], so
          // data[7:0] is the level byte and data[15:8] is the duration. XM7
          // treats level bytes below $40 as low, except $7f/$ff which is the
          // long-silence marker and is also low.
          s <= decoded_s;
          len <= decoded_len;
        end
`ifdef DEBUG_TAPE
        // Every entry as it is actually latched, against what the file holds.
        // `len` is in 9.125 us ticks; a 1200 baud half-bit is ~47 and a 2400
        // baud half-bit is ~25, so anything near 0 means the word is wrong.
        dbg_entries <= dbg_entries + 25'd1;
        dbg_ticks   <= dbg_ticks + { 24'd0, data[15:8] };
        if (dbg_entries < 25'd24)
          $display("T77 entry %0d addr=$%06x data=$%04x -> level=%0d len=%0d",
                   dbg_entries, sdram_addr, data,
                   !((data[7:0] < 8'h40) ||
                     ((data[7:0] == 8'h7f) && (data[15:8] == 8'hff))),
                   data[15:8]);
        if (eot)
          $display("T77SUM entries=%0d summed_len=%0d ticks_elapsed=%0d",
                   dbg_entries, dbg_ticks, dbg_tick_count);
`endif
      end

      // Count down the current segment even while a prefetch is in flight.
      // This prevents the SDRAM round trip from stretching every T77 level.
      if (len > 15'd1)
        len <= len - 15'd1;
      else if (len == 15'd1 && !data_stb && next_valid) begin
        s <= next_s;
        len <= next_len;
        next_valid <= 1'b0;
      end
    end
    else if (sending && ~eot) begin
      if (len > 15'd1) begin
        // Four 9-us ticks leave ample time for the SDRAM read to complete.
        if (!next_valid && len <= 15'd4) begin
          sdram_addr <= addr;
          sdram_rd <= 1'b1;
          fetch_next <= 1'b1;
          addr <= addr + 25'd2;
        end
        len <= len - 15'd1;
      end
      else if (len == 15'd1 && next_valid) begin
        s <= next_s;
        len <= next_len;
        next_valid <= 1'b0;
      end
      else if (len == 15'd1) begin
        len <= 15'd0;
      end
      else if (next_valid) begin
        s <= next_s;
        len <= next_len;
        next_valid <= 1'b0;
      end
      else begin
        sdram_addr <= addr;
        sdram_rd <= 1'b1;
        fetch_next <= 1'b0;
        addr <= addr + 25'd2;
      end
    end
  end
end


endmodule
