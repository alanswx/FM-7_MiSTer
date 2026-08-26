
module PAL(
  input CLKSYS,
  input SVDOFFn,
  input SBLANKn,
  input [7:0] SVDATAB,
  input [7:0] SVDATAB3,
  input [7:0] SVDATAR,
  input [7:0] SVDATAR3,
  input [7:0] SVDATAG,
  input [7:0] SVDATAG3,
  input [7:0] SVDATAB2,
  input [7:0] SVDATAB1,
  input [7:0] SVDATAB0,
  input [7:0] SVDATAR2,
  input [7:0] SVDATAR1,
  input [7:0] SVDATAR0,
  input [7:0] SVDATAG2,
  input [7:0] SVDATAG1,
  input [7:0] SVDATAG0,
  input SFTCLK,
  input machine_av,
  input AV_MODE_320,
  input SFTSTEP,
  input SFTLODn,
  input DPAGE1,
  input DPAGE2,
  input DPAGE3,
  input [7:0] MDATA,
  output reg [7:0] PALDATA,
  input [15:0] MADDRBUS,
  input PLTREGn,
  input AV_PALREGn,
  input RDQEn,
  input WTQEn,
  input RESETBn,
  output reg [2:0] grb,
  output [11:0] ANALOG_CODE,
  output [23:0] ANALOG_RGB
);

wire SFTCLKn = ~SFTCLK;
reg [2:0] rst_idx = 3'd0;

reg [2:0] pal[7:0];
reg [7:0] SFT1;
reg [7:0] SFT2;
reg [7:0] SFT3;
reg [7:0] B3SHIFT, B2SHIFT, B1SHIFT, B0SHIFT;
reg [7:0] R3SHIFT, R2SHIFT, R1SHIFT, R0SHIFT;
reg [7:0] G3SHIFT, G2SHIFT, G1SHIFT, G0SHIFT;
reg [11:0] analog_reset_idx = 12'd0;
reg [11:0] analog_index = 12'd0;
reg [11:0] analog_code_reg = 12'd0;

wire m25_3 = ~(SVDOFFn & SBLANKn);

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    pal[rst_idx] <= rst_idx;
    rst_idx <= rst_idx + 3'b1;
    analog_reset_idx <= analog_reset_idx + 12'd1;
  end
  if (~PLTREGn && ~SFTCLKn && (~machine_av || MADDRBUS[3])) begin
    pal[MADDRBUS[2:0]] <= MDATA[2:0];
  end

  // FM77AV's analog palette shares the $FD30-$FD3F block with the FM-7 digital
  // palette.  The low half is the 12-bit indexed palette; the high half remains
  // the eight-entry digital palette at $FD38-$FD3F.  Only the index registers
  // are kept here -- the entries themselves live in the three PAL_RAM blocks
  // below.
  //
  // AV_PALREGn, not PLTREGn: PLTREGn is the $fd38-$fd3f half only, so the
  // `~PLTREGn && ~MADDRBUS[3]` this used to ask for could never be true and the
  // whole register file was dead.  core.v carries the measurement.
  if (~AV_PALREGn && ~WTQEn) begin
    case (MADDRBUS[2:0])
      3'd0: analog_index[11:8] <= MDATA[3:0];
      3'd1: analog_index[7:0]  <= MDATA;
      default: ;
    endcase
  end
end

