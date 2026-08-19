
// Page 12 on schematics.

module FLAGS(
  // The BUSY flag below is a real state machine with three inputs (the main's
  // halt request and the sub's read and write of $d40a), so it is clocked
  // rather than built from a stack of asynchronous edges. Everything else in
  // this module is still edge-triggered off its own strobe, as on the
  // schematic.
  input CLKSYS,
  input SEB,
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

// THESE FOUR FLIP-FLOPS WERE CLOCKED BY DECODE STROBES, NOT BY A CLOCK.
//
// m56_5 on `posedge SCRTSWn`, m56_9 on `posedge SLEDn`, m45 on `posedge
// CANCELn`, m44_5 on `posedge SVRACSn` (below). Every one of those is a 74138
// chip-select output, i.e. combinational logic over the address bus. Verilator
// gives them one clean edge per access; Quartus gives ripple clocks on general
// routing, and a LUT-built decode GLITCHES as address bits arrive skewed. Every
// glitch is a spurious clock edge.
//
// It never mattered before because core.v tied SRESETn to 1'b0, which holds all
// four permanently in reset -- the glitchy clocks had nothing to clock. Undoing
// that tie-off (f9548d8) released them, and OS-9 promptly regressed ON REAL
// HARDWARE while remaining perfect in simulation. That asymmetry is the tell:
// sim cannot see a glitch that only exists in routed logic.
//
// Two of the four are live and both are load-bearing:
//   m56_5 -> SVDOFFn -> PAL.v's `m25_3 = ~(SVDOFFn & SBLANKn)`, so a spurious
//            edge here BLANKS OR CORRUPTS THE DISPLAY.
//   m45   -> SUBIRQn, so a spurious edge fires an interrupt at the sub CPU.
// (m56_9/INS is connected in core.v but consumed by nothing, and m44_5 is
// written and never read -- see the note below.)
//
// Now clocked on CLKSYS with the strobes edge-detected, which is what this
// project already does everywhere else it hit this: P3-1 moved the timer IRQ
// flip-flop onto CLKSYS for the same reason, and the BUSY flag further down
// this file is built the same way. The strobes are tens of CLKSYS cycles wide
// (E is 1.2288 MHz against 48 MHz), so an edge cannot be missed, and SRWB is
// stable across the whole bus cycle so sampling it a cycle later is safe.
// The strobes are FILTERED through a 3-bit shift register, not merely
// edge-detected against the previous cycle. A decode glitch is one or two
// CLKSYS cycles wide, so a one-cycle detector still reports it as an edge --
// which is the very thing being fixed. Taking the edge from the filtered copy
// means a transient has to persist to be believed. The sample then lands two
// CLKSYS cycles into the strobe instead of exactly on its edge; E-high is about
// 19 CLKSYS cycles, so that is comfortably inside the access.
//
// This shape came back from the hardware side (see DERIVED_CLOCKS.md). The
// first version of this conversion used a plain one-cycle detector and was
// confirmed working on hardware, but that is luck rather than design: it only
// held because the glitch on these particular decodes happened to be shorter
// than a CLKSYS period.
reg [2:0] scrtsw_sr, sled_sr, cancel_sr;
reg sirqclr_d;
reg sirqclr_ephase;

always @(posedge CLKSYS) begin
  scrtsw_sr <= { scrtsw_sr[1:0], SCRTSWn };
  sled_sr   <= { sled_sr[1:0],   SLEDn   };
  if (~SRESETn) begin
    m56_5 <= 1'b1;
    m56_9 <= 1'b1;
  end
  else begin
    // filtered rising edge, matching the original `posedge SCRTSWn`/`SLEDn`
    if (~scrtsw_sr[2] & scrtsw_sr[1]) m56_5 <= SRWB;  // $d408: read = CRT on
    if (~sled_sr[2]   & sled_sr[1])   m56_9 <= SRWB;
  end
end

// m45 keeps its original semantics exactly: reset or the sub's $d402
// cancel-acknowledge clears it, and CANCELn's rising edge sets it. The
// acknowledge is not level-sensitive, however: one sub-CPU read produces a Q
// pulse followed by an E pulse, and the CPU latches on the E phase. Remember
// which SIRQCLRn pulse is the E-phase one and clear at that pulse's close.
always @(posedge CLKSYS) begin
  cancel_sr <= { cancel_sr[1:0], CANCELn };
  sirqclr_d <= SIRQCLRn;
  if (sirqclr_d & ~SIRQCLRn) sirqclr_ephase <= SEB;
  if (~SRESETn)                          m45 <= 1'b0;
  else if (~sirqclr_d & SIRQCLRn & sirqclr_ephase)
                                           m45 <= 1'b0;
  else if (~cancel_sr[2] & cancel_sr[1])  m45 <= 1'b1;
end

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
// m44_5 is WRITTEN AND NEVER READ -- nothing in this file or any other consumes
// it, because SHALTn stopped using it when P0-7 replaced the blanket VRAM halt
// with a real per-access wait state. It is kept (rather than deleted) because
// the comment above is the record of why the polarity is what it is, and it is
// moved onto CLKSYS with the rest so no derived clock survives in this module.
reg [2:0] svracs_sr;
always @(posedge CLKSYS) begin
  svracs_sr <= { svracs_sr[1:0], SVRACSn };
  if (~SRESETn)                          m44_5 <= 1'b1;
  else if (~svracs_sr[2] & svracs_sr[1]) m44_5 <= SRWBn;
end

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
  // BUSY is SET by reset, not cleared by it, and `reset` here includes the sub
  // CPU reset that a $fd13 write triggers -- SRESETn is RESETBn & ~SUBMON_RESET.
  //
  // 77AVEMU does both: FM77AV::Reset has `state.subSysBusy=true; // Busy on
  // reset` (fm77av.cpp:624) and the $FD13 handler repeats it after resetting
  // the sub CPU (fm77avio.cpp:194-202). CSP does not model the $FD13 reset at
  // all, so 77AVEMU is the only authority here and it is unambiguous. The flag
  // then clears the normal way, when the sub monitor's init reaches its idle
  // loop and reads $d40a.
  //
  // Clearing it here instead is what kept the original Fujitsu FM77AV demo
  // disk blank. Its loader writes $fd13 to select monitor B and then polls
  // $fd05 for the sub to finish restarting; the reference reads $fe (busy) and
  // waits, while this core read $7e (idle) immediately, concluded the restart
  // was already done, halted and released a sub CPU still in reset, and then
  // span on $fd05 at $0783 for the rest of the run.
  if (~SRESETn)                              m44_8 <= 1'b1;
  // The main CPU asking for a halt marks the sub busy.
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
// WFD37n is a decode strobe, not a clock -- the last one left in this module
// after 3f85852 moved the other four. See DERIVED_CLOCKS.md: Quartus routes it
// as a ripple clock and a LUT-built decode glitches as its inputs arrive
// skewed. m46 is the worst remaining place for that, because it drives both
// VPAGE1-3n (which VRAM planes the CPU may touch) and DPAGE1-3 (which planes
// are displayed, feeding PAL.v's clr1/clr2/clr3) -- a spurious write changes
// what the machine can draw on and what it shows, mid-boot.
//
// On CLKSYS with the strobe filtered through a 3-stage shift register, the
// same shape as the MFD, PAL and MB60H010 conversions: a glitch is one or two
// CLKSYS cycles wide, so requiring successive agreeing samples rejects it,
// where edge-detecting the raw strobe would still see a glitch as an edge.
//
// The leading edge is preserved deliberately -- the P1-4 note above is why this
// register samples there rather than on release, and that reasoning is
// unchanged. Only the clock moves.
reg [2:0] wfd37_sr;
always @(posedge CLKSYS) begin
  wfd37_sr <= { wfd37_sr[1:0], WFD37n };
  if (~RESETBn)                          m46 <= 8'h0;
  else if (wfd37_sr[2] & ~wfd37_sr[1])   m46 <= MDATABUS_in;
end

assign BUSY = m44_8;
assign SUBIRQn = ~m45;
assign VPAGE1n = m46[0]; // CPU access
assign VPAGE2n = m46[1]; // CPU access
assign VPAGE3n = m46[2]; // CPU access
assign DPAGE1  = m46[4]; // Display 0 = enable color layer
assign DPAGE2  = m46[5]; // Display
assign DPAGE3  = m46[6]; // Display

endmodule
