
// Page 12 on schematics.

module FLAGS(
  // The BUSY flag below is a real state machine with three inputs (the main's
  // halt request and the sub's read and write of $d40a), so it is clocked
  // rather than built from a stack of asynchronous edges. Everything else in
  // this module is still edge-triggered off its own strobe, as on the
  // schematic.
  input CLKSYS,
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
// The $d40a half of this is correct as written, and the polarity is easy to
// misread, so: SBUSYSETn is Y2 of SDECODE's m87, which decodes $d408-$d40f
// enabled by SQANDEn = ~(Q&E) -- NOT qualified by direction, so both reads and
// writes of $d40a land here. And `SRWBn` is `~RnW` (SCPU.v:29), i.e. HIGH on a
// write. So
//
//   sub CPU reads  $d40a -> SRWBn=0 -> BUSY cleared  ("I am back in the idle loop")
//   sub CPU writes $d40a -> SRWBn=1 -> BUSY set      ("I have started a command")
//
// which is exactly MAME (fm7_v.cpp): `sub_busyflag_r()` clears,
// `sub_busyflag_w()` sets. Do not "fix" this by inverting to ~SRWBn -- that was
// tried and boots neither F-BASIC nor a game.
//
// WHAT WAS WRONG: the main CPU's halt request must SET this flag, and here it
// asynchronously CLEARED it. The old async clear was
//
//     wire s3 = RESETBn & SHALTACn;   // held m44_8 at 0 for the whole halt
//
// Both references set busy on the halt request instead, and neither clears it
// on release:
//
//   MAME  subintf_w: `m_video.sub_halt = data & 0x80;
//                     if(data & 0x80) m_video.sub_busy = data & 0x80;`
//         and sub_busyflag_r only clears `if(m_video.sub_halt == 0)`.
//   CSP   display.cpp:1879 `case SIG_FM7_SUB_HALT: if(flag) { sub_busy = true; }`
//         with reset_subbusy()/set_subbusy() on the $d40a read/write.
//
// That difference is the whole completion handshake. The intended sequence is
//
//   main: poll $fd05 bit 7 until CLEAR      -- sub is idle
//   main: $fd05 <- $80                      -- halt requested, AND BUSY SET
//   main: write the command block to $fc80+
//   main: $fd05 <- $00                      -- halt released; BUSY STAYS SET
//   sub:  wakes, consumes the command, draws
//   sub:  returns to its ROM idle loop and reads $d40a -> BUSY clears
//   main: sees bit 7 clear and may send the next command
//
// With BUSY force-cleared during the halt, the moment the main released the
// halt bit 7 read 0 -- "sub idle" -- even though the sub had not yet run a
// single instruction of the command. A main CPU that loops "wait for idle,
// halt, write, release" therefore overwrote command blocks the sub had not
// consumed yet. It is a race, so it costs SOME commands and not others, which
// is exactly Hydlide II dropping whole glyphs out of its story text (P4-13)
// while The Castle, which draws text a different way, loses almost none.
//
// TIMER.v's `BUSY | ~SHALTACn` for bit 7 stays: it is redundant now that the
// request sets BUSY, but MAME ORs sub_halt in the same way (`if(sub_busy != 0
// || sub_halt != 0)`), so it is correct and costs nothing.
reg sbusyset_d, subhaltreq_d;
always @(posedge CLKSYS) begin
  sbusyset_d   <= SBUSYSETn;
  subhaltreq_d <= SUBHALTREQn;
  if (~RESETBn)                              m44_8 <= 1'b0;
  // The main CPU asking for a halt marks the sub busy. THIS is the fix.
  else if (subhaltreq_d & ~SUBHALTREQn)      m44_8 <= 1'b1;
  else if (sbusyset_d & ~SBUSYSETn) begin
    if (SRWBn)                               m44_8 <= 1'b1;  // sub wrote $d40a
    else if (SUBHALTREQn)                    m44_8 <= 1'b0;  // sub read $d40a,
                                                             // and only while not
                                                             // halted, per MAME
  end
end

// $fd37, the multi-page register: bits 0-2 mask CPU access to the three VRAM
// planes, bits 4-6 mask their display. Both MAME (`data & 0x77`) and CSP
// (`accessmask = val & 0x07; dispmask = (val & 0x70) >> 4`) agree on that split.
//
// This was clocked on `posedge WFD37n` -- the TRAILING edge of the write strobe.
// A 74LS374 on the schematic latches there and the 6809's data-hold window
// covers it, but in zero-delay RTL the CPU has already released the bus, so the
// register captured whatever the bus had decayed to and $fd37 read back $00
// forever. Games that select which planes are displayed had the selection
// silently ignored; Thexder writes $30 here and got all three planes drawn.
//
// And it could not have worked regardless, because nothing decoded a write to
// $fd37 at all until MDECODE.v was fixed -- see the WFD37n comment there. With a
// real write strobe, latch on its leading edge where the data is valid. Same
// family as P0-1/P0-3.
wire s4 = ~RESETBn;
always @(negedge WFD37n or posedge s4)
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
