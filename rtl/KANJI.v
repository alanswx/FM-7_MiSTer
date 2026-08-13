// Kanji ROM, $fd20-$fd23 (TODO.md P3-3).
//
// A 128 KB mask ROM holding 4096 glyphs of 16x16 pixels, 32 bytes each. The CPU
// writes a 16-bit glyph address to $fd20/$fd21 and reads the two bytes of one
// scanline back from $fd22/$fd23. The ROM address is the glyph address shifted
// left one, with $fd22 selecting the even byte and $fd23 the odd:
//
//   MAME  kanji_r: `addr = m_kanji_address << 1; case 2: return KROM[addr];
//                   case 3: return KROM[addr+1];`            (fm7.cpp:1054)
//   CSP   kanjirom.cpp:83: `data_table[(kanjiaddr.d << 1) & 0x1ffff]` and `+ 1`
//
// Both make $fd20/$fd21 write-only and $fd22/$fd23 read-only, which the decode
// in MDECODE.v reproduces.
//
// This is an OPTIONAL expansion on a real FM-7 -- MAME loads it with
// ROM_LOAD_OPTIONAL and CSP gates it behind `connect_kanjiroml1` -- so software
// probes for it. Present-and-working is the right default: the alternative is
// that any title wanting Japanese text either falls back to a worse path or
// gives up.
//
// THE IMAGE LIVES IN SDRAM, NOT BLOCK RAM.
//
// At 128 KB this was 128 M10K -- 23% of the DE10-Nano's 553 -- on a design that
// missed the device by 137. It is also the only ROM here that can move: every
// other one is fetched by a CPU every bus cycle or by the raster every
// character cell, where SDRAM latency would be a wrong instruction or a wrong
// pixel. This one is read through a slow, software-driven I/O window, and the
// protocol hands us the latency for free -- the CPU writes the glyph address
// before it reads the bytes, so the word is prefetched a whole bus cycle ahead
// and is already latched when $fd22/$fd23 is strobed.
//
// The image arrives as boot.rom on ioctl index 0, which the MiSTer framework
// uploads automatically at core start, so this needs no user action.

module KANJI(
  input CLKSYS,
  input RESETBn,
  input [7:0] MDATABUS_in,
  input WFD20n,
  input WFD21n,
  input RFD22n,
  input RFD23n,
  output [7:0] MDATABUS_out,

  // SDRAM read channel. REQ stays asserted until the arbiter grants it and the
  // controller answers, so losing the bus to the tape stream only delays us.
  output [16:0] KANJI_ADDR,
  output        KANJI_RD,
  input         KANJI_GNT,     // this cycle's request went to the controller
  input         KANJI_READY,   // KANJI_DATA is valid for that grant
  input  [15:0] KANJI_DATA
);

reg [15:0] kaddr;
reg wr20_d, wr21_d;

// Latch on the LEADING edge of the write strobe, where the data is valid.
//
// FLAGS.v's $fd37 register latched on the trailing edge and read back $00 for
// ever: a 74LS374 on the schematic captures there and the 6809's data-hold
// window covers it, but in zero-delay RTL the CPU has already released the bus.
// Same family as P0-3 and P1-4, so do it the same way they were fixed.
wire wr20_stb = wr20_d & ~WFD20n;
wire wr21_stb = wr21_d & ~WFD21n;

always @(posedge CLKSYS) begin
  wr20_d <= WFD20n;
  wr21_d <= WFD21n;
  if (~RESETBn) kaddr <= 16'h0000;
  else begin
    if (wr20_stb) kaddr[15:8] <= MDATABUS_in;
    if (wr21_stb) kaddr[7:0]  <= MDATABUS_in;
  end
end

// Prefetch. Either half of the address being written starts a fetch of the
// 16-bit word at (kaddr << 1), which holds both bytes the CPU is about to ask
// for -- the even byte in [7:0] and the odd in [15:8], the same packing the
// tape decoder reads. Software writes both halves, so the second write simply
// re-issues with the settled address.
reg        req;
reg        outstanding;
reg [15:0] word;
reg [15:0] fetch_addr;

wire [15:0] next_addr = { wr20_stb ? MDATABUS_in : kaddr[15:8],
                          wr21_stb ? MDATABUS_in : kaddr[7:0] };

assign KANJI_ADDR = { fetch_addr, 1'b0 };
assign KANJI_RD   = req;

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    req         <= 1'b0;
    outstanding <= 1'b0;
    word        <= 16'h0000;
    fetch_addr  <= 16'h0000;
  end
  else begin
    if (wr20_stb | wr21_stb) begin
      fetch_addr  <= next_addr;
      req         <= 1'b1;
      outstanding <= 1'b0;
    end
    else begin
      if (req & KANJI_GNT) begin
        req         <= 1'b0;
        outstanding <= 1'b1;
      end
      if (outstanding & KANJI_READY) begin
        word        <= KANJI_DATA;
        outstanding <= 1'b0;
      end
    end
  end
end

wire [7:0] rom_dout = (~RFD23n) ? word[15:8] : word[7:0];
assign MDATABUS_out = (RFD22n & RFD23n) ? 8'h00 : rom_dout;

endmodule
