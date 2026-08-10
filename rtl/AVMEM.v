// FM77AV main-memory front end.
//
// The AV presents a 256 KB physical space through a 64 KB 6809 address bus.
// At reset MMR is disabled and the FM-7 machine lives at physical $30000. The
// initiator and F-BASIC ROM overlays are selected by ROMS.v; this block owns
// the RAM, boot-RAM seed, MMR registers, and TWR window.

module AVMEM(
  input        CLKSYS,
  input        RESETBn,
  input        machine_av,
  input  [1:0] bootrom_sel,
  input [15:0] MADDRBUS,
  input  [7:0] DIN,
  input        RWBn,
  input        WTQEn,
  input        RDQEn,
  input  [13:0] VRAM_OFFSET,
  input  [7:0] VRAM_DOUT,
  output [7:0] DOUT,
  output reg [7:0] IODOUT,
  output       IOSEL,
  output       TWRSEL,
  output [1:0] SUBMON_SEL,
  output       SUBMON_RESET,
  output       AV_MODE_320,
  output       VRAM_SEL,
  output [1:0] VRAM_PLANE,
  output [13:0] VRAM_ADDR,
  output       VRAM_WRITE,
  output [7:0] VRAM_DIN
);

reg av_mode_320;
wire mode_io_sel = machine_av && (MADDRBUS == 16'hfd12);
wire io_sel = machine_av && (((MADDRBUS >= 16'hfd80) && (MADDRBUS <= 16'hfd93)) ||
                             mode_io_sel);
wire submon_io_sel = machine_av && (MADDRBUS == 16'hfd13);
assign IOSEL = io_sel;
assign AV_MODE_320 = av_mode_320;

wire bootram_sel = machine_av &&
                   (MADDRBUS >= 16'hfe00) && (MADDRBUS < 16'hffe0);

// Base AV has four MMR segments and 16 six-bit bank registers per segment.
// The register value is physical A17:A12. Reset values are irrelevant while
// MMR is disabled, but are defined as zero to match 77AVEMU/CSP.
reg [5:0] mmr [0:3][0:15];
reg [1:0] mmr_segment;
reg [7:0] twr_address;
reg       mmr_enable;
reg       twr_enable;
reg       bootram_write_enable;
reg [1:0] submon_sel;
reg [7:0] submon_reset_count;
assign SUBMON_SEL = submon_sel;
assign SUBMON_RESET = (submon_reset_count != 8'd0);

wire twr_sel = machine_av && twr_enable &&
               (MADDRBUS >= 16'h7c00) && (MADDRBUS < 16'h8000);
assign TWRSEL = twr_sel;
wire initiator_sel = machine_av &&
                     (((MADDRBUS >= 16'h6000) && (MADDRBUS < 16'h8000)) ||
                      (MADDRBUS >= 16'hfffe));
wire fbasic_sel = machine_av && (MADDRBUS >= 16'h8000) &&
                  (MADDRBUS < 16'hfc00);

wire av_write = machine_av && ~WTQEn;
wire bootram_write = av_write && bootram_sel && bootram_write_enable;
wire mmr_write = av_write && (io_sel || submon_io_sel);

// TWR maps the 1 KB window at $7c00-$7fff into page zero. MMR is checked only
// below $fc00; the entire $fc00-$ffff range stays on the physical FM77AV page.
reg [17:0] physical_address;
always @* begin
  if (twr_enable && (MADDRBUS >= 16'h7c00) && (MADDRBUS < 16'h8000))
    physical_address = {2'b00, twr_address, 8'd0} + {8'd0, MADDRBUS[9:0]};
  else if (mmr_enable && (MADDRBUS < 16'hfc00))
    physical_address = {mmr[mmr_segment][MADDRBUS[15:12]], MADDRBUS[11:0]};
  else
    physical_address = 18'h30000 + {2'b00, MADDRBUS};
end

// The AV's physical $10000-$1BFFF range is the three 16 KB video planes.
// MMR maps this aperture into the main CPU address space; it is not ordinary
// RAM and must stay coherent with the raster/sub-CPU VRAM store.
wire vram_sel = machine_av &&
                (physical_address >= 18'h10000) &&
                (physical_address < 18'h1c000);
assign VRAM_SEL   = vram_sel;
assign VRAM_PLANE = physical_address[15:14]; // 0=B, 1=R, 2=G
// 77AVEMU's TransformVRAMAddress preserves the plane/page high bits while
// wrapping the low address at 8 KB in 320x200 mode (16 KB in 640x200 mode).
// VRAM_OFFSET is the existing sub-system display offset, so main-CPU MMR
// accesses follow the same scroll transform as the reference machine.
wire [13:0] vram_addr_raw = physical_address[13:0];
wire [13:0] vram_addr_640 = vram_addr_raw + VRAM_OFFSET;
wire [13:0] vram_addr_320 = {vram_addr_raw[13],
                             vram_addr_raw[12:0] + VRAM_OFFSET[12:0]};
assign VRAM_ADDR  = av_mode_320 ? vram_addr_320 : vram_addr_640;
assign VRAM_WRITE = av_write && vram_sel;
assign VRAM_DIN   = DIN;

// ROM and boot-RAM windows do not write the physical RAM array. The AV F-BASIC
// ROM is not shadowed by this first backend; boot RAM has its explicit $FD93
// bit-0 write enable.
wire ram_write = av_write && !io_sel && !bootram_sel && !vram_sel &&
                 (!initiator_sel || twr_sel) && !fbasic_sel &&
                 (MADDRBUS < 16'hfffe);
wire [7:0] ram_q;

ram #(18,8) av_ram(
  .clk  ( CLKSYS             ),
  .addr ( physical_address   ),
  .din  ( DIN               ),
  .q    ( ram_q              ),
  .wr_n ( ~ram_write        ),
  .rd_n ( ~RDQEn            ),
  .ce_n ( 1'b0              )
);

// The 480-byte loader is copied from initiate.rom[$1800/$1a00] by the real
// machine at reset. Keeping the two mode images separate makes the OSD's DOS
// boot selection deterministic while preserving the AV rule that this is RAM
// after $FD93 bit 0 is enabled.
reg [7:0] boot_basic [0:479];
reg [7:0] boot_dos   [0:479];
initial begin
  $readmemh("./roms/fm77av_boot_basic.rom.mem", boot_basic);
  $readmemh("./roms/fm77av_boot_dos.rom.mem",   boot_dos);
end

wire [8:0] boot_offset = MADDRBUS[8:0];
wire [7:0] boot_q = (boot_offset < 9'd480) ?
                    (bootrom_sel[1] ? boot_dos[boot_offset] :
                                      boot_basic[boot_offset]) : 8'hff;

always @(posedge CLKSYS) begin
  if (~RESETBn) begin
    mmr_segment         <= 2'd0;
    twr_address         <= 8'd0;
    mmr_enable          <= 1'b0;
    twr_enable          <= 1'b0;
    bootram_write_enable <= 1'b0;
    av_mode_320         <= 1'b0;
    submon_sel          <= 2'd0; // Type C monitor
    submon_reset_count  <= 8'd0;
    mmr[0][0] <= 6'd0; mmr[0][1] <= 6'd0; mmr[0][2] <= 6'd0; mmr[0][3] <= 6'd0;
    mmr[0][4] <= 6'd0; mmr[0][5] <= 6'd0; mmr[0][6] <= 6'd0; mmr[0][7] <= 6'd0;
    mmr[0][8] <= 6'd0; mmr[0][9] <= 6'd0; mmr[0][10] <= 6'd0; mmr[0][11] <= 6'd0;
    mmr[0][12] <= 6'd0; mmr[0][13] <= 6'd0; mmr[0][14] <= 6'd0; mmr[0][15] <= 6'd0;
    mmr[1][0] <= 6'd0; mmr[1][1] <= 6'd0; mmr[1][2] <= 6'd0; mmr[1][3] <= 6'd0;
    mmr[1][4] <= 6'd0; mmr[1][5] <= 6'd0; mmr[1][6] <= 6'd0; mmr[1][7] <= 6'd0;
    mmr[1][8] <= 6'd0; mmr[1][9] <= 6'd0; mmr[1][10] <= 6'd0; mmr[1][11] <= 6'd0;
    mmr[1][12] <= 6'd0; mmr[1][13] <= 6'd0; mmr[1][14] <= 6'd0; mmr[1][15] <= 6'd0;
    mmr[2][0] <= 6'd0; mmr[2][1] <= 6'd0; mmr[2][2] <= 6'd0; mmr[2][3] <= 6'd0;
    mmr[2][4] <= 6'd0; mmr[2][5] <= 6'd0; mmr[2][6] <= 6'd0; mmr[2][7] <= 6'd0;
    mmr[2][8] <= 6'd0; mmr[2][9] <= 6'd0; mmr[2][10] <= 6'd0; mmr[2][11] <= 6'd0;
    mmr[2][12] <= 6'd0; mmr[2][13] <= 6'd0; mmr[2][14] <= 6'd0; mmr[2][15] <= 6'd0;
    mmr[3][0] <= 6'd0; mmr[3][1] <= 6'd0; mmr[3][2] <= 6'd0; mmr[3][3] <= 6'd0;
    mmr[3][4] <= 6'd0; mmr[3][5] <= 6'd0; mmr[3][6] <= 6'd0; mmr[3][7] <= 6'd0;
    mmr[3][8] <= 6'd0; mmr[3][9] <= 6'd0; mmr[3][10] <= 6'd0; mmr[3][11] <= 6'd0;
    mmr[3][12] <= 6'd0; mmr[3][13] <= 6'd0; mmr[3][14] <= 6'd0; mmr[3][15] <= 6'd0;
  end
  else begin
    if (submon_reset_count != 8'd0)
      submon_reset_count <= submon_reset_count - 8'd1;

    if (mmr_write) begin
      case (MADDRBUS[7:0])
      8'h12: av_mode_320 <= DIN[6];
      8'h80, 8'h81, 8'h82, 8'h83,
      8'h84, 8'h85, 8'h86, 8'h87,
      8'h88, 8'h89, 8'h8a, 8'h8b,
      8'h8c, 8'h8d, 8'h8e, 8'h8f:
        mmr[mmr_segment][MADDRBUS[3:0]] <= DIN[5:0];
      8'h90: mmr_segment <= DIN[1:0];
      8'h92: twr_address <= DIN;
      8'h93: begin
        mmr_enable           <= DIN[7];
        twr_enable           <= DIN[6];
        bootram_write_enable <= DIN[0];
      end
      8'h13: begin
        // 0=C, 1=A, 2=B, 4=RAM on AV40. The base AV has no RAM monitor
        // bank, so retain Type C for unsupported values.
        case (DIN[2:0])
          3'd1: submon_sel <= 2'd1;
          3'd2: submon_sel <= 2'd2;
          default: submon_sel <= 2'd0;
        endcase
        // The real AV resets the sub-system on every write, including a
        // write that selects the already-active monitor bank.
        submon_reset_count <= 8'hff;
      end
      default: ;
      endcase
    end

    if (bootram_write)
      if (bootrom_sel[1]) boot_dos[boot_offset] <= DIN;
      else                 boot_basic[boot_offset] <= DIN;
  end
end

always @* begin
  case (MADDRBUS[7:0])
    8'h12: IODOUT = 8'hbf | (av_mode_320 ? 8'h40 : 8'h00);
    8'h80, 8'h81, 8'h82, 8'h83,
    8'h84, 8'h85, 8'h86, 8'h87,
    8'h88, 8'h89, 8'h8a, 8'h8b,
    8'h8c, 8'h8d, 8'h8e, 8'h8f:
      IODOUT = {2'b00, mmr[mmr_segment][MADDRBUS[3:0]]};
    8'h93: IODOUT = 8'h3f | (mmr_enable ? 8'h80 : 8'h00) |
                         (twr_enable ? 8'h40 : 8'h00);
    default: IODOUT = 8'hff;
  endcase
end

assign DOUT = bootram_sel ? boot_q : vram_sel ? VRAM_DOUT : ram_q;

endmodule
