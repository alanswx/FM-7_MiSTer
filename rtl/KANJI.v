
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
module KANJI(
  input CLKSYS,
  input RESETBn,
  input [7:0] MDATABUS_in,
  input WFD20n,
  input WFD21n,
  input RFD22n,
  input RFD23n,
  output [7:0] MDATABUS_out
);

reg [15:0] kaddr;
reg wr20_d, wr21_d;

// Latch on the LEADING edge of the write strobe, where the data is valid.
//
// FLAGS.v's $fd37 register latched on the trailing edge and read back $00 for
// ever: a 74LS374 on the schematic captures there and the 6809's data-hold
// window covers it, but in zero-delay RTL the CPU has already released the bus.
// Same family as P0-3 and P1-4, so do it the same way they were fixed.
always @(posedge CLKSYS) begin
  wr20_d <= WFD20n;
  wr21_d <= WFD21n;
  if (~RESETBn) kaddr <= 16'h0000;
  else begin
    if (wr20_d & ~WFD20n) kaddr[15:8] <= MDATABUS_in;
    if (wr21_d & ~WFD21n) kaddr[7:0]  <= MDATABUS_in;
  end
end

// (kaddr << 1) | byte-select, i.e. a 17-bit index into the 128 KB image.
wire        bytesel = ~RFD23n;
wire [16:0] rom_addr = { kaddr, bytesel };
wire [7:0]  rom_dout;

// Synchronous read, one CLKSYS behind the address -- the same `rom` primitive
// the F-BASIC and boot ROMs use. E is 1.2288 MHz against a 48 MHz CLKSYS, so a
// read strobe is tens of cycles wide and the output is long settled by the time
// the CPU samples.
rom #("./roms/kanji.rom.mem", 17, 8) u_kanji(
  .clk  ( CLKSYS          ),
  .addr ( rom_addr        ),
  .dout ( rom_dout        ),
  .ce_n ( RFD22n & RFD23n )
);

assign MDATABUS_out = (RFD22n & RFD23n) ? 8'h00 : rom_dout;

endmodule
