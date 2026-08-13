
module SRAM(
  input CLKSYS,
  input [15:0] SADDRBUS,
  input [15:0] MADDRBUS,
  input [7:0] SDATA_in,
  input [7:0] MDATA_in,
  output [7:0] SRDATA_out,
  input SHALTACn,
  input RDQEn,
  input SRDQEn,
  input WTQEn,
  input SWTQEn,
  input SSMEMn,
  input SUBSELn,
  input AV_SHARED_SEL,
  input [9:0] AV_SHARED_ADDR,
  input AV_SHARED_WRITE,
  input [7:0] AV_SHARED_DIN,
  output [7:0] AV_SHARED_DOUT,
  input AV_SUBRAM_SEL
);

// Two things were tried here while chasing Thexder's corrupt sub-CPU program
// (TODO.md P4-1) and BOTH were dead ends -- recorded so they are not retried:
//
//  * Gating the main-side write with SHALTACn, the way MAME's `main_shared_w()`
//    drops a write unless `sub_halt` is set. No effect on the corruption.
//  * Keying the address/data mux off SUBSELn instead of SHALTACn, on the theory
//    that a main access outside a halt was being misdirected to SADDRBUS. Also
//    no effect -- which is itself informative: it means SHALTACn is already low
//    during those accesses, i.e. the sub really is halted for them, via the
//    SVDHALT path in FLAGS.v rather than via an explicit $fd05 request.
//
// So the shared-RAM aperture is not where Thexder loses its bytes. Left as-is.
// SSMEMn is the sub CPU's own $d000-$d3ff decode and SUBSELn is the main CPU's
// $fcxx decode. They are independent, and each side's write is qualified by its
// own select and its own write strobe -- exactly as the single-port version's
// `wr_n = (SSMEMn | SWTQEn) & (SUBSELn | WTQEn)` did.
//
// Requiring the *other* side's select as well kills the mailbox: the main CPU
// writes this window while the sub is halted, so the sub is not addressing
// $d000-$d3ff at that moment and the write is discarded. F-BASIC then never
// hands the sub a draw command and the FM-7 boots to a blank screen with both
// CPUs running at their normal rates.
wire legacy_main_sel = ~SHALTACn;
wire sub_sel = ~SSMEMn & ~AV_SUBRAM_SEL;
wire [9:0] legacy_main_addr = {2'b11, MADDRBUS[7:0]};
wire sub_write = sub_sel && ~SWTQEn;
wire main_write = (~SUBSELn & ~WTQEn) || AV_SHARED_WRITE;
wire [7:0] main_q;
wire [7:0] sub_q;

`ifdef DEBUG_SRAM
// Is a main-side write into the shared window actually landing where it should?
// The write enable and the address/data mux are gated by different things, so a
// write issued before the sub acknowledges the halt still fires -- at the sub's
// address, with the sub's data.
integer sram_ok = 0, sram_bad = 0;
reg mw_d = 1'b0;
wire mw = ~SUBSELn & ~WTQEn;
always @(posedge CLKSYS) begin
  mw_d <= mw;
  if (mw & ~mw_d) begin
    if (~SHALTACn) sram_ok <= sram_ok + 1;
    else begin
      sram_bad <= sram_bad + 1;
      if (sram_bad < 12)
        $display("SRAMBAD main write $%04x <- $%02x with SHALTACn HIGH (goes to sub addr $%04x)",
                 MADDRBUS, MDATA_in, SADDRBUS);
    end
  end
end
final $display("SRAMSUM accepted=%0d misdirected=%0d", sram_ok, sram_bad);
`endif

// Port A is the sub CPU's $d000-$d3ff view. Port B is shared by the legacy
// halted-main aperture and the AV main-CPU $fc80-$fcff alias.
dpram #(8,10) sram(
  .clock    ( CLKSYS          ),
  .address_a( SADDRBUS[9:0]   ),
  .data_a   ( SDATA_in        ),
  .wren_a   ( sub_write       ),
  .q_a      ( sub_q           ),
  .address_b( AV_SHARED_SEL ? AV_SHARED_ADDR : legacy_main_addr ),
  .data_b   ( AV_SHARED_SEL ? AV_SHARED_DIN : MDATA_in ),
  .wren_b   ( main_write      ),
  .q_b      ( main_q          )
);

assign SRDATA_out = legacy_main_sel ? main_q : sub_q;
assign AV_SHARED_DOUT = main_q;

endmodule
