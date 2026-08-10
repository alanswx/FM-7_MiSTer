// `include "rtl/clocks.svh"

module core(
  input RESETn,
  input CLKSYS,
  output HBLANK,
  output VBLANK,
  output VSync,
  output HSync,
  output ce_pix,
  output [2:0] grb,
  input [10:0] ps2_key,
  // Joysticks (MiSTer order: [0]=right [1]=left [2]=down [3]=up [4]=A [5]=B)
  input [5:0] joystick_0,
  input [5:0] joystick_1,
  input cin,
  output motor,
  output SVIDEOCLK,
  output [13:0] audio_out,
  output buzzer,
  input [1:0] bootrom_sel,
  input machine_av,

  // Floppy: MiSTer block-device interface, straight through to FDC.v
  input  [1:0]  img_mounted,
  input         img_readonly,
  input  [63:0] img_size,
  output [31:0] sd_lba [2],
  output [1:0]  sd_rd,
  output [1:0]  sd_wr,
  input  [1:0]  sd_ack,
  input   [8:0] sd_buff_addr,
  input   [7:0] sd_buff_dout,
  output  [7:0] sd_buff_din [2],
  input         sd_buff_wr
);

wire [15:0] MADDRBUS;
wire [7:0] MDATABUS_in;
wire [7:0] MDATABUS_out;
wire [7:0] ROMDATA;
wire [7:0] MRAM_dout;
wire [7:0] AVMEM_dout;
wire [7:0] AVIO_dout;
wire       AVIO_sel;
wire       AVTWR_sel;
wire [1:0] AV_SUBMON_SEL;
wire       AV_SUBMON_RESET;
wire       AV_MODE_320;
wire [13:0] AV_VRAM_OFFSET;
wire       SFTSTEP;
wire [7:0] AV_VRAM_DOUT;
wire       AV_VRAM_SEL;
wire [1:0] AV_VRAM_PLANE;
wire [13:0] AV_VRAM_ADDR;
wire       AV_VRAM_WRITE;
wire [7:0] AV_VRAM_DIN;
wire [7:0] MAINRAM_dout = machine_av ? AVMEM_dout : MRAM_dout;
wire [7:0] TIMER_out;
wire [7:0] CLKCTRL_out;
wire [7:0] PERIPH_out;
wire [7:0] MFD_out;
wire [7:0] RS232_dout;
wire [7:0] PALDATA;
wire [23:0] AV_ANALOG_RGB;
wire [7:0] MKDATA;
wire [7:0] SOUND_dout;
wire [7:0] KANJI_dout;

wire [15:0] SADDRBUS;
wire [7:0] SDATABUS_in;
wire [7:0] SDATABUS_out;
wire [7:0] SMEM_dout;
wire [7:0] AV_D430_dout;
wire       AV_DISPLAY_PAGE;
wire       AV_ACTIVE_PAGE;
wire       AV_VRAM_BANK;
wire [7:0] CRTRAMDATA;
wire [7:0] SKDATA;

wire [7:0] SRDATA_out;


