
module SMEM(
  input CLKSYS,
  input [15:0] SADDRBUS,
  input [7:0] SDATABUS_in,
  output [7:0] SDATABUS_out,
  input SRAM1CSn,
  input SRAM2CSn,
  input SWTQEn,
  input SRDQEn,
  // Sub-system register write bus: the sub CPU normally, the main CPU's MMR
  // view of physical $1D400-$1D4FF while the sub CPU is halted.
  input [15:0] SREGADDR,
  input  [7:0] SREGDIN,
  input        SREGWEn,
  input SROMSELn,
  input SROMDn,
  input machine_av,
  input [1:0] submon_sel,
  input submon_status,
  input SBLANKn,
  input SVSYNCn,
  input alu_busy,
  input RESETBn,
  output [7:0] av_d430_out,
  output av_display_page,
  output av_active_page,
  output av_vram_bank,
  output av_nmi_mask,
  output av_offset_fine
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

wire av_d430_sel = machine_av && (SREGADDR == 16'hd430);
// $D430 readback is a live status register, not the write latch.  Bit 4 is
// "ALU idle": AVHDRAW's byte read-modify-write finishes inside one sub-CPU
// bus cycle, so only a hardware line draw is ever seen busy here.
assign av_d430_out = {~SBLANKn, 2'b11, ~alu_busy, 1'b1, ~SVSYNCn, 1'b1, submon_status};
assign av_display_page = av_d430_reg[6];
assign av_active_page = av_d430_reg[5];
assign av_vram_bank = av_d430_reg[5];
// Bit 7 masks the sub CPU's 20 ms NMI (1 = masked).  The FM-7 has no such
// register and its NMI is unconditional; core.v gates on machine_av.  Reset
// leaves it 0 = enabled, matching CSP's `nmi_enable = true` and 77AVEMU's
// `state.subNMIMask=false`.
assign av_nmi_mask = av_d430_reg[7];
// $D430 b2 = unmasked VRAM offset. 77AVEMU:
// `if(0!=(data&4)) VRAMOffsetMask=0xffff; else 0xffe0` (fm77avcrtc.cpp:271-282).
// With the bit set the scroll offset's low 5 bits are live -- fine scroll
// rather than 32-byte steps.
assign av_offset_fine = av_d430_reg[2];

// $D430 is a write latch on the sub-system register bus.  SREGADDR/SREGWEn are
// decode outputs rather than a clock, and the address can already be moving to
// the next cycle at a CLKSYS edge.  Filter the active-low write strobe and
// capture on its stable leading edge, matching the scroll-register latches in
// MB60H010.
wire av_d430_wrn = ~(av_d430_sel && ~SREGWEn);
reg [2:0] av_d430_wr_sr;
always @(posedge CLKSYS) begin
  av_d430_wr_sr <= { av_d430_wr_sr[1:0], av_d430_wrn };
  if (~RESETBn) begin
    av_d430_reg <= 8'd0;
    av_d430_wr_sr <= 3'b111;
  end
  else if ((av_d430_sel && ~SREGWEn) ||
           (av_d430_wr_sr[2] & ~av_d430_wr_sr[1])) begin
    av_d430_reg <= SREGDIN;
  end
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