// ---------------------------------------------------------------------------
// Analog palette storage
//
// This was `reg [11:0] analog[0:4095]` read combinationally. That cost 21,025
// combinational ALUTs and 49,334 registers -- 40% of the design's logic and
// 65% of its registers -- and no block RAM at all, because an asynchronous
// read blocks RAM inference and Quartus builds 49,152 flops plus a 4096:1
// multiplexer instead. The design then missed the DE10-Nano by 140% on ALMs.
// Two changes make it a real M10K:
//
//   * One memory per gun. Each $FD32/$FD33/$FD34 write is then a full 4-bit
//     write; the old per-nibble writes into a shared 12-bit word were a
//     second inference blocker.
//   * A registered read, addressed by the *combinational* next code rather
//     than by analog_code_reg. The output register updates on the same SFTCLK
//     edge that analog_code_reg latches that code, so the pixel path keeps
//     exactly the latency it had -- this is not a pipeline stage.
// ---------------------------------------------------------------------------
wire        analog_rst   = ~RESETBn;
wire        analog_wr    = ~AV_PALREGn && ~WTQEn;
wire [11:0] analog_waddr = analog_rst ? analog_reset_idx : analog_index;
wire        analog_we_b  = analog_rst | (analog_wr && (MADDRBUS[2:0] == 3'd2));
wire        analog_we_r  = analog_rst | (analog_wr && (MADDRBUS[2:0] == 3'd3));
wire        analog_we_g  = analog_rst | (analog_wr && (MADDRBUS[2:0] == 3'd4));
// Reset fills the identity ramp entry[i] = i, i.e. B = i[3:0], R = i[7:4],
// G = i[11:8] -- CSP's power-on palette (display.cpp:226-228), not black.
wire  [3:0] analog_wd_b  = analog_rst ? analog_reset_idx[3:0]   : MDATA[3:0];
wire  [3:0] analog_wd_r  = analog_rst ? analog_reset_idx[7:4]   : MDATA[3:0];
wire  [3:0] analog_wd_g  = analog_rst ? analog_reset_idx[11:8]  : MDATA[3:0];

function [7:0] expand4;
  input [3:0] nibble;
  begin
    // CSP's DAC model keeps black at zero and gives every non-zero 4-bit
    // level a full-scale low nibble: 1 -> 1f, ... f -> ff.
    expand4 = (nibble == 4'd0) ? 8'h00 : {nibble, 4'hf};
  end
endfunction

// The code the SFTCLK block is about to latch into analog_code_reg. Addressing
// the RAM with this rather than with analog_code_reg is what keeps the
// registered read latency-neutral; the read enable mirrors that block's own
// enable exactly, so the entry never advances when the code does not.
wire [11:0] analog_code_next = {
  G3SHIFT[7], G2SHIFT[7], G1SHIFT[7], G0SHIFT[7],
  R3SHIFT[7], R2SHIFT[7], R1SHIFT[7], R0SHIFT[7],
  B3SHIFT[7], B2SHIFT[7], B1SHIFT[7], B0SHIFT[7]
};
wire        analog_rd_en = analog_rst | (AV_MODE_320 & SFTSTEP);
wire [11:0] analog_raddr = analog_rst ? 12'd0 : analog_code_next;
wire  [3:0] analog_q_b, analog_q_r, analog_q_g;

PAL_RAM pal_blue(
  .WCLK(CLKSYS), .WADDR(analog_waddr), .WDATA(analog_wd_b), .WE(analog_we_b),
  .RCLK(SFTCLK),  .RADDR(analog_raddr), .RE(analog_rd_en),   .Q(analog_q_b)
);
PAL_RAM pal_red(
  .WCLK(CLKSYS), .WADDR(analog_waddr), .WDATA(analog_wd_r), .WE(analog_we_r),
  .RCLK(SFTCLK),  .RADDR(analog_raddr), .RE(analog_rd_en),   .Q(analog_q_r)
);
PAL_RAM pal_green(
  .WCLK(CLKSYS), .WADDR(analog_waddr), .WDATA(analog_wd_g), .WE(analog_we_g),
  .RCLK(SFTCLK),  .RADDR(analog_raddr), .RE(analog_rd_en),   .Q(analog_q_g)
);

assign ANALOG_CODE = analog_code_reg;
assign ANALOG_RGB = { expand4(analog_q_r),
                      expand4(analog_q_g),
                      expand4(analog_q_b) };

// RDQEn is a decode strobe, not a clock -- see DERIVED_CLOCKS.md. A LUT-built
// decode glitches as its inputs arrive skewed, so this read-back register could
// latch the palette entry at an address that was never on the bus.
//
// On CLKSYS with the strobe filtered through a shift register, so a one or two
// cycle glitch cannot be mistaken for a read. The capture lands two CLKSYS
// cycles into the strobe instead of exactly on its falling edge, which is still
// early in the access -- E is 1.2288 MHz against 48 MHz -- so PALDATA is ready
// long before the CPU latches the bus.
//
// The `posedge SFTCLK` block below is left alone deliberately: SFTCLK is the
// video shift clock, a real clock, not an address decode.
reg [2:0] rdqe_sr;
always @(posedge CLKSYS) begin
  rdqe_sr <= { rdqe_sr[1:0], RDQEn };
  if (rdqe_sr[2] & ~rdqe_sr[1] & ~PLTREGn)   // filtered leading edge of the read
    // $F8, not zero, in the five unused bits. Both references build the byte
    // that way -- 77AVEMU returns `0xF8|digitalPalette[n]`
    // (fm77av/fm77avio.cpp:933) and CSP stores `val|0xf8` at set_dpalette and
    // hands that back on read (fm7/display.cpp:479, :2701). Same shape as
    // $D432 and $FD93: an FM-7 register's undriven bits float high.
    PALDATA <= {5'b11111, pal[MADDRBUS[2:0]]};
end

wire clr1 = DPAGE1|m25_3;
wire clr2 = DPAGE2|m25_3;
wire clr3 = DPAGE3|m25_3;

reg qh1;
reg qh2;
reg qh3;

wire [2:0] color = { qh3, qh2, qh1 };

always @(posedge SFTCLK) begin
//$display("pal[color] %x",pal[color]);
  if (~RESETBn) begin
    analog_code_reg <= 12'd0;
  end
  else if (~AV_MODE_320 | SFTSTEP) begin
    grb <= pal[color];
    qh1 <= SFT1[7];
    qh2 <= SFT2[7];
    qh3 <= SFT3[7];
    if (AV_MODE_320)
      analog_code_reg <= {
        G3SHIFT[7], G2SHIFT[7], G1SHIFT[7], G0SHIFT[7],
        R3SHIFT[7], R2SHIFT[7], R1SHIFT[7], R0SHIFT[7],
        B3SHIFT[7], B2SHIFT[7], B1SHIFT[7], B0SHIFT[7]
      };
  end
end

wire sftlod = ~SFTLODn;

always @(posedge SFTCLK, posedge sftlod, posedge clr1) begin
  if (clr1) SFT1 <= 8'd0;
  else if (sftlod) SFT1 <= SVDATAB;
  else if (~AV_MODE_320 | SFTSTEP) SFT1 <= { SFT1[6:0], 1'b0 };
end

always @(posedge SFTCLK, posedge sftlod, posedge clr2) begin
  if (clr2) SFT2 <= 8'd0;
  else if (sftlod) SFT2 <= SVDATAR;
  else if (~AV_MODE_320 | SFTSTEP) SFT2 <= { SFT2[6:0], 1'b0 };
end

always @(posedge SFTCLK, posedge sftlod, posedge clr3) begin
  if (clr3) SFT3 <= 8'd0;
  else if (sftlod) SFT3 <= SVDATAG;
  else if (~AV_MODE_320 | SFTSTEP) SFT3 <= { SFT3[6:0], 1'b0 };
end

always @(posedge SFTCLK, posedge sftlod, posedge clr1) begin
  if (clr1) begin
    B3SHIFT <= 8'd0; B2SHIFT <= 8'd0; B1SHIFT <= 8'd0; B0SHIFT <= 8'd0;
  end
  else if (sftlod) begin
    B3SHIFT <= AV_MODE_320 ? SVDATAB3 : SVDATAB;  B2SHIFT <= SVDATAB2;
    B1SHIFT <= SVDATAB1; B0SHIFT <= SVDATAB0;
  end
  else if (AV_MODE_320 && SFTSTEP) begin
    B3SHIFT <= {B3SHIFT[6:0], 1'b0}; B2SHIFT <= {B2SHIFT[6:0], 1'b0};
    B1SHIFT <= {B1SHIFT[6:0], 1'b0}; B0SHIFT <= {B0SHIFT[6:0], 1'b0};
  end
end

always @(posedge SFTCLK, posedge sftlod, posedge clr2) begin
  if (clr2) begin
    R3SHIFT <= 8'd0; R2SHIFT <= 8'd0; R1SHIFT <= 8'd0; R0SHIFT <= 8'd0;
  end
  else if (sftlod) begin
    R3SHIFT <= AV_MODE_320 ? SVDATAR3 : SVDATAR;  R2SHIFT <= SVDATAR2;
    R1SHIFT <= SVDATAR1; R0SHIFT <= SVDATAR0;
  end
  else if (AV_MODE_320 && SFTSTEP) begin
    R3SHIFT <= {R3SHIFT[6:0], 1'b0}; R2SHIFT <= {R2SHIFT[6:0], 1'b0};
    R1SHIFT <= {R1SHIFT[6:0], 1'b0}; R0SHIFT <= {R0SHIFT[6:0], 1'b0};
  end
end

always @(posedge SFTCLK, posedge sftlod, posedge clr3) begin
  if (clr3) begin
    G3SHIFT <= 8'd0; G2SHIFT <= 8'd0; G1SHIFT <= 8'd0; G0SHIFT <= 8'd0;
  end
  else if (sftlod) begin
    G3SHIFT <= AV_MODE_320 ? SVDATAG3 : SVDATAG;  G2SHIFT <= SVDATAG2;
    G1SHIFT <= SVDATAG1; G0SHIFT <= SVDATAG0;
  end
  else if (AV_MODE_320 && SFTSTEP) begin
    G3SHIFT <= {G3SHIFT[6:0], 1'b0}; G2SHIFT <= {G2SHIFT[6:0], 1'b0};
    G1SHIFT <= {G1SHIFT[6:0], 1'b0}; G0SHIFT <= {G0SHIFT[6:0], 1'b0};
  end
end


endmodule

// One gun of the FM77AV analog palette: 4096 x 4 bits, written by the main CPU
// on CLKSYS and read by the raster on SFTCLK. Two always blocks on two clocks
// is the template Quartus infers a true dual-port M10K from; read-during-write
// to the same entry is a don't-care here, it is one pixel of one frame.
module PAL_RAM(
  input            WCLK,
  input     [11:0] WADDR,
  input      [3:0] WDATA,
  input            WE,
  input            RCLK,
  input     [11:0] RADDR,
  input            RE,
  output reg [3:0] Q
);

reg [3:0] mem [0:4095];

always @(posedge WCLK) if (WE) mem[WADDR] <= WDATA;
always @(posedge RCLK) if (RE) Q <= mem[RADDR];

endmodule