wire WFD0Fn;
wire RDQEn;
wire FCXXn;
wire RAM1HB1n;
wire RAM1HB2n;
wire BTRDYn;
wire BTROMn;
wire SUBSELn;
wire MIOSn;
wire Z80W;
wire GHn;
wire NMIn = 1;
wire IRQn;
wire FIRQn;
wire DMAn;
wire Z80;
wire RESETBn;
wire QB;
wire EB;
wire BAB;
wire BSB;
wire RWB;
wire WTQEn;
wire REFGRVTn;
wire RDEn;
wire RWBn;
wire E;
wire IOSn;
wire FD0Xn;
wire PLTREGn;
wire AB3n;
wire WFD00n;
wire WFD01n;
wire WFD02n;
wire WFD03n;
wire WFD05n;
wire WFD37n;
wire WFD0En;
wire WFD0Dn;
wire RFD00n;
wire RFD01n;
wire RFD02n;
wire RFD04n;
wire RFD03n;
wire RFD05n;
wire RFD0En;
wire RFD0Fn;
wire WFD20n;
wire WFD21n;
wire RFD22n;
wire RFD23n;
wire BUZZERn;
wire ATTENTn;
wire BUSY;
wire BREAKn;
wire EXTDETn = 0; // ?
wire SOUND;
wire SCLKNMIn;
wire LPMASKn;
wire LPINTn;
wire IRQCLRn;
wire LPBUSY;
wire CANCELn;
wire SUBHALTREQn;
wire KEYINn;
wire TMMASK;
wire MRDYn;
wire _2MS;
wire EXTIRQ;
wire MCPUCLK;
wire SCPUCLK;
wire SUBIRQn;
wire KSTROBEn;
wire SHALTn;
wire SWTQEn;
wire SQANDEn;
wire SRDQEn;
wire SQB;
wire SEB;
wire SHALTSTn;
wire SRWB;
wire SRWBn;
wire SBA;
wire SCRTSWn;
wire SRESETn = RESETBn & ~AV_SUBMON_RESET;
wire SLEDn;
wire SIRQCLRn;
wire SVDHALT;
wire SVRACSn;
wire SBUSYSETn;
wire SVDOFFn;
wire SHALTACn;
wire VPAGE1n;
wire VPAGE2n;
wire VPAGE3n;
wire DPAGE1;
wire DPAGE2;
wire DPAGE3;
wire INS;
wire SCLK1;
wire SCLK2;
wire SCPUWEn;
wire SRDEn;
wire SROMSELn;
wire SRAM1CSn;
wire SRAM2CSn;
wire SROMDn;
wire SSMEMn;
wire SREGHn;
wire SREGLn;
wire KDATAn;
wire KACKNGn;
wire SDRAMGn;
wire SDRAMRn;
wire SDRAMBn;
wire SDRAMV1n;
wire SDRAMV2n;
wire SDRAMV3n;
wire EIRQn;
wire FD_MRn;
wire [7:0] FD_Din;
wire [7:0] FD_Dout;
wire [2:0] FD_RS;
wire FD_DRQn;
wire FD_INTRQn;
wire FD_CSn;
wire FD_WEn;
wire FD_REn;
wire RS232_CEn;
wire FD1Fn;
wire [7:0] SVDATAB;
wire [7:0] SVDATAR;
wire [7:0] SVDATAG;
wire SADRSEL;
wire SFTCLK;
wire [13:0] SVRADRS;
wire SVSYNCn;
wire SHSYNCn;
wire SFTLODn;
wire SBLANKn;
wire SCSYNCn;
wire SCASSEL;
wire SVCASBn;
wire SVCASRn;
wire SVCASGn;
wire SVWEn;
wire HBLANKn;
wire VBLANKn;
wire fm8_switch;
wire CLK2_5;
wire CLK1_2;
wire CLK0_3;

// FM77AV is not an FM-7 boot-ROM variant. Keep the family signal at the core
// boundary now, but fail safe until the AV memory/video/I/O backend is wired:
// selecting AV in the OSD must not present an FM-7 machine under an AV label.
wire RESETn_active = RESETn & ~machine_av;

assign HSync = SHSYNCn;
assign VSync = SVSYNCn;
assign HBLANK = ~HBLANKn;
assign VBLANK = ~VBLANKn;
assign ce_pix = SFTCLK;
assign buzzer = SOUND;

assign MDATABUS_in =
  ~(RFD00n & RFD01n) ? MKDATA :
  ~(IOSn | RFD02n) ? PERIPH_out :
  ~(IOSn | RFD03n) ? CLKCTRL_out :
  ~(IOSn | (RFD04n & RFD05n)) ? TIMER_out :
  ~(IOSn | RFD0En) ? SOUND_dout :
  ~(IOSn | FD1Fn) ? MFD_out :
  ~(IOSn | FD_CSn) ? MFD_out :
  ~(IOSn | RS232_CEn) ? RS232_dout :
  // $fd22/$fd23, the kanji ROM data pair. $fd20/$fd21 are write-only and are
  // deliberately NOT decoded here, so they fall through to the $ff default --
  // which is exactly what MAME's kanji_r returns for them.
  ~(RFD22n & RFD23n) ? KANJI_dout :
  ~PLTREGn ? PALDATA :
  AVIO_sel ? AVIO_dout :
  ~IOSn ? 8'hff :

  ~(SUBSELn | RDQEn) ? SRDATA_out :
  ~(BTROMn | BTRDYn) | ~RAM1HB2n ? ROMDATA :
  // `(MADDRBUS[15] & FCXXn)` is $8000-$fbff with the $fd0f window switched to
  // RAM, and without it that whole 31 KB READ AS ZERO.
  //
  // RAM1HB2n is really "F-BASIC ROM selected": ROMS.v has
  // `m107_q = ~(MADDRBUS[15] & FCXXn & ff_q)`, so it is asserted only in ROM
  // mode. In RAM mode it goes high, the ROMDATA arm above stops matching, and
  // the old MRAM condition could not match either -- `~(RAM1HB1n & RAM1HB2n)`
  // is `~(1 & 1)` = 0 there because RAM1HB1n is forced high for anything
  // outside $fc00-$ffff, and `MADDRBUS <= 16'h8000` is false above $8000. So
  // the mux fell through to its `8'h0` default.
  //
  // WRITES were always fine -- MRAM.v is a full 64 K with ce_n tied low -- so
  // this presented as "the data I stored comes back as zeros", not as a dead
  // memory. Xevious pushed a return address to its stack at $bee3, the RTS read
  // $0000 back, and the CPU ran away into page zero executing cleared RAM
  // ($00 $00 = NEG direct-page). That is the P4-15 signature, and it is also
  // why Ys loads a clean 24 KB to $8000-$dfff and then never runs it (P4-8).
  //
  // Reaching this arm with A15 set and FCXXn high necessarily means the RAM
  // window is open, because the ROMDATA arm above has already taken ROM mode.
  ~(RAM1HB1n & RAM1HB2n) || MADDRBUS <= 16'h8000
                         || (MADDRBUS[15] & FCXXn) ? MAINRAM_dout :
  8'h0;

