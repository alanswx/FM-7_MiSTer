
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
  input SUBSELn
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
wire [9:0] SAB = ~SHALTACn ? {2'b11, MADDRBUS[7:0] } : SADDRBUS[9:0];
wire [7:0] SDB = ~(SUBSELn | SHALTACn) ? MDATA_in : SDATA_in;

wire ce_n = SUBSELn & SSMEMn;
wire wr_n = (SSMEMn | SWTQEn) & (SUBSELn | WTQEn);
wire rd_n = RDQEn & SRDQEn;

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

ram #(10,8) sram(
  .clk  ( CLKSYS     ),
  .addr ( SAB        ),
  .din  ( SDB        ),
  .q    ( SRDATA_out ),
  .wr_n ( wr_n       ),
  .rd_n ( rd_n       ),
  .ce_n ( ce_n       )
);

endmodule
