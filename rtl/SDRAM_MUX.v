// SDRAM arbiter: the tape stream, the kanji ROM, and the ioctl downloads that
// fill both.
//
// This lives in rtl/ rather than in the two top levels because getting it
// wrong breaks tape playback, and FM-7_MiSTer.sv and vsim/sim.v would then
// disagree about how -- exactly the class of divergence that makes a
// simulation result meaningless.
//
// Priority is tape, because tape playback is a real-time path with a byte due
// on a schedule. Kanji can always wait: it prefetches when the CPU writes the
// glyph address, a whole bus cycle before the CPU reads the byte, and its
// request stays asserted until it is granted.
//
// Writes (ioctl) outrank both. They only happen while a file is being loaded,
// when neither client is running.

module SDRAM_MUX(
  input             CLKSYS,

  // ioctl download, already routed to the right base address by the caller
  input             DL_WR,
  input      [24:0] DL_ADDR,
  input       [7:0] DL_DATA,

  // tape client
  input      [24:0] TAPE_ADDR,
  input             TAPE_RD,
  output            TAPE_READY,

  // kanji client
  input      [24:0] KANJI_ADDR,
  input             KANJI_RD,
  output            KANJI_GNT,
  output            KANJI_READY,

  // to the controller
  output     [24:0] SD_ADDR,
  output      [7:0] SD_DIN,
  output            SD_WE,
  output            SD_RD,
  input             SD_READY,
  input      [15:0] SD_DOUT,
  output     [15:0] SD_DOUT_OUT
);

// Kanji is granted only on a cycle the tape is not asking for and no download
// is in flight, so the tape's own handshake is bit-for-bit what it was before
// this block existed.
assign KANJI_GNT = KANJI_RD & ~TAPE_RD & ~DL_WR;

assign SD_ADDR = DL_WR     ? DL_ADDR   :
                 TAPE_RD   ? TAPE_ADDR : KANJI_ADDR;
assign SD_DIN  = DL_DATA;
assign SD_WE   = DL_WR;
assign SD_RD   = TAPE_RD | KANJI_GNT;

// Which client owns the outstanding read, so SD_READY is steered to it. The
// controller reports ready both as "data valid" and as "idle", and the tape
// decoder has always consumed it as a data strobe -- keep that untouched and
// gate the kanji side on ownership instead.
reg owner_kanji;
always @(posedge CLKSYS) begin
  if (SD_RD) owner_kanji <= KANJI_GNT & ~TAPE_RD;
end

`ifdef DEBUG_KANJI
// Why the kanji client never gets granted: print the two signals that can
// veto it, on any change, while a kanji request is asserted.
integer mdbg_n = 0;
reg tr_d, dl_d, kr_d;
always @(posedge CLKSYS) begin
  tr_d <= TAPE_RD; dl_d <= DL_WR; kr_d <= KANJI_RD;
  if (mdbg_n < 40 && KANJI_RD) begin
    $display("MUX  TAPE_RD=%b DL_WR=%b KANJI_RD=%b -> GNT=%b",
             TAPE_RD, DL_WR, KANJI_RD, KANJI_GNT);
    mdbg_n = mdbg_n + 1;
  end
end
`endif

assign TAPE_READY  = SD_READY;
assign KANJI_READY = SD_READY & owner_kanji;
assign SD_DOUT_OUT = SD_DOUT;

endmodule
