
// Page 12 on schematics.

module FLAGS(
  input SRWB,
  input SCRTSWn,
  input SRESETn,
  input SLEDn,
  input CANCELn,
  input SIRQCLRn,
  input [7:0] MDATABUS_in,
  input RESETBn,
  input WFD37n,
  input SRWBn,
  input SVDHALT,
  input SVRACSn,
  input SUBHALTREQn,
  input SBUSYSETn,
  input SHALTSTn,
  output SHALTn,
  output SVDOFFn,
  output SUBIRQn,
  output BUSY,
  output SHALTACn,
  output VPAGE1n,
  output VPAGE2n,
  output VPAGE3n,
  output DPAGE1,
  output DPAGE2,
  output DPAGE3,
  output INS
);

reg m56_5;
reg m56_9;
reg m45;
reg m44_5;
reg m44_8;
reg [7:0] m46;


assign SVDOFFn = m56_5;
assign INS = m56_9;

wire s0 = ~SRESETn;
always @(posedge SCRTSWn, posedge s0)
  if (s0) m56_5 <= 1'b1;
  else m56_5 <= SRWB;

always @(posedge SLEDn, posedge s0)
  if (s0) m56_9 <= 1'b1;
  else m56_9 <= SRWB;

wire s1 = ~(SRESETn & SIRQCLRn);
always @(posedge CANCELn, posedge s1)
  if (s1) m45 <= 1'b0;
  else m45 <= 1'b1;

// "The sub CPU wants VRAM", which gates the display-period halt below.
//
// LEAVE THIS POLARITY ALONE. Inverting it was tried and it is visibly wrong --
// F-BASIC's banner comes out with each character in a different colour, because
// the sub CPU becomes free to write VRAM mid-display and the three colour planes
// tear against the raster. The current sense keeps the display clean.
//
// It looks inverted against MAME, which is the trap. MAME (fm7_v.cpp) has
// `vram_access_r()` set the flag and `vram_access_w()` clear it, i.e. READ asks
// for VRAM; this latches SRWBn, which is `~RnW` and so HIGH on a write. But MAME
// never uses the flag for anything -- its halt check is commented out at
// fm7_v.cpp:643 and its sub CPU is never held for VRAM at all -- so MAME cannot
// arbitrate the question. The display can, and it says this way round.
//
// THE REAL PROBLEM IS NOT THE POLARITY, IT IS THAT THIS IS A BLANKET HALT.
// `SHALTn` below stops the sub for the whole display period whenever this flag
// is set, whether or not the sub is actually touching VRAM. Real hardware only
// makes it wait for the accesses themselves. The cost is about half the sub
// CPU's cycles -- 3820 instructions/frame against the ~8400 that E = 2.016 MHz
// should give -- and it is what still starves Thexder's shared-window byte pump
// (TODO.md P4-1). Fixing it properly means qualifying the wait with an actual
// VRAM access and stretching the sub's clock (MRDY-style) rather than asserting
// HALT, since HALT only takes effect at instruction boundaries.
wire s2 = ~SRESETn;
always @(posedge SVRACSn or posedge s2)
  if (s2) m44_5 <= 1'b1;
  else m44_5 <= SRWBn;

// SVDHALT/m44_5 no longer gate this. That pair was a BLANKET halt: it stopped
// the sub for the whole display period whenever the mode flag was set, whether
// or not the sub was touching VRAM, costing it ~55% of its cycles. The VRAM
// conflict it was protecting against is now handled where it belongs, as a wait
// state on the access itself -- see `sub_vram_wait` in core.v. What is left
// here is the main CPU's explicit halt request, which is what SHALTn is for.
assign SHALTn = SUBHALTREQn;
assign SHALTACn = SUBHALTREQn | SHALTSTn;

// The sub-system BUSY flag, reported on $fd05 bit 7 (see TIMER.v).
//
// This is correct as written, and the polarity is easy to misread, so: SBUSYSETn
// is Y2 of SDECODE's m87, which decodes $d408-$d40f enabled by SQANDEn = ~(Q&E)
// -- NOT qualified by direction, so both reads and writes of $d40a land here.
// And `SRWBn` is `~RnW` (SCPU.v:29), i.e. HIGH on a write. So
//
//   sub CPU reads  $d40a -> SRWBn=0 -> BUSY cleared
//   sub CPU writes $d40a -> SRWBn=1 -> BUSY set
//
// which is exactly MAME (fm7_v.cpp): `sub_busyflag_r()` clears, `sub_busyflag_w()`
// sets. Do not "fix" this by inverting to ~SRWBn -- that was tried and boots
// neither F-BASIC nor a game.
wire s3 = RESETBn & SHALTACn;
always @(negedge SBUSYSETn or negedge s3)
  if (~s3) m44_8 <= 1'b0;
  else m44_8 <= SRWBn;

wire s4 = ~RESETBn;
always @(posedge WFD37n or posedge s4)
  if (s4) m46 <= 8'h0;
  else m46 <= MDATABUS_in;

assign BUSY = m44_8;
assign SUBIRQn = ~m45;
assign VPAGE1n = m46[0]; // CPU access
assign VPAGE2n = m46[1]; // CPU access
assign VPAGE3n = m46[2]; // CPU access
assign DPAGE1  = m46[4]; // Display 0 = enable color layer
assign DPAGE2  = m46[5]; // Display
assign DPAGE3  = m46[6]; // Display

endmodule
