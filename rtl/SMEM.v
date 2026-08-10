
module SMEM(
  input CLKSYS,
  input [15:0] SADDRBUS,
  input [7:0] SDATABUS_in,
  output [7:0] SDATABUS_out,
  input SRAM1CSn,
  input SRAM2CSn,
  input SWTQEn,
  input SRDQEn,
  input SROMSELn,
  input SROMDn,
  input machine_av,
  input [1:0] submon_sel
);

wire [7:0] m153_q;
wire [7:0] m154_q;
wire [7:0] m141_q;
wire [7:0] m123_q;
wire [7:0] av_sub_a_q;
wire [7:0] av_sub_b_q;
wire [7:0] monitor_q = !machine_av ? m154_q :
                        (submon_sel == 2'd1) ? av_sub_a_q :
                        (submon_sel == 2'd2) ? av_sub_b_q : m154_q;

assign SDATABUS_out =
  ~SRAM1CSn ? m141_q :
  ~SRAM2CSn ? m123_q :
  ~SROMDn   ? m153_q :
  ~SROMSELn ? monitor_q : 8'h00;

ram #(11,8) m141(
  .clk  ( CLKSYS         ),
  .addr ( SADDRBUS[10:0] ),
  .din  ( SDATABUS_in    ),
  .q    ( m141_q         ),
  .wr_n ( SWTQEn         ),
  .rd_n ( SRDQEn         ),
  .ce_n ( SRAM1CSn       )
);

ram #(11,8) m123(
  .clk  ( CLKSYS         ),
  .addr ( SADDRBUS[10:0] ),
  .din  ( SDATABUS_in    ),
  .q    ( m123_q         ),
  .wr_n ( SWTQEn         ),
  .rd_n ( SRDQEn         ),
  .ce_n ( SRAM2CSn       )
);

rom #("./roms/subsys_m153.rom.mem", 11, 8) m153(
  .clk  ( CLKSYS         ),
  .addr ( SADDRBUS[10:0] ),
  .dout ( m153_q         ),
  .ce_n ( SROMDn         )
);

rom #("./roms/subsys_m154.rom.mem", 13, 8) m154(
  .clk  ( CLKSYS         ),
  .addr ( SADDRBUS[12:0] ),
  .dout ( m154_q         ),
  .ce_n ( SROMSELn       )
);

rom #("./roms/fm77av_subsys_a.rom.mem", 13, 8) av_sub_a(
  .clk  ( CLKSYS          ),
  .addr ( SADDRBUS[12:0]  ),
  .dout ( av_sub_a_q      ),
  .ce_n ( SROMSELn        )
);

rom #("./roms/fm77av_subsys_b.rom.mem", 13, 8) av_sub_b(
  .clk  ( CLKSYS          ),
  .addr ( SADDRBUS[12:0]  ),
  .dout ( av_sub_b_q      ),
  .ce_n ( SROMSELn        )
);


endmodule
