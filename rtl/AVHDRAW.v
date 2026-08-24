// FM77AV MB61VH010 drawing ALU -- sub-CPU registers $D410-$D42B.
//
// Two triggers drive one read-modify-write engine:
//
//   * While $D410 b7 is set, *any* sub-CPU VRAM access -- read or write -- is
//     intercepted.  The CPU's data byte is discarded and the ALU instead
//     read-modify-writes the addressed byte on all three colour planes at
//     once.  Reads trigger as well as writes: the 2019 FM77AV demo dummy-reads
//     and Pro Baseball Fan dummy-writes (77AVEMU `fm77avmemory.cpp:820-827`
//     into `fm77avcrtc.cpp:331-446`; CSP `display.cpp:3174-3181`).
//   * Writing $D42B starts a Bresenham line that walks the same engine one
//     pixel at a time (77AVEMU `fm77avcrtc.cpp:659-846`).
//
// The engine needs all three planes at one address in the same cycle.  The
// raster/sub-CPU port cannot supply that -- it is time-multiplexed with the
// display and carries one plane per access -- so the engine borrows CRTRAM's
// main-CPU aperture port, which addresses all three planes in parallel.
//
// The ALU operates on a whole byte, i.e. eight pixels, not on one pixel: the
// $D412 write mask picks which of the eight take the new value.  That is the
// half the 2019 demo actually uses; it never writes $D424-$D42B at all.

module AVHDRAW(
  input         CLKSYS,
  input         RESETBn,
  input         MACHINE_AV,      // the register block does not exist on the FM-7
  input  [15:0] SADDRBUS,
  input   [7:0] SDATA,
  input         SWTQEn,          // sub-CPU write strobe, active low
  input         SEB,             // sub-CPU E
  input         SCASSEL,         // VRAM address bus belongs to the sub CPU
  input         SUB_VRAM_SEL,    // sub CPU is addressing one of the three planes
  input  [13:0] SVRADRS,         // translated sub-CPU VRAM address
  // The main CPU's MMR aperture into the same VRAM. A title that halts the sub
  // CPU and drives this chip from the main side reaches the planes only here.
  input         AV_VRAM_WRITE,
  input         AV_VRAM_READ,   // main-CPU aperture write, held for the cycle
  input  [13:0] AV_VRAM_ADDR,    // translated aperture address
  input         AV_VRAM_BANK,
  input         AV_MODE_320,
  input         AV_ACTIVE_PAGE,
  input  [13:0] AV_VRAM_OFFSET,  // active-page scroll offset
  input   [2:0] VPAGE_MASK,      // $FD37 b2:0, 1 = plane masked
  input   [7:0] DRAW_Q_B,
  input   [7:0] DRAW_Q_R,
  input   [7:0] DRAW_Q_G,
  output        DRAW_PORT_EN,
  output  [1:0] DRAW_BLOCK,
  output [12:0] DRAW_ADDR,
  output        DRAW_WRITE_B,
  output        DRAW_WRITE_R,
  output        DRAW_WRITE_G,
  output  [7:0] DRAW_DIN_B,
  output  [7:0] DRAW_DIN_R,
  output  [7:0] DRAW_DIN_G,
  output        DRAW_INHIBIT,    // the plain VRAM store is discarded, either CPU
  output        DRAW_BUSY,
  output  [7:0] DRAW_DOUT         // $D410-$D41B readback
);

localparam CMD_PSET = 3'd0;
localparam CMD_NOT1 = 3'd1;   // 77AVEMU: the FM77AV demo uses 1 as a second NOT
localparam CMD_OR   = 3'd2;
localparam CMD_AND  = 3'd3;
localparam CMD_XOR  = 3'd4;
localparam CMD_NOT  = 3'd5;
localparam CMD_TILE = 3'd6;
localparam CMD_CMP  = 3'd7;

