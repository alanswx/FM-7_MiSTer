
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
