//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_BLACKOUT  = 0;
assign HDMI_BOB_DEINT = 0;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 0;
// assign AUDIO_L = 0;
// assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"

// ---------------------------------------------------------------- OSD bits
// Every bit of `status` this core reads, and nothing else is allocated. sys/
// reserves none of them -- hps_io just transports 128 bits and CONF_STR below
// is the only thing that gives them meaning.
//
//   bit(s)    menu entry                 read at
//   ------    ----------------------     ----------------------------------
//   0         Reset / Reset+close OSD    reset_req
//   8         Tape Rewind (trigger)      rewind -> t77_decode
//   9         Tape Audio                 cin_audio, relay_audio
//   11:10     Boot ROM                   bootrom_sel -> ROMS.v M152 bank
//   12        Machine family             machine_av -> AV memory/video/I/O
//   122:121   Aspect ratio               VIDEO_ARX / VIDEO_ARY
//
// Bits 1..7 and 13..120 are free. The hole at 1..7 is where the template's
// "TV Mode" (O[2]) and "Noise" (O[4:3]) demo options used to sit; they drove
// nothing in this core and are gone. The hole is left as-is deliberately --
// renumbering would only invalidate saved .cfg files for no gain.
localparam CONF_STR = {
  "FM-7;;",
  "-;",
  "F1,t77,Load Tape;",
  "S0,d77d88,Mount Disk 1;",
  "S1,d77d88,Mount Disk 2;",
  "T[8],Tape Rewind;",
  "O[9],Tape Audio,Off,On;",
  "O[11:10],Boot ROM,0 disk,1 alt,2 dos-a,3 empty;",
  "O[12],Machine,FM-7,FM77AV (experimental);",
  "-;",
  "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
  "-;",
  "T[0],Reset;",
  "R[0],Reset and close OSD;",
  // J1/jn MUST stay last, after the reset entries. MiSTer reserves a menu slot
  // where J1 appears in the string but DRAWS the joystick item ("Fire mode.")
  // at the bottom of the OSD, so every entry after J1 has its action shifted
  // one item earlier than its label. With J1 in the middle, selecting "Reset"
  // ran "Aspect ratio". Every working core puts these last -- RX78.sv and
  // Arcade-Asteroids.sv both go R0,Reset / J1 / jn / V,v.
  "J1,Button A,Button B;",
  "jn,A,B;",
  "v,4;",
  "V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

// The AV selector is a machine-family bit, not a second boot-ROM choice.
// FM77AV has a different memory map, video system, sub-I/O and sound device;
// those must all see the same family selection.
wire machine_av = status[12];

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [31:0] joy1, joy2;

// Floppy block-device interface. VDNUM 2 exposes the FM-7's two physical
// drives to the OSD and to the single MB8877 controller in core.v.
wire [1:0]  img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba [2];
wire [1:0]  sd_rd, sd_wr, sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din [2];
wire        sd_buff_wr;

// WIDE must stay 0. hps_io sizes BOTH the ioctl download path and the floppy
// sector buffer from it -- `DW = WIDE ? 15 : 7`, `AW = WIDE ? 12 : 13`. With
// WIDE(1) the sector buffer becomes 16 bits wide and steps one address per
// WORD, but sd_buff_dout/din here are [7:0] and sd_buff_addr is [8:0], so the
// connection silently truncated: the wd1793 received bytes 0,2,4,...,510 of
// each 512-byte sector, landed at addresses 0..255, with 256..511 never
// written. Every sector read returned garbage, so no disk could ever boot --
// the boot ROM cleared the screen and hung. vsim never caught it because
// vsim/sim.v has no hps_io at all and SimBlockDevice speaks 8-bit natively.
// The tape path is byte-wide to match (see wtbt and tape_size below).
hps_io #(.CONF_STR(CONF_STR),.WIDE(0),.VDNUM(2)) hps_io
(
  .clk_sys(clk_sys),
  .HPS_BUS(HPS_BUS),
  .EXT_BUS(),
  .gamma_bus(),

  .ioctl_download(ioctl_download),
  .ioctl_wr(ioctl_wr),
  .ioctl_addr(ioctl_addr),
  .ioctl_dout(ioctl_dout),
  .ioctl_index(ioctl_index),
  // Back-pressure for the tape download. This was left unconnected -- an
  // INPUT to hps_io with no driver, so the HPS was told "never wait" and
  // streamed bytes at whatever rate it liked while the SDRAM controller
  // dropped the ones it could not take. vsim/sim.v has always driven it.
  .ioctl_wait(ioctl_wait),

  .joystick_0(joy1),
  .joystick_1(joy2),

  .buttons(buttons),
  .status(status),

  .ps2_key(ps2_key),

  .img_mounted(img_mounted),
  .img_readonly(img_readonly),
  .img_size(img_size),
  .sd_lba(sd_lba),
  .sd_blk_cnt('{6'd0, 6'd0}),
  .sd_rd(sd_rd),
  .sd_wr(sd_wr),
  .sd_ack(sd_ack),
  .sd_buff_addr(sd_buff_addr),
  .sd_buff_dout(sd_buff_dout),
  .sd_buff_din(sd_buff_din),
  .sd_buff_wr(sd_buff_wr)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys, locked, _2MHz;
pll pll
(
  .refclk(CLK_50M),
  .rst(0),
  .outclk_0(clk_sys),
  .outclk_1(_2MHz),
  .locked(locked)
);

// Reset sources, and there are exactly three: RESET (sys_top asserts it at
// power-on and on core load), status[0] (the OSD's Reset / Reset and close
// OSD, both of which pulse bit 0) and buttons[1] (the physical user button).
//
// The pulse is latched rather than used directly. status[0] is momentary, and
// the FM-7 logic runs on clock enables divided down from CLKSYS -- the main
// CPU's E clock is 1.2288 MHz against 48 MHz -- so a reset must be held long
// enough for every one of those domains to see it. 2^20 CLKSYS cycles is
// 21.8 ms, tens of thousands of cycles even for the slowest. The counter also
// holds reset while the PLL is unlocked, and its {20{1'b1}} initial value
// means the core comes out of FPGA configuration already in reset instead of
// relying on a power-up state -- see TODO.md P0-2 for what that cost before.
//
// img_mounted is deliberately NOT a reset source. Auto-resetting on mount
// would boot a disk inserted from the OSD, but it would also reboot the
// machine on every mid-game disk swap -- Ys (Disk A/B) and Mugen no Shinzou II
// (Disk 1/2) both do that. Mount-then-boot belongs in the MGL instead, as a
// <reset delay="1" hold="1"/> after the <file> element.
reg machine_av_d = 1'b0;
always @(posedge clk_sys)
  machine_av_d <= machine_av;

// A family change is a board change. Hold reset long enough for every
// clock-enable domain to observe it. core.v then releases the selected
// machine's CPUs through their normal reset-vector path.
wire machine_mode_changed = machine_av_d ^ machine_av;
wire reset_req = RESET | status[0] | buttons[1] | machine_mode_changed;
reg [19:0] reset_count = {20{1'b1}};

always @(posedge clk_sys) begin
  if(reset_req | ~locked)
    reset_count <= {20{1'b1}};
  else if(|reset_count)
    reset_count <= reset_count - 1'd1;
end

wire reset = |reset_count;

// index 1 == "F1,t77,Load Tape" in CONF_STR. Everything below keys off THIS,
// not off raw ioctl_download: the SDRAM write port and the rewind pulse both
// belong to the tape, and any other ioctl transfer would otherwise scribble
// over the tape image and rewind the deck. vsim/sim.v has always gated on it.
wire tape_download = ioctl_download && (ioctl_index[7:0] == 8'd1);

reg old_ioctl_download;
always @(posedge clk_sys)
  old_ioctl_download <= tape_download;

wire [2:0] grb;
wire [23:0] rgb;

assign VGA_R = machine_av ? rgb[23:16] : {8{grb[1]}};
assign VGA_G = machine_av ? rgb[15:8]  : {8{grb[2]}};
assign VGA_B = machine_av ? rgb[7:0]   : {8{grb[0]}};

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire ce_pix;
wire [7:0] video;

wire RESETn = ~reset;
wire CLKSYS = clk_sys;
wire cin;
wire motor;
wire [15:0] sdram_data;
wire [24:0] sdram_addr;
wire need_more_byte;
wire sdram_ready;

// Hold the HPS off while the SDRAM controller is busy, so every byte of the
// t77 actually lands. Same expression vsim/sim.v uses.
wire ioctl_wait = (tape_download | kanji_download) & ~sdram_ready;
wire rewind = (old_ioctl_download & ~tape_download) | status[8];

// Size of the mounted tape, latched from the ioctl download, so t77_decode
// can stop at the end instead of running on into whatever else is in SDRAM.
// hps_io is WIDE(0), so ioctl_addr steps by 1 and ioctl_dout is a byte.
reg [24:0] tape_size = 25'd0;
always @(posedge clk_sys) begin
  if (tape_download) begin
    if (ioctl_wr) tape_size <= ioctl_addr + 25'd1;
  end
end
wire SVIDEOCLK;
wire [13:0] audio_out;
wire [11:0] fm_audio_out;
wire buzzer;
wire [7:0] relay_snd;

wire [15:0] cin_audio = { 1'b0, cin & motor & status[9], 13'b0 };
// audio_out is 14 bits, so `{ 1'b0, audio_out, 13'b0 }` is a 28-bit expression
// assigned to a 16-bit wire: Verilog keeps the LOW 16, which is audio_out[2:0]
// shifted up to bits 15:13. Only the bottom three bits of the PSG mix reached
// the DAC, at full scale -- the fastest-changing bits amplified to maximum,
// i.e. noise rather than the tune, swamping the buzzer and tape audio that sit
// at bit 13. Measured on Thexder: PSG mix peaked at 10238 and core_audio came
// out as a constant-amplitude 57344 = 7 << 13.
//
// {2'b00, audio_out} keeps all 14 bits. The four sources still cannot overflow:
// 8192 + 16383 + 8192 + 32640 = 65407.
wire [15:0] core_audio =  { 2'b00, audio_out };
wire [15:0] buz_audio = { 1'b0, buzzer, 13'b0 };
wire [15:0] relay_audio = { 1'b0, (status[9] ? relay_snd : 8'd0), 7'b0 };

// The YM2203's FM half. It arrives unsigned around a 2048 midpoint, so it
// costs a small DC offset and at most 4095 of swing -- the largest slice
// left before this sum overflows 16 bits:
// 8192 + 12240 + 8192 + 32640 + 4095 = 65359.
wire [15:0] fm_audio = { 4'b0000, fm_audio_out };
assign AUDIO_L = cin_audio + core_audio + buz_audio + relay_audio + fm_audio;
assign AUDIO_R = cin_audio + core_audio + buz_audio + relay_audio + fm_audio;

core u_core(
  .RESETn      ( RESETn        ),
  .CLKSYS      ( CLKSYS        ),
  .HBLANK      ( HBlank        ),
  .VBLANK      ( VBlank        ),
  .VSync       ( VSync         ),
  .HSync       ( HSync         ),
  .grb         ( grb           ),
  .rgb         ( rgb           ),
  .ps2_key     ( ps2_key       ),
  .joystick_0  ( joy1[5:0]     ),
  .joystick_1  ( joy2[5:0]     ),
  .SVIDEOCLK   ( SVIDEOCLK     ),
  .ce_pix      ( ce_pix        ),
  .audio_out   ( audio_out     ),
  .fm_audio_out( fm_audio_out ),
  .KANJI_ADDR  ( kanji_addr    ),
  .KANJI_RD    ( kanji_rd      ),
  .KANJI_GNT   ( kanji_gnt     ),
  .KANJI_READY ( kanji_ready   ),
  .KANJI_DATA  ( sdram_data    ),
  .buzzer      ( buzzer        ),
  // tape
  .cin         ( cin           ),
  .motor       ( motor         ),
  .bootrom_sel ( status[11:10] ),
  .machine_av  ( machine_av    ),
  // floppy
  .img_mounted  ( img_mounted  ),
  .img_readonly ( img_readonly ),
  .img_size     ( img_size     ),
  .sd_lba       ( sd_lba       ),
  .sd_rd        ( sd_rd        ),
  .sd_wr        ( sd_wr        ),
  .sd_ack       ( sd_ack       ),
  .sd_buff_addr ( sd_buff_addr ),
  .sd_buff_dout ( sd_buff_dout ),
  .sd_buff_din  ( sd_buff_din  ),
  .sd_buff_wr   ( sd_buff_wr   )
);


t77_decode u_t77_decode(
  .CLKSYS     ( CLKSYS         ),
  .start      ( motor          ),
  .data       ( sdram_data     ),
  .data_stb   ( sdram_ready    ),
  .sdram_addr ( sdram_addr     ),
  .sdram_rd   ( need_more_byte ),
  .sout       ( cin            ),
  .rewind     ( rewind         ),
  .image_size ( tape_size      ),
  .eot        (                )
);


// The kanji ROM (128 KB) lives in SDRAM rather than block RAM -- see the
// header of rtl/KANJI.v. It arrives as boot.rom on ioctl index 0, which the
// MiSTer framework uploads automatically at core start, so it just works.
// Based well clear of any tape image.
localparam [24:0] KANJI_BASE = 25'h0400000;
// boot.rom is ioctl index 0. Test the low byte, not [15:6]: the tape is
// index 1 and [15:6]==0 matches everything from 0 to 63, which would send
// tape bytes to the kanji base as well.
wire        kanji_download = ioctl_download && (ioctl_index[7:0] == 8'd0);
wire [16:0] kanji_addr;
wire        kanji_rd, kanji_gnt, kanji_ready;

wire [24:0] sdc_addr;
wire  [7:0] sdc_din;
wire        sdc_we, sdc_rd;

SDRAM_MUX u_sdram_mux(
  .CLKSYS      ( CLKSYS ),
  .DL_WR       ( ioctl_wr & (tape_download | kanji_download) ),
  .DL_ADDR     ( kanji_download ? (KANJI_BASE + {8'd0, ioctl_addr[16:0]})
                                 : ioctl_addr ),
  .DL_DATA     ( ioctl_dout ),
  .TAPE_ADDR   ( sdram_addr ),
  .TAPE_RD     ( need_more_byte ),
  .TAPE_READY  ( ),
  .KANJI_ADDR  ( KANJI_BASE + {8'd0, kanji_addr} ),
  .KANJI_RD    ( kanji_rd ),
  .KANJI_GNT   ( kanji_gnt ),
  .KANJI_READY ( kanji_ready ),
  .SD_ADDR     ( sdc_addr ),
  .SD_DIN      ( sdc_din ),
  .SD_WE       ( sdc_we ),
  .SD_RD       ( sdc_rd ),
  .SD_READY    ( sdram_ready ),
  .SD_DOUT     ( sdram_data ),
  .SD_DOUT_OUT ( )
);

sdram u_sdram(
  .*,
  .init  ( ~locked                                  ),
  .clk   ( CLKSYS                                   ),
  .wtbt  ( 2'b00                                    ),
  .addr  ( sdc_addr ),
  .dout  ( sdram_data                               ),
  .din   ( {8'd0, sdc_din} ),
  .we    ( sdc_we ),
  .rd    ( sdc_rd ),
  .ready ( sdram_ready                              )
);

pcm pcm(
  .CLKSYS         ( CLKSYS    ),
  .motor          ( motor     ),
  .unsigned_audio ( relay_snd )
);

assign CLK_VIDEO = clk_sys;
// One-cycle pulse per pixel. ce_pix is SFTCLK, a 16 MHz square wave that
// clk_en holds high two of every three CLK_VIDEO cycles, and ascal samples
// every high cycle -- which is how 640 active pixels per line became 960 in
// the scaler (and 1280 on the pre-2026 framework: the two widths are the two
// ascal versions' readings of the same over-asserted enable). Same
// edge-detect vsim/sim.v has always used, which is why sim screenshots were
// 640 wide while hardware's were not.
reg ce_pix_d;
always @(posedge clk_sys) ce_pix_d <= ce_pix;
assign CE_PIXEL = ce_pix & ~ce_pix_d;
assign VGA_DE = ~(HBlank | VBlank);
assign VGA_HS = HSync;
assign VGA_VS = VSync;


assign LED_USER    = cin;

endmodule