localparam ST_IDLE  = 2'd0;
localparam ST_READ  = 2'd1;   // address presented, dpram output still stale
localparam ST_WRITE = 2'd2;   // DRAW_Q_* valid: combine and write back

localparam LN_NONE  = 3'd0;
localparam LN_DOT   = 3'd1;
localparam LN_VERT  = 3'd2;
localparam LN_HORZ  = 3'd3;
localparam LN_LONGX = 3'd4;
localparam LN_LONGY = 3'd5;

// ---------------------------------------------------------------------------
// Registers
// ---------------------------------------------------------------------------
reg        enabled;
reg  [1:0] condition;      // b1 = compare enable, b0 = invert the sense
reg  [2:0] command;
reg  [2:0] color;
reg  [7:0] mask_bits;      // 1 = preserve that pixel
reg  [7:0] compare_color [0:7];
reg  [7:0] compare_result;
reg  [2:0] bank_mask;      // 1 = plane disabled
reg  [7:0] tile_b, tile_r, tile_g;
reg [13:0] addr_offset;
reg [15:0] stipple;
reg  [7:0] x0_hi, x1_hi, y0_hi, y1_hi;
reg [15:0] x0, y0, x1, y1;

// Line walker.
reg  [2:0] line_mode;
reg        line_active;
reg [15:0] lx, ly;
reg        vx_neg, vy_neg;
reg [16:0] ldx, ldy, balance;
reg  [3:0] stip_idx;

reg  [1:0] state;
reg  [1:0] acc_block;
reg [12:0] acc_offset;

integer i;

// ---------------------------------------------------------------------------
// Register decode
//
// SADDRBUS/SWTQEn are decode outputs, not a clock.  Filter the active-low
// strobe and capture on its stable leading edge, the same shape as the
// MB60H010 scroll latches and the $D430 latch in SMEM -- a one or two CLKSYS
// cycle decode glitch is then rejected instead of being seen as an edge.  The
// two-cycle delay is ~42 ns against a sub-CPU E period of ~250 ns, so
// SADDRBUS and SDATA are still the ones belonging to this access.
// ---------------------------------------------------------------------------
wire reg_sel = MACHINE_AV &&
               ((SADDRBUS[15:4] == 12'hd41) || (SADDRBUS[15:4] == 12'hd42));
wire reg_wrn = ~(reg_sel && ~SWTQEn);
reg  [2:0] reg_wr_sr;
wire reg_write = reg_wr_sr[2] & ~reg_wr_sr[1];

// ---------------------------------------------------------------------------
// Trigger for the intercepted VRAM access
//
// Qualifying with E separates back-to-back VRAM bus cycles, which SUB_VRAM_SEL
// alone does not: a `STA ,X+` run keeps the address decode asserted across
// cycles.  The 6809 has its address valid before E rises, so the address
// sampled here is the one belonging to this access.
//
// SCASSEL is deliberately NOT in this qualifier, and must not be put back.
// It used to be, on the grounds that core.v stalls the sub clock until the
// VRAM address bus comes back and only then is SVRADRS the sub's own address.
// That premise still holds, but it is now enforced by the stall rather than by
// this term: SCASSEL hands the sub every cycle the raster is not fetching, so
// it TOGGLES SEVERAL TIMES INSIDE ONE SUB BUS CYCLE, and with it in the
// qualifier alu_access fell and rose again each time -- firing the ALU two or
// three times for a single VRAM access, and a read-modify-write op run two or
// three times on the same byte does not give the same answer once.
//
// Honesty about the evidence: this is reasoning about the trigger, NOT a
// measured regression. Wizardry IV renders byte-identically with and without
// the SCASSEL change (12522-byte PNG at frame 700 either way), so nothing in
// the current gate set actually caught the extra edges -- most likely those
// titles never enable the ALU from the sub side. It is removed because the
// term is wrong once SCASSEL toggles inside a bus cycle, not because a title
// was seen to break. A title that drives the ALU from the SUB CPU (rather
// than through the aperture, which uses main_access below) would be the test.
//
// Without it the edge is still one per access. sub_vram_wait freezes the sub's
// clock whenever it is addressing VRAM with SCASSEL low, so SEB can only RISE
// while SCASSEL is high -- the address captured on the edge is the sub's. If
// SCASSEL then drops mid-cycle, SEB is frozen high and alu_access simply stays
// asserted, which is the whole point.
// ---------------------------------------------------------------------------
`ifdef DEBUG_AVDRAW
reg av_vram_write_d;
always @(posedge CLKSYS) begin
  av_vram_write_d <= AV_VRAM_WRITE;
  if (AV_VRAM_WRITE & ~av_vram_write_d)
    $display("AVDRAW V addr=$%04x bank=%0d enabled=%0d", AV_VRAM_ADDR, AV_VRAM_BANK, enabled);
end
`endif
wire alu_access = enabled & SUB_VRAM_SEL & SEB;
reg  alu_access_d;
wire alu_access_edge = alu_access & ~alu_access_d;