assign SDATABUS_in =
  ~(KDATAn & KACKNGn) ? SKDATA :
  (machine_av && (SADDRBUS == 16'hd430) && SRWB) ? AV_D430_dout :
  ~(SDRAMBn & SDRAMGn & SDRAMRn) ? CRTRAMDATA :
	~(SSMEMn | SRWBn) ? SRDATA_out :
  ~(SROMDn & SROMSELn & SRAM1CSn & SRAM2CSn) ? SMEM_dout :
  8'hff;

CLKCTRL u_CLKCTRL(
  // FM-7 mode. This picks the CPU clock (MCPUCLK = CLK4_9 = 4.9152 MHz, so
  // E = 1.2288 MHz, the real FM-7 main CPU rate; 1'b0 selects SCLK1 and runs
  // it at the FM-8's 2 MHz) and is reported on $FD00 bit 0, which the BIOS
  // reads to choose between two different cassette routines.
  .SW2          ( 1'b1         ), // 0 = FM-8 compatibility
  .CLKSYS       ( CLKSYS       ),
  .SCLK1        ( SCLK1        ),
  .SCLK2        ( SCLK2        ),
  .SCLKNMIn     ( SCLKNMIn     ),
  .RFD00n       ( RFD00n       ),
  .RFD03n       ( RFD03n       ),
  .KEYINn       ( KEYINn       ),
  .LPINTn       ( LPINTn       ),
  .TMMASK       ( TMMASK       ),
  .SVIDEOCLK    ( SVIDEOCLK    ),
  .IOSn         ( IOSn         ),
  .BTRDYn       ( BTRDYn       ),
  .EB           ( EB           ),
  .RESETBn      ( RESETBn      ),
  .MRDYn        ( MRDYn        ),
  ._2MS         ( _2MS         ),
  .IRQCLRn      ( IRQCLRn      ),
  .EXTIRQ       ( EXTIRQ       ),
  .MCPUCLK      ( MCPUCLK      ),
  .SCPUCLK      ( SCPUCLK      ),
  .MDATABUS_out ( CLKCTRL_out  ),
  .IRQn         ( IRQn         ),
  .switch       ( fm8_switch   ),
  .CLK2_5       ( CLK2_5       ),
  .CLK1_2       ( CLK1_2       ),
  .CLK0_3       ( CLK0_3       )
);

ROMS u_ROMS(
  .MADDRBUS ( MADDRBUS    ),
  .RESETBn  ( RESETBn     ),
  .RFD0Fn   ( RFD0Fn      ),
  .WFD0Fn   ( WFD0Fn      ),
  .RDQEn    ( RDQEn       ),
  .CLKSYS   ( CLKSYS      ),
  .FCXXn    ( FCXXn       ),
  .RAM1HB2n ( RAM1HB2n    ),
  .ROMDATA  ( ROMDATA     ),
  .BTRDYn   ( BTRDYn      ),
  .BTROMn   ( BTROMn      ),
  .SUBSELn  ( SUBSELn     ),
  .MIOSn    ( MIOSn       ),
  .RAM1HB1n ( RAM1HB1n    ),
  .SW2      ( bootrom_sel ),
  .machine_av ( machine_av ),
  .twr_active ( AVTWR_sel )
);

MRAM u_MRAM(
  .RAM1HB1n ( RAM1HB1n     ),
  .RAM1HB2n ( RAM1HB2n     ),
  .RWBn     ( RWBn         ),
  .CLKSYS   ( CLKSYS       ),
  .MADDRBUS ( MADDRBUS     ),
  .DIN      ( MDATABUS_out ),
  .RDQEn    ( RDQEn        ),
  .DOUT     ( MRAM_dout    )
);

AVMEM u_AVMEM(
  .CLKSYS      ( CLKSYS       ),
  .RESETBn     ( RESETBn      ),
  .machine_av  ( machine_av   ),
  .bootrom_sel ( bootrom_sel  ),
  .MADDRBUS    ( MADDRBUS     ),
  .DIN         ( MDATABUS_out ),
  .RWBn        ( RWBn         ),
  .WTQEn       ( WTQEn        ),
  .RDQEn       ( RDQEn        ),
  .VRAM_OFFSET ( AV_VRAM_OFFSET ),
  .VRAM_DOUT   ( AV_VRAM_DOUT  ),
  .DOUT        ( AVMEM_dout   ),
  .IODOUT      ( AVIO_dout    ),
  .IOSEL       ( AVIO_sel     ),
  .TWRSEL      ( AVTWR_sel    ),
  .SUBMON_SEL  ( AV_SUBMON_SEL ),
  .SUBMON_RESET ( AV_SUBMON_RESET ),
  .AV_MODE_320 ( AV_MODE_320 ),
  .VRAM_SEL    ( AV_VRAM_SEL    ),
  .VRAM_PLANE  ( AV_VRAM_PLANE  ),
  .VRAM_ADDR   ( AV_VRAM_ADDR   ),
  .VRAM_WRITE  ( AV_VRAM_WRITE  ),
  .VRAM_DIN    ( AV_VRAM_DIN    )
);

// RDQEn, not RDEn, gates the I/O read decoder.
//
// RDEn is ~(RWB & EB), so it drops the instant E falls -- the same instant
// mc6809i latches the data bus (always @(negedge E)). The RFDxxn strobes are
// already high by then and the read mux above has fallen through to its
// `~IOSn ? 8'hff` default, so EVERY $fdxx read returned $ff. Real hardware is
// saved by 74LS138 propagation delay and the 6809's data hold window;
// zero-delay RTL is not.
//
// RDQEn is ~(RWB & (QB|EB)). Q falls a quarter cycle after E, so this strobe
// starts on the same edge and simply extends past the latch. It is what the
// ROM/RAM read path already uses, which is why that path always worked.
MDECODE u_MDECODE(
  .MADDRBUS ( MADDRBUS ),
  .RDEn     ( RDQEn    ),
  .E        ( E        ),
  .RWBn     ( RWBn     ),
  .WTQEn    ( WTQEn    ),
  .IOSn     ( IOSn     ),
  .FD0Xn    ( FD0Xn    ),
  .PLTREGn  ( PLTREGn  ),
  .AB3n     ( AB3n     ),
  .WFD00n   ( WFD00n   ),
  .WFD01n   ( WFD01n   ),
  .WFD02n   ( WFD02n   ),
  .WFD03n   ( WFD03n   ),
  .WFD05n   ( WFD05n   ),
  .WFD37n   ( WFD37n   ),
  .WFD0Dn   ( WFD0Dn   ),
  .WFD0En   ( WFD0En   ),
  .WFD0Fn   ( WFD0Fn   ),
  .RFD00n   ( RFD00n   ),
  .RFD01n   ( RFD01n   ),
  .RFD02n   ( RFD02n   ),
  .RFD04n   ( RFD04n   ),
  .RFD03n   ( RFD03n   ),
  .RFD05n   ( RFD05n   ),
  .RFD0En   ( RFD0En   ),
  .RFD0Fn   ( RFD0Fn   ),
  .WFD20n   ( WFD20n   ),
  .WFD21n   ( WFD21n   ),
  .RFD22n   ( RFD22n   ),
  .RFD23n   ( RFD23n   )
);

// Kanji ROM at $fd20-$fd23 (P3-3). Optional expansion hardware on a real FM-7,
// but software probes for it and there is no reason to advertise its absence.
KANJI u_KANJI(
  .CLKSYS       ( CLKSYS       ),
  .RESETBn      ( RESETBn      ),
  .MDATABUS_in  ( MDATABUS_out ),
  .WFD20n       ( WFD20n       ),
  .WFD21n       ( WFD21n       ),
  .RFD22n       ( RFD22n       ),
  .RFD23n       ( RFD23n       ),
  .MDATABUS_out ( KANJI_dout   )
);

MCPU u_MCPU(
  .MDATABUS_in  ( MDATABUS_in  ),
  .RESETn       ( RESETn_active ),
  .Z80W         ( Z80W         ),
  .MCPUCLK      ( MCPUCLK      ),
  .GHn          ( GHn          ),
  .NMIn         ( NMIn         ),
  .IRQn         ( IRQn         ),
  .FIRQn        ( FIRQn        ),
  .DMAn         ( DMAn         ),
  .CLKSYS       ( CLKSYS       ),
  .Z80          ( Z80          ),
  .RESETBn      ( RESETBn      ),
  .QB           ( QB           ),
  .EB           ( EB           ),
  .BAB          ( BAB          ),
  .BSB          ( BSB          ),
  .RWB          ( RWB          ),
  .WTQEn        ( WTQEn        ),
  .RDQEn        ( RDQEn        ),
  .REFGRVTn     ( REFGRVTn     ),
  .MDATABUS_out ( MDATABUS_out ),
  .MADDRBUS     ( MADDRBUS     ),
  .RDEn         ( RDEn         ),
  .RWBn         ( RWBn         ),
  .E            ( E            )
);

TIMER u_TIMER(
  .CLKSYS       ( CLKSYS       ),
  .MDATABUS_in  ( MDATABUS_out ),
  .MDATABUS_out ( TIMER_out    ),
  .WFD03n       ( WFD03n       ),
  .BUZZERn      ( BUZZERn      ),
  .RESETBn      ( RESETBn      ),
  .EB           ( EB           ),
  .Z80W         ( Z80W         ),
  .REFGRVTn     ( REFGRVTn     ),
  .ATTENTn      ( ATTENTn      ),
  .RFD04n       ( RFD04n       ),
  .RFD05n       ( RFD05n       ),
  .BUSY         ( BUSY         ),
  .SHALTACn     ( SHALTACn     ),
  .BREAKn       ( BREAKn       ),
  .EXTDETn      ( EXTDETn      ),
  .CLK0_3       ( CLK0_3       ),
  .SOUND        ( SOUND        ),
  .SCLKNMIn     ( SCLKNMIn     ),
  .DMAn         ( DMAn         ),
  .FIRQn        ( FIRQn        )
);

PERIPHERAL u_PERIPHERAL(
  .CLKSYS       ( CLKSYS       ),
  .MDATABUS_in  ( MDATABUS_out ),
  .MDATABUS_out ( PERIPH_out   ),
  .WFD00n       ( WFD00n       ),
  .WFD01n       ( WFD01n       ),
  .WFD05n       ( WFD05n       ),
  .RFD02n       ( RFD02n       ),
  .RFD03n       ( RFD03n       ),
  .RESETBn      ( RESETBn      ),
  .LPMASKn      ( LPMASKn      ),
  .LPINTn       ( LPINTn       ),
  .IRQCLRn      ( IRQCLRn      ),
  .LPBUSY       ( LPBUSY       ),
  .GHn          ( GHn          ),
  .Z80W         ( Z80W         ),
  .CANCELn      ( CANCELn      ),
  .SUBHALTREQn  ( SUBHALTREQn  ),
  .motor        ( motor        ),
  .cin          ( cin          )
);

// Sub-CPU VRAM wait state.
//
// MB60H010 hands the VRAM address bus to the sub CPU only while SCASSEL is high
// (blanking); during active display SVRADRS follows the raster instead. So a
// sub access to VRAM mid-display does not merely contend, it lands at the
// raster's address. That is what the blanket halt in FLAGS.v exists to prevent,
// and it costs the sub about 55% of its cycles even when running code that
// never touches VRAM -- which is what starves Thexder's shared-window byte pump
// (TODO.md P4-1).
//
// The right answer is a wait state on the access itself, but neither `nHALT`
// nor `nDMABREQ` can express one: mc6809i samples both at CPUSTATE_FETCH_I1,
// i.e. at instruction boundaries. So stall the sub's clock directly. Holding
// SCPUCLK low freezes the core mid-cycle until blanking arrives, at which point
// SVRADRS is its own address again and the access completes correctly.
wire sub_vram_sel = ~(SDRAMBn & SDRAMGn & SDRAMRn);  // sub is addressing VRAM
wire sub_vram_wait = sub_vram_sel & ~SCASSEL;        // ...while the raster owns it
wire SCPUCLK_w = SCPUCLK & ~sub_vram_wait;

SCPU u_SCPU(
  .RESETBn      ( RESETBn      ),
  .SCPUCLK      ( SCPUCLK_w    ),
  .SCLKNMIn     ( SCLKNMIn     ),
  .SUBIRQn      ( SUBIRQn      ),
  .KSTROBEn     ( KSTROBEn     ),
  .SHALTn       ( SHALTn       ),
  .SADDRBUS     ( SADDRBUS     ),
  .SDATABUS_in  ( SDATABUS_in  ),
  .SDATABUS_out ( SDATABUS_out ),
  .SWTQEn       ( SWTQEn       ),
  .SQANDEn      ( SQANDEn      ),
  .SRDQEn       ( SRDQEn       ),
  .SQB          ( SQB          ),
  .SEB          ( SEB          ),
  .SHALTSTn     ( SHALTSTn     ),
  .SRWB         ( SRWB         ),
  .SRWBn        ( SRWBn        ),
  .SBA          ( SBA          )
);

FLAGS u_FLAGS(
  .CLKSYS      ( CLKSYS      ),
  .SEB         ( SEB         ),
  .SRWB        ( SRWB        ),
  .SCRTSWn     ( SCRTSWn     ),
  // Was tied to 1'b0, which holds THREE of FLAGS' flip-flops permanently in
  // reset, because every one of them derives its async clear from this pin:
  //
  //   s0 = ~SRESETn                 -> m56_5 (SVDOFFn) stuck at 1
  //   s1 = ~(SRESETn & SIRQCLRn)    -> m45 stuck at 0, so SUBIRQn = ~m45 is
  //                                    stuck DEASSERTED and the sub CPU can
  //                                    never receive the main's attention IRQ
  //   s2 = ~SRESETn                 -> m44_5 stuck at 1
  //
  // The sub's IRQ vector is $e06e, and its handler is three instructions:
  //   $e06e  BITA $d402   (cancel-ack)
  //   $e071  LDA  #$ff
  //   $e073  STA  <$00    DP=$d0, so $d000 = $ff
  //   $e075  RTI
  // -- which is the ONLY writer of $d000, the flag the sub monitor ROM's input
  // wait at $fd76 spins on. With SUBIRQn dead that wait can never end.
  //
  // `wire SRESETn = RESETBn;` is declared at the top of this file and wired
  // correctly into SCPU at the other instantiation, so this looks like a
  // debugging leftover rather than a deliberate tie-off.
  .SRESETn     ( SRESETn     ),
  .SLEDn       ( SLEDn       ),
  .CANCELn     ( CANCELn     ),
  .SIRQCLRn    ( SIRQCLRn    ),
  .MDATABUS_in ( MDATABUS_out),
  .RESETBn     ( RESETBn     ),
  .WFD37n      ( WFD37n      ),
  .SRWBn       ( SRWBn       ),
  .SVDHALT     ( SVDHALT     ),
  .SVRACSn     ( SVRACSn     ),
  .SUBHALTREQn ( SUBHALTREQn ),
  .SBUSYSETn   ( SBUSYSETn   ),

  .SHALTSTn    ( SHALTSTn    ),
  .SHALTn      ( SHALTn      ),

  .SVDOFFn     ( SVDOFFn     ),
  .SUBIRQn     ( SUBIRQn     ),
  .BUSY        ( BUSY        ),
  .SHALTACn    ( SHALTACn    ),
  .VPAGE1n     ( VPAGE1n     ),
  .VPAGE2n     ( VPAGE2n     ),
  .VPAGE3n     ( VPAGE3n     ),
  .DPAGE1      ( DPAGE1      ),
  .DPAGE2      ( DPAGE2      ),
  .DPAGE3      ( DPAGE3      ),
  .INS         ( INS         )
);

SDECODE u_SDECODE(
  .SADDRBUS  ( SADDRBUS  ),
  .SQB       ( SQB       ),
  .SEB       ( SEB       ),
  .SBA       ( SBA       ),
  .SQANDEn   ( SQANDEn   ),
  .SRWB      ( SRWB      ),
  .VPAGE1n   ( VPAGE1n   ),
  .VPAGE2n   ( VPAGE2n   ),
  .VPAGE3n   ( VPAGE3n   ),
  .SCPUWEn   ( SCPUWEn   ),
  .SRDEn     ( SRDEn     ),
  .SROMSELn  ( SROMSELn  ),
  .SRAM1CSn  ( SRAM1CSn  ),
  .SRAM2CSn  ( SRAM2CSn  ),
  .SROMDn    ( SROMDn    ),
  .SSMEMn    ( SSMEMn    ),
  .SCRTSWn   ( SCRTSWn   ),
  .SVRACSn   ( SVRACSn   ),
  .SBUSYSETn ( SBUSYSETn ),
  .SLEDn     ( SLEDn     ),
  .SREGHn    ( SREGHn    ),
  .SREGLn    ( SREGLn    ),
  .KDATAn    ( KDATAn    ),
  .KACKNGn   ( KACKNGn   ),
  .SIRQCLRn  ( SIRQCLRn  ),
  .BUZZERn   ( BUZZERn   ),
  .ATTENTn   ( ATTENTn   ),
  .SDRAMGn   ( SDRAMGn   ),
  .SDRAMRn   ( SDRAMRn   ),
  .SDRAMBn   ( SDRAMBn   ),
  .SDRAMV1n  ( SDRAMV1n  ),
  .SDRAMV2n  ( SDRAMV2n  ),
  .SDRAMV3n  ( SDRAMV3n  )
);

SMEM u_SMEM(
  .CLKSYS       ( CLKSYS       ),
  .SADDRBUS     ( SADDRBUS     ),
  .SDATABUS_in  ( SDATABUS_out ),
  .SDATABUS_out ( SMEM_dout    ),
  .SRAM1CSn     ( SRAM1CSn     ),
  .SRAM2CSn     ( SRAM2CSn     ),
  .SWTQEn       ( SWTQEn       ),
  .SRDQEn       ( SRDQEn       ),
  .SROMSELn     ( SROMSELn     ),
  .SROMDn       ( SROMDn       ),
  .machine_av   ( machine_av   ),
  .submon_sel   ( AV_SUBMON_SEL ),
  .RESETBn      ( SRESETn      ),
  .av_d430_out  ( AV_D430_dout ),
  .av_display_page ( AV_DISPLAY_PAGE ),
  .av_active_page  ( AV_ACTIVE_PAGE  ),
  .av_vram_bank    ( AV_VRAM_BANK    )
);

// shared RAM
SRAM u_SRAM(
  .CLKSYS      ( CLKSYS       ),
  .SADDRBUS    ( SADDRBUS     ),
  .MADDRBUS    ( MADDRBUS     ),
  .SDATA_in    ( SDATABUS_out ),
  .MDATA_in    ( MDATABUS_out ),
  .SRDATA_out  ( SRDATA_out   ),
  .SHALTACn    ( SHALTACn     ),
  .RDQEn       ( RDQEn        ),
  .SRDQEn      ( SRDQEn       ),
  .WTQEn       ( WTQEn        ),
  .SWTQEn      ( SWTQEn       ),
  .SSMEMn      ( SSMEMn       ),
  .SUBSELn     ( SUBSELn      )
);

MFD u_MFD(
  .CLKSYS       ( CLKSYS       ),
  .MADDRBUS     ( MADDRBUS     ),
  .MDATABUS_out ( MDATABUS_out ),
  .MFD_out      ( MFD_out      ),
  .IOSn         ( IOSn         ),
  .EB           ( EB           ),
  .QB           ( QB           ),
  .RESETBn      ( RESETBn      ),
  .RWB          ( RWB          ),
  .EIRQn        ( EIRQn        ),
  .FD1Fn        ( FD1Fn        ),
  // .FD18_1Dn     ( FD18_1Dn     ),
  // floppy disk interface MB8877
  .FD_CSn       ( FD_CSn       ),
  .FD_Dout      ( FD_Dout      ),
  .FD_Din       ( FD_Din       ),
  .FD_RS        ( FD_RS        ),
  .FD_DRQn      ( FD_DRQn      ),
  .FD_INTRQn    ( FD_INTRQn    ),
  .FD_MRn       ( FD_MRn       ),
  .FD_WEn       ( FD_WEn       ),
  .FD_REn       ( FD_REn       )
);

FDC u_FDC(
  .CLKSYS    ( CLKSYS    ),
  .FD_MRn    ( FD_MRn    ),
  .FD_Din    ( FD_Dout   ),
  .FD_Dout   ( FD_Din    ),
  .FD_RS     ( FD_RS     ),
  .FD_DRQn   ( FD_DRQn   ),
  .FD_INTRQn ( FD_INTRQn ),
  .FD_CSn    ( FD_CSn    ),
  .FD_WEn    ( FD_WEn    ),
  .FD_REn    ( FD_REn    ),

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


RS232 RS232(
  .MADDRBUS  ( MADDRBUS   ),
  .RS232_CEn ( RS232_CEn  ),
  .dout      ( RS232_dout )
);

CRTRAM u_CRTRAM(
  .CLKSYS     ( CLKSYS       ),
  .SDATABUS   ( SDATABUS_out ),
  .CRTRAMDATA ( CRTRAMDATA   ),
  .SVWEn      ( SVWEn        ),
  .SCASSEL    ( SCASSEL      ),
  .SVRADRS    ( SVRADRS      ),
  .AV_DISPLAY_PAGE ( AV_DISPLAY_PAGE ),
  .AV_ACTIVE_PAGE  ( AV_ACTIVE_PAGE  ),
  .AV_VRAM_BANK    ( AV_VRAM_BANK    ),
  .SVCASBn    ( SVCASBn      ),
  .SVCASRn    ( SVCASRn      ),
  .SVCASGn    ( SVCASGn      ),
  .AV_VRAM_SEL    ( AV_VRAM_SEL    ),
  .AV_VRAM_PLANE  ( AV_VRAM_PLANE  ),
  .AV_VRAM_ADDR   ( AV_VRAM_ADDR   ),
  .AV_VRAM_WRITE  ( AV_VRAM_WRITE  ),
  .AV_VRAM_DIN    ( AV_VRAM_DIN    ),
  .AV_VRAM_DOUT   ( AV_VRAM_DOUT   ),
  .SDRAMBn    ( SDRAMBn      ),
  .SDRAMRn    ( SDRAMRn      ),
  .SDRAMGn    ( SDRAMGn      ),
  .SVDATAB    ( SVDATAB      ),
  .SVDATAR    ( SVDATAR      ),
  .SVDATAG    ( SVDATAG      )
);

SUBCRTADDR u_SUBCRTADDR(
  .SDRAMV1n ( SDRAMV1n ),
  .SDRAMV2n ( SDRAMV2n ),
  .SDRAMV3n ( SDRAMV3n ),
  .SBLANKn  ( SBLANKn  ),
  .SCASSEL  ( SCASSEL  ),
  .SRWB     ( SRWB     ),
  .SVCASBn  ( SVCASBn  ),
  .SVCASRn  ( SVCASRn  ),
  .SVCASGn  ( SVCASGn  ),
  .SVWEn    ( SVWEn    ),
  .SADRSEL  ( SADRSEL  )
);

MB60H010 u_MB60H010(
  .SRESETn   ( SRESETn   ),
  .CLKSYS    ( CLKSYS    ),
  .SADDRBUS  ( SADDRBUS  ),
  .SDATA     ( SDATABUS_out ),
  .AV_MODE_320 ( AV_MODE_320 ),
  .SREGLn    ( SREGLn    ),
  .SREGHn    ( SREGHn    ),
  .SADRSEL   ( SADRSEL   ),
  .SFTCLK    ( SFTCLK    ),
  .SCLK1     ( SCLK1     ),
  .SCLK2     ( SCLK2     ),
  .SVRADRS   ( SVRADRS   ),
  .VRAM_OFFSET ( AV_VRAM_OFFSET ),
  .SFTSTEP   ( SFTSTEP   ),
  .SVIDEOCLK ( SVIDEOCLK ),
  .SVSYNCn   ( SVSYNCn   ),
  .SHSYNCn   ( SHSYNCn   ),
  .SVDHALT   ( SVDHALT   ),
  .SFTLODn   ( SFTLODn   ),
  .SBLANKn   ( SBLANKn   ),
  .SCSYNCn   ( SCSYNCn   ),
  .SCASSEL   ( SCASSEL   ),
  .VBLANKn   ( VBLANKn   ),
  .HBLANKn   ( HBLANKn   )
);

PAL PAL(
  .CLKSYS   ( CLKSYS       ),
  .SVDOFFn  ( SVDOFFn      ),
  .SBLANKn  ( SBLANKn      ),
  .SVDATAB  ( SVDATAB      ),
  .SVDATAR  ( SVDATAR      ),
  .SVDATAG  ( SVDATAG      ),
  .SFTCLK   ( SFTCLK       ),
  .machine_av ( machine_av ),
  .AV_MODE_320 ( AV_MODE_320 ),
  .SFTSTEP  ( SFTSTEP      ),
  .SFTLODn  ( SFTLODn      ),
  .DPAGE1   ( DPAGE1       ),
  .DPAGE2   ( DPAGE2       ),
  .DPAGE3   ( DPAGE3       ),
  .MDATA    ( MDATABUS_out ),
  .PALDATA  ( PALDATA      ),
  .MADDRBUS ( MADDRBUS     ),
  .PLTREGn  ( PLTREGn      ),
  .RDQEn    ( RDQEn        ),
  .WTQEn    ( WTQEn        ),
  .RESETBn  ( RESETBn      ),
  .grb      ( grb          ),
  .ANALOG_CODE ( 12'd0     ),
  .ANALOG_RGB  ( AV_ANALOG_RGB )
);

KEYBOARD KEYBOARD(
  .CLKSYS     ( CLKSYS       ),
  .RESETBn    ( RESETBn      ),
  .ps2_key    ( ps2_key      ),
  .MDATA_in   ( MDATABUS_out ),
  .SKDATA     ( SKDATA       ),
  .MKDATA     ( MKDATA       ),
  .KDATAn     ( KDATAn       ),
  .KACKNGn    ( KACKNGn      ),
  .RFD00n     ( RFD00n       ),
  .RFD01n     ( RFD01n       ),
  .EB         ( EB           ),
  .SEB        ( SEB          ),
  .SCLK2      ( SCLK2        ),
  .WFD02n     ( WFD02n       ),
  .KSTROBEn   ( KSTROBEn     ),
  .BREAKn     ( BREAKn       ),
  .fm8_switch ( fm8_switch   ),
  .LPMASKn    ( LPMASKn      ),
  .TMMASK     ( TMMASK       ),
  .KEYINn     ( KEYINn       )
);


SOUND u_SOUND(
  .CLKSYS       ( CLKSYS       ),
  .CLK1_2       ( CLK1_2       ),
  .RESETBn      ( RESETBn      ),
  .MDATABUS_in  ( MDATABUS_out ),
  .MDATABUS_out ( SOUND_dout   ),
  .RFD0En       ( RFD0En       ),
  .WFD0En       ( WFD0En       ),
  .WFD0Dn       ( WFD0Dn       ),
  .joystick_0   ( joystick_0   ),
  .joystick_1   ( joystick_1   ),
  .mix_audio_o  ( audio_out    )
);


endmodule
