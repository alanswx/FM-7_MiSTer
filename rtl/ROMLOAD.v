
// ROMLOAD: copy one system ROM set out of SDRAM into the four loadable block
// RAMs, while the machine is held in reset.
//
// WHY THIS EXISTS, and why the ROMs are not simply duplicated in block RAM:
// the FM-7's main ROM (m151) is 32768 deep and therefore costs 32 M10K blocks
// on its own. A second copy for a second machine variant would cost another
// 32, plus 2 for the character generator -- 34 of the 37 free blocks recorded
// in TODO.md's FPGA fit section. Staging the sets in SDRAM instead and paging
// the selected one down into the existing block RAMs costs ZERO blocks, and
// SDRAM has ~30 MB free above the kanji ROM.
//
// The CPU cannot run from SDRAM -- it fetches every bus cycle, and the kanji
// ROM was moved off-chip only because it is read through a slow I/O window
// that prefetches. So this is a copy, not a redirect.
//
// WHEN IT RUNS: whenever the selected set differs from the one currently in
// the block RAMs, including immediately after reset. BUSY holds the machine in
// reset for the duration, so no CPU ever sees a half-written ROM. Changing the
// OSD option therefore resets the machine, which is correct -- swapping the
// BASIC ROM under a running interpreter would not be.
//
// WHEN IT DOES NOT RUN: when no ROM set was uploaded (SET_VALID low). The
// block RAMs then keep their synthesis-time $readmemh contents, so a card with
// no ROM-set file boots exactly as it did before this module existed.
//
// SDRAM returns the byte at the requested address in DATA[7:0] regardless of
// address parity (see rtl/sdram.sv's `dout` mux), so this reads a byte at a
// time and ignores the high half. ~45 K reads is a few milliseconds behind
// reset -- not worth the complexity of pairing them.

module ROMLOAD #(
  parameter [24:0] BASE   = 25'h0420000,   // where the uploaded sets live
  parameter [24:0] STRIDE = 25'h0010000    // 64 KB per set
)(
  input             CLKSYS,
  input             RESETn,          // RAW system reset -- never BUSY-gated

  input             SET_VALID,       // a ROM set of at least one full set arrived
  input             SET_HAS_1,       // ...and it is long enough to hold set 1
  input             SET_SEL,         // 0 = set 0, 1 = set 1

  // SDRAM client, same handshake as KANJI.v: assert RD, wait GNT, wait READY.
  output     [24:0] ROMSET_ADDR,
  output            ROMSET_RD,
  input             ROMSET_GNT,
  input             ROMSET_READY,
  input      [15:0] ROMSET_DATA,

  // Load bus to the four rom_loadable instances. One strobe each; the shared
  // address is 15 bits and each instance takes the low bits it declares.
  output reg        LD_M151_WR,
  output reg        LD_M152_WR,
  output reg        LD_M153_WR,
  output reg        LD_M154_WR,
  output reg [14:0] LD_ADDR,
  output reg  [7:0] LD_DATA,

  output            BUSY
);

// Set layout. These offsets are the file format -- tools/make-romset.py writes
// them and docs/ROMSETS.md documents them. Changing one means changing all
// three.
localparam [16:0] OFF_M151 = 17'h00000;   // main ROM / F-BASIC   32768
localparam [16:0] OFF_M152 = 17'h08000;   // boot ROM, 4 banks     2048
localparam [16:0] OFF_M153 = 17'h08800;   // character generator   2048
localparam [16:0] OFF_M154 = 17'h09000;   // sub monitor           8192
localparam [16:0] TOTAL    = 17'h0B000;   // 45056 bytes

localparam ST_IDLE = 2'd0, ST_REQ = 2'd1, ST_WAIT = 2'd2;

reg  [1:0]  st;
reg  [16:0] idx;
reg         loaded_valid;   // a set has been paged in since reset
reg         loaded_sel;     // which one

// Fall back to set 0 if set 1 was asked for but the file is too short to hold
// it. Loading past the end of the file would page in whatever else is in
// SDRAM, which is a far worse failure than quietly giving the user set 0.
wire eff_sel  = (SET_SEL & SET_HAS_1);
wire need_load = SET_VALID & (~loaded_valid | (loaded_sel != eff_sel));

assign BUSY        = need_load | (st != ST_IDLE);
assign ROMSET_ADDR = BASE + (eff_sel ? STRIDE : 25'd0) + {8'd0, idx};
assign ROMSET_RD   = (st == ST_REQ);

always @(posedge CLKSYS) begin
  if (!RESETn) begin
    st           <= ST_IDLE;
    idx          <= 17'd0;
    loaded_valid <= 1'b0;
    loaded_sel   <= 1'b0;
    LD_M151_WR   <= 1'b0;
    LD_M152_WR   <= 1'b0;
    LD_M153_WR   <= 1'b0;
    LD_M154_WR   <= 1'b0;
  end
  else begin
    LD_M151_WR <= 1'b0;
    LD_M152_WR <= 1'b0;
    LD_M153_WR <= 1'b0;
    LD_M154_WR <= 1'b0;

    case (st)
      ST_IDLE:
        if (need_load) begin
          idx <= 17'd0;
          st  <= ST_REQ;
        end

      ST_REQ:
        if (ROMSET_GNT) st <= ST_WAIT;

      ST_WAIT:
        if (ROMSET_READY) begin
          LD_DATA <= ROMSET_DATA[7:0];
          // Subtract the region base rather than slicing idx. Slicing only
          // works while every offset happens to be aligned to its region size,
          // and OFF_M154 ($9000) is NOT 8192-aligned -- idx[12:0] there starts
          // at $1000, not 0, which would have written the sub monitor into
          // itself at a 4 KB rotation. Subtraction is correct for any layout.
          if (idx < OFF_M152) begin
            LD_ADDR    <= (idx - OFF_M151);
            LD_M151_WR <= 1'b1;
          end
          else if (idx < OFF_M153) begin
            LD_ADDR    <= (idx - OFF_M152);
            LD_M152_WR <= 1'b1;
          end
          else if (idx < OFF_M154) begin
            LD_ADDR    <= (idx - OFF_M153);
            LD_M153_WR <= 1'b1;
          end
          else begin
            LD_ADDR    <= (idx - OFF_M154);
            LD_M154_WR <= 1'b1;
          end

          if (idx == TOTAL - 17'd1) begin
            st           <= ST_IDLE;
            loaded_valid <= 1'b1;
            loaded_sel   <= eff_sel;
          end
          else begin
            idx <= idx + 17'd1;
            st  <= ST_REQ;
          end
        end
    endcase
  end
end

endmodule