// The same interception, for the main CPU reaching VRAM through the MMR
// aperture. 77AVEMU keys hardware drawing on the ADDRESS, not on which CPU is
// accessing (`fm77avmemory.cpp:818-828`): the MEMTYPE_SUBSYS_VRAM store does the
// dummy read and returns whenever hardDraw is enabled, and the halt check just
// above it lets the main CPU through precisely because the sub is halted.
//
// This was missing, and it cost Argo its sprite transparency. It halts the sub
// CPU and programs this chip entirely from the main side -- over 400 frames,
// 2839 writes to $D410, 1468 to $D411 and 53023 to $D412, every one with the sub
// halted -- and then blits through the aperture. With no trigger here the ALU
// performed ZERO operations for the whole run and all 58656 aperture writes
// landed as plain opaque stores, so every sprite painted its bounding box
// instead of its masked shape.
//
// AV_VRAM_WRITE is `av_write && vram_sel`, a level held for the main CPU's write
// cycle, and AV_VRAM_READ the matching strobe for a read, so the edge gives one
// trigger per access either way -- the same shape as the sub path above.
//
// BOTH forms are needed. 77AVEMU calls the dummy READ the supposed form and the
// write a Pro Baseball Fan quirk (fm77avmemory.cpp:818-828), and the read is by
// far the more common: Woody Poco makes 53311 aperture reads and zero aperture
// writes. The read was left out here on the grounds that no title in hand
// needed it, which was only true because the titles that need it were blank and
// unexplained.
wire main_access = enabled & (AV_VRAM_WRITE | AV_VRAM_READ);
reg  main_access_d;
wire main_access_edge = main_access & ~main_access_d;

