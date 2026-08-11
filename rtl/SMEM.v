
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
  input [1:0] submon_sel,
  input submon_status,
  input SBLANKn,
  input SVSYNCn,
  input RESETBn,
  output [7:0] av_d430_out,
  output av_display_page,
  output av_active_page,
  output av_vram_bank
);

wire [7:0] m153_q;
wire [7:0] m154_q;
wire [7:0] m141_q;
wire [7:0] m123_q;
wire [7:0] av_sub_a_q;
wire [7:0] av_sub_b_q;
wire [7:0] av_font_q;
reg [7:0] av_d430_reg;
wire [7:0] monitor_q = !machine_av ? m154_q :
                        (submon_sel == 2'd1) ? av_sub_a_q :
                        (submon_sel == 2'd2) ? av_sub_b_q : m154_q;
// Type-C monitor ROM contains its own 2 KB character generator.  D430's
// four-bank character-generator ROM is selected only by monitor A/B; the
// reference hardware model returns the C font while Type C is active.
wire [7:0] av_font_data = (submon_sel == 2'd0) ? m153_q : av_font_q;

wire av_d430_sel = machine_av && (SADDRBUS == 16'hd430);
// $D430 readback is a live status register, not the write latch.  The
// unimplemented ALU is idle, so bit 4 remains set until the ALU exists.
assign av_d430_out = {~SBLANKn, 2'b11, 2'b11, ~SVSYNCn, 1'b1, submon_status};
assign av_display_page = av_d430_reg[6];
assign av_active_page = av_d430_reg[5];
assign av_vram_bank = av_d430_reg[5];

always @(posedge CLKSYS) begin
  if (~RESETBn)
    av_d430_reg <= 8'd0;
  else if (av_d430_sel && ~SWTQEn)
    av_d430_reg <= SDATABUS_in;
end

assign SDATABUS_out =
  ~SRAM1CSn ? m141_q :
  ~SRAM2CSn ? m123_q :
  ~SROMDn   ? (machine_av ? av_font_data : m153_q) :
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

rom #("./roms/fm77av_subsyscg.rom.mem", 13, 8) av_font(
  .clk  ( CLKSYS                         ),
  .addr ( {av_d430_reg[1:0], SADDRBUS[10:0]} ),
  .dout ( av_font_q                      ),
  .ce_n ( SROMDn                         )
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