// ---------------------------------------------------------------------------
// Address of the byte being combined
// ---------------------------------------------------------------------------
wire [13:0] line_base = AV_MODE_320 ? (ly[8:0] * 14'd40) : (ly[8:0] * 14'd80);
wire [13:0] line_col  = {5'd0, lx[11:3]};
wire [13:0] line_sum  = addr_offset + AV_VRAM_OFFSET + line_base + line_col;
// In 320 mode each gun is two 8 KB planes and $D420 b4 (address bit 13) picks
// the half, so the running address wraps inside 13 bits instead of carrying
// into the plane select -- 77AVEMU's `GetPlaneVRAMMask()` is $1FFF in 320 mode
// and $3FFF in 640.
wire [12:0] line_sum13 = addr_offset[12:0] + AV_VRAM_OFFSET[12:0] +
                         line_base[12:0] + line_col[12:0];
wire  [1:0] line_block = {AV_ACTIVE_PAGE,
                          AV_MODE_320 ? addr_offset[13] : line_sum[13]};
wire [12:0] line_offset = AV_MODE_320 ? line_sum13 : line_sum[12:0];

assign DRAW_BLOCK = line_active ? line_block  : acc_block;
assign DRAW_ADDR  = line_active ? line_offset : acc_offset;

// ---------------------------------------------------------------------------
// Per-pixel compare against the eight colour slots
//
// The slots are compared as full bytes: $D413-$D41A store `data & $87`, so a
// slot written with b7 set can never match a three-bit source colour.  That
// is how a slot is disabled (77AVEMU `fm77avcrtc.cpp:485-520`).
// ---------------------------------------------------------------------------
wire [7:0] cmp_pass_bits;
genvar b;
generate
  for (b = 0; b < 8; b = b + 1) begin : cmp
    wire [7:0] src_color = {5'd0, DRAW_Q_G[7-b], DRAW_Q_R[7-b], DRAW_Q_B[7-b]} |
                           {5'd0, VPAGE_MASK};
    wire match = (src_color == compare_color[0]) |
                 (src_color == compare_color[1]) |
                 (src_color == compare_color[2]) |
                 (src_color == compare_color[3]) |
                 (src_color == compare_color[4]) |
                 (src_color == compare_color[5]) |
                 (src_color == compare_color[6]) |
                 (src_color == compare_color[7]);
    assign cmp_pass_bits[7-b] = condition[0] ? ~match : match;
  end
endgenerate

wire cmp_active = condition[1] | (command == CMD_CMP);
wire [7:0] pass_bits = cmp_active ? cmp_pass_bits : 8'hff;

// The write mask gates the intercepted-access path only.  PutDot -- the line
// path -- ignores $D412 and writes the one pixel it is on, gated by the
// rotating stipple pattern.
wire [7:0] pixel_bit = 8'h80 >> lx[2:0];
wire [7:0] access_write_bits = ~mask_bits & pass_bits;
wire [7:0] line_write_bits   = (stipple[stip_idx] ? pixel_bit : 8'h00) & pass_bits;
wire [7:0] write_bits = line_active ? line_write_bits : access_write_bits;

function [7:0] combine;
  input [7:0] old_byte;
  input       plane_color;
  input [7:0] tile_byte;
  input [7:0] wb;
  reg   [7:0] rgb;
  begin
    rgb = plane_color ? 8'hff : 8'h00;
    case (command)
      CMD_PSET: combine = (old_byte & ~wb) | (rgb & wb);
      CMD_NOT1,
      CMD_NOT:  combine = old_byte & ~(rgb & wb);
      CMD_OR:   combine = old_byte | (rgb & wb);
      CMD_AND:  combine = (old_byte & ~wb) | (old_byte & rgb & wb);
      CMD_XOR:  combine = old_byte ^ (rgb & wb);
      CMD_TILE: combine = (old_byte & ~wb) | (tile_byte & wb);
      default:  combine = old_byte;   // CMD_CMP writes nothing
    endcase
  end
endfunction

wire [2:0] plane_mask = bank_mask | VPAGE_MASK;
wire write_phase = (state == ST_WRITE) && (command != CMD_CMP);

assign DRAW_PORT_EN = (state != ST_IDLE);
assign DRAW_WRITE_B = write_phase && ~plane_mask[0];
assign DRAW_WRITE_R = write_phase && ~plane_mask[1];
assign DRAW_WRITE_G = write_phase && ~plane_mask[2];
assign DRAW_DIN_B = combine(DRAW_Q_B, color[0], tile_b, write_bits);
assign DRAW_DIN_R = combine(DRAW_Q_R, color[1], tile_r, write_bits);
assign DRAW_DIN_G = combine(DRAW_Q_G, color[2], tile_g, write_bits);

assign DRAW_INHIBIT = MACHINE_AV & enabled;
assign DRAW_BUSY = line_active;

assign DRAW_DOUT =
  (SADDRBUS[3:0] == 4'h0) ? {enabled, condition, 2'b11, command} :
  (SADDRBUS[3:0] == 4'h1) ? {5'b11111, color} :
  (SADDRBUS[3:0] == 4'h2) ? mask_bits :
  (SADDRBUS[3:0] == 4'h3) ? compare_result :
  (SADDRBUS[3:0] == 4'hb) ? {5'b11111, bank_mask} : 8'hff;

// ---------------------------------------------------------------------------
// Line setup, evaluated combinationally off the $D42B write data
// ---------------------------------------------------------------------------
wire [15:0] start_y1 = {y1_hi, SDATA};
wire        start_vx_neg = (x1 < x0);
wire        start_vy_neg = (start_y1 < y0);
wire [15:0] start_dx = start_vx_neg ? (x0 - x1) : (x1 - x0);
wire [15:0] start_dy = start_vy_neg ? (y0 - start_y1) : (start_y1 - y0);
wire        start_long_y = ~(start_dy < start_dx);
wire  [2:0] start_mode = (start_dx == 16'd0 && start_dy == 16'd0) ? LN_DOT :
                         (start_dx == 16'd0)                     ? LN_VERT :
                         (start_dy == 16'd0)                     ? LN_HORZ :
                         start_long_y ? LN_LONGY : LN_LONGX;

// ---------------------------------------------------------------------------
// Line stepping for the pixel after the one just written
// ---------------------------------------------------------------------------
wire [15:0] lx_step = vx_neg ? (lx - 16'd1) : (lx + 16'd1);
wire [15:0] ly_step = vy_neg ? (ly - 16'd1) : (ly + 16'd1);
wire [16:0] bal_x   = balance + ldy;      // LONGX accumulates dy per x step
wire [16:0] bal_y   = balance + ldx;      // LONGY accumulates dx per y step
wire        cross_x = (ldx <= bal_x);
wire        cross_y = (ldy <= bal_y);
wire        line_more =
  (line_mode == LN_VERT)  ? (ly != y1) :
  (line_mode == LN_HORZ)  ? (lx != x1) :
  (line_mode == LN_LONGX ||
   line_mode == LN_LONGY) ? ((lx != x1) || (ly != y1)) : 1'b0;

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    reg_wr_sr <= 3'b111;
    alu_access_d <= 1'b0;
    main_access_d <= 1'b0;
    state <= ST_IDLE;
    enabled <= 1'b0;
    condition <= 2'd0;
    command <= 3'd0;
    color <= 3'd0;
    mask_bits <= 8'd0;
    compare_result <= 8'd0;
    bank_mask <= 3'd0;
    tile_b <= 8'd0; tile_r <= 8'd0; tile_g <= 8'd0;
    addr_offset <= 14'd0;
    stipple <= 16'hffff;
    x0 <= 16'd0; y0 <= 16'd0; x1 <= 16'd0; y1 <= 16'd0;
    x0_hi <= 8'd0; y0_hi <= 8'd0; x1_hi <= 8'd0; y1_hi <= 8'd0;
    line_mode <= LN_NONE;
    line_active <= 1'b0;
    lx <= 16'd0; ly <= 16'd0;
    vx_neg <= 1'b0; vy_neg <= 1'b0;
    ldx <= 17'd0; ldy <= 17'd0; balance <= 17'd0;
    stip_idx <= 4'd15;
    acc_block <= 2'd0;
    acc_offset <= 13'd0;
    for (i = 0; i < 8; i = i + 1) compare_color[i] <= 8'd0;
  end
  else begin
    reg_wr_sr <= { reg_wr_sr[1:0], reg_wrn };
    alu_access_d <= alu_access;
    main_access_d <= main_access;

    if (reg_write) begin
`ifdef DEBUG_AVDRAW
      $display("AVDRAW W $d4%02x <- $%02x", SADDRBUS[7:0], SDATA);
`endif
      case (SADDRBUS[7:0])
        8'h10: begin enabled <= SDATA[7]; condition <= SDATA[6:5]; command <= SDATA[2:0]; end
        8'h11: color <= SDATA[2:0];
        8'h12: mask_bits <= SDATA;
        8'h13, 8'h14, 8'h15, 8'h16,
        8'h17, 8'h18, 8'h19, 8'h1a: compare_color[SADDRBUS[2:0]] <= SDATA & 8'h87;
        8'h1b: bank_mask <= SDATA[2:0];
        8'h1c: tile_b <= SDATA;
        8'h1d: tile_r <= SDATA;
        8'h1e: tile_g <= SDATA;
        8'h20: addr_offset[13:9] <= SDATA[4:0];
        8'h21: addr_offset[8:1] <= SDATA;
        8'h22: stipple[15:8] <= SDATA;
        8'h23: stipple[7:0] <= SDATA;
        8'h24: begin x0_hi <= SDATA; x0 <= {SDATA, x0[7:0]}; end
        8'h25: x0 <= {x0_hi, SDATA};
        8'h26: begin y0_hi <= SDATA; y0 <= {SDATA, y0[7:0]}; end
        8'h27: y0 <= {y0_hi, SDATA};
        8'h28: begin x1_hi <= SDATA; x1 <= {SDATA, x1[7:0]}; end
        8'h29: x1 <= {x1_hi, SDATA};
        8'h2a: begin y1_hi <= SDATA; y1 <= {SDATA, y1[7:0]}; end
        8'h2b: begin
          // Writing the low byte of Y1 latches it and starts the line.
          y1 <= start_y1;
          lx <= x0;
          ly <= y0;
          vx_neg <= start_vx_neg;
          vy_neg <= start_vy_neg;
          ldx <= {1'b0, start_dx} + 17'd1;
          ldy <= {1'b0, start_dy} + 17'd1;
          balance <= start_long_y ? {2'd0, start_dx[15:1]} : {2'd0, start_dy[15:1]};
          line_mode <= start_mode;
          line_active <= 1'b1;
          stip_idx <= 4'd15;
          state <= ST_READ;
        end
        default: ;
      endcase
    end

    case (state)
      ST_IDLE: begin
        // Sub CPU first if both land on the same clock; the aperture write is
        // held for a whole main bus cycle and will still be there next time.
        if (alu_access_edge) begin
          acc_block  <= {AV_ACTIVE_PAGE, SVRADRS[13]};
          acc_offset <= SVRADRS[12:0];
          state <= ST_READ;
        end
        else if (main_access_edge) begin
`ifdef DEBUG_AVDRAW
          $display("AVDRAW T addr=$%04x bank=%0d cmd=%0d", AV_VRAM_ADDR, AV_VRAM_BANK, command);
`endif
          // CRTRAM's own cpu_block/cpu_offset, so the ALU combines exactly the
          // byte the plain store would have written.
          acc_block  <= {AV_VRAM_BANK, AV_VRAM_ADDR[13]};
          acc_offset <= AV_VRAM_ADDR[12:0];
          state <= ST_READ;
        end
      end
      ST_READ: state <= ST_WRITE;
      ST_WRITE: begin
        // $D413 reports the compare result of the intercepted-access path.
        // PutDot -- the line path -- does not touch it.
        if (cmp_active && ~line_active) compare_result <= pass_bits;
        if (line_active) begin
          stip_idx <= stip_idx - 4'd1;
          if (line_more) begin
            case (line_mode)
              LN_VERT: ly <= ly_step;
              LN_HORZ: lx <= lx_step;
              LN_LONGX: begin
                lx <= lx_step;
                balance <= cross_x ? (bal_x - ldx) : bal_x;
                if (cross_x) ly <= ly_step;
              end
              LN_LONGY: begin
                ly <= ly_step;
                balance <= cross_y ? (bal_y - ldy) : bal_y;
                if (cross_y) lx <= lx_step;
              end
              default: ;
            endcase
            state <= ST_READ;
          end
          else begin
            line_active <= 1'b0;
            line_mode <= LN_NONE;
            state <= ST_IDLE;
          end
        end
        else state <= ST_IDLE;
      end
      default: state <= ST_IDLE;
    endcase
  end
end

endmodule
