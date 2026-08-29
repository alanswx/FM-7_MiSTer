#============================================================================
#  FM-7 Verilator simulation
#
#  Modelled on the RX-78 vsim Makefile (which in turn came from Apple-IIgs).
#
#    make            build ./obj_dir/Vemu
#    make run        build and launch the windowed sim
#    make test       build and run the headless regression (run_tests.sh)
#    make clean
#
#  Both CPUs are mc6809i (Verilog), so there is no VHDL and no ghdl step.
#  rtl/MRAM.v selects the generic `ram` model under `ifdef VERILATOR` instead
#  of the Quartus altsyncram wrapper; Verilator predefines VERILATOR.
#============================================================================

V     = verilator
RTL   = ../rtl
TOP   = --top-module emu
V_INC = +incdir+$(RTL)

# Verilator flags.
#   -Wno-fatal            : the core has plenty of width/latch/case warnings;
#                           they are pre-existing and not what the sim is for.
#   --converge-limit      : the video chain (MB60H010 -> SUBCRTADDR -> CRTRAM
#                           -> PAL) settles through several combinational
#                           layers and needs more than the default passes.
#   +define+SIMULATION=1  : matches the RX-78/IIgs convention; available if the
#                           RTL ever needs a sim-only branch.
#   --no-timing           : mc6809i.v and the 74xx models carry cosmetic `#`
#                           delays. They are ignored by synthesis, so ignoring
#                           them here matches the FPGA build. Verilator 5
#                           refuses to guess and demands the flag -- but 4.x
#                           ignores those delays by default and ERRORS OUT on
#                           the flag ("Invalid option: --no-timing"), which
#                           made the whole sim unbuildable on a v4 box. Pass it
#                           only to the versions that want it.
VERILATOR_MAJOR := $(shell verilator --version 2>/dev/null | sed -n 's/^Verilator \([0-9][0-9]*\).*/\1/p')
NO_TIMING       := $(if $(filter 4,$(VERILATOR_MAJOR)),,--no-timing)

V_DEFINE = +define+SIMULATION=1 \
	-CFLAGS "-I../sim/imgui -I../sim/vinc -I../sim/ -g" \
	--timescale-override 1ps/1ps -Wno-TIMESCALEMOD -Wno-fatal \
	$(NO_TIMING) --converge-limit 6000 \
	-I$(RTL)

# VCD tracing: `make clean && make TRACE=1`, then run with --vcd <file>.
#
# The clean matters. These flags are baked in when Verilator generates the
# model, so a plain `make TRACE=1` over an existing build silently keeps the
# old ones and --vcd reports that it needs a TRACE=1 build.
#
# The dump obeys --trace-from/--trace-until, and you want a window: two frames
# of a 48 MHz design is about 700 MB, so a whole run is unusable. Find the frame
# of interest with the text traces first, then dump a few frames around it.
#
#   make clean && make TRACE=1
#   ./obj_dir/Vemu --headless --disk foo.d77 --stop-at-frame 2680 \
#       --trace-from 2667 --trace-until 2669 --vcd /tmp/stall.vcd
#
# Worth reaching for once a bug has survived two rounds of $display: three
# rounds of printf on TODO.md P4-5 produced two confident wrong answers, and one
# waveform settled it. Costs runtime even when not dumping, so it is opt-in.
ifeq ($(TRACE),1)
V_DEFINE += --trace
CXX_DEFINE += -DVM_TRACE_VCD=1
else
CXX_DEFINE += -DVM_TRACE_VCD=0
endif

# IMPORTANT, applies to every flag below as well as TRACE above: these become
# `+define+` arguments to Verilator, and Verilator only re-reads them when it
# re-runs. `make DEBUG_FDC=1` straight after a plain `make` will happily relink
# the old model with the old defines and your instrumentation will silently not
# be there -- you get a clean build, a clean run, and no output. Touch a file in
# the flag's target module (or `make clean`) when turning one on:
#
#   touch ../rtl/SRAM.v && make DEBUG_SRAM=1
#
# Check it took before trusting a null result:
#
#   grep -l SRAMSUM obj_dir/*.cpp
#
# rtl/MB60H010.v has a per-pixel-clock $display left over from bring-up. It is
# behind `ifdef DEBUG_MB60H010`; `make DEBUG_VIDEO=1` turns it back on. Do not
# do that for a full run -- it is 16 million lines per simulated second.
ifeq ($(DEBUG_VIDEO),1)
V_DEFINE += +define+DEBUG_MB60H010
endif

# `make DEBUG_FDC=1` turns on the floppy tracing in rtl/wd1793.sv and rtl/FDC.v:
#
#   D77SEC <track> <side> <C> <H> <R> <N> <data offset> <crc flags>
#         one line per sector the mount-time scanner puts in the table (1265 of
#         them for the Thexder image), in a form that can be diffed straight
#         against a reference parse of the same file
#   D77SCAN done: ...
#         the summary: format, bytes consumed, tracks, sectors, write protect
#   FDCW reg<n> <- <byte>
#         every register write that reaches the controller. If a boot ROM looks
#         like it is doing nothing, check here first -- these went missing
#         entirely until the bus-to-ce crossing in FDC.v was written
#   WDCMD <byte> accepted=<0|1>
#         every command the controller latched
#
# All of it is low volume except D77SEC. See TODO.md P4-1.
# `make DEBUG_JOY=1` prints one line per PSG port-B write (stick selection) and
# per port-A read (the byte handed back), from rtl/SOUND.v.
# `make DEBUG_MMR=1` prints all four MMR segment maps whenever any of them
# changes -- the counterpart of FM77AV_MMR_DUMP on the reference harness.
ifeq ($(DEBUG_MMR),1)
V_DEFINE += +define+DEBUG_MMR
endif

ifeq ($(DEBUG_JOY),1)
V_DEFINE += +define+DEBUG_JOY
endif

# `make JT12_RAW=1` turns on jt12's own raw-audio dump, which writes
# vsim/jt12.raw from jt12_top.v. Upstream guards it with `SIMULATION`, which
# this Makefile defines unconditionally, so it had to be moved behind its own
# define -- otherwise every run of every test silently grew that file.
ifeq ($(JT12_RAW),1)
V_DEFINE += +define+JT12_DUMP_RAW
endif

ifeq ($(DEBUG_FDC),1)
V_DEFINE += +define+DEBUG_FDC_SCAN
endif

# `make DEBUG_AVDRAW=1` prints one line per MB61VH010 register write accepted by
# rtl/AVHDRAW.v, whichever CPU made it:
#
#   AVDRAW W $d4<reg> <- $<byte>
#
# The point is that 77AVEMU's --trace-io logs the same writes as
# `IOWRITE SUB: .... IO:D4xx VALUE:xx by Main CPU`, so the two are directly
# comparable. A title that halts the sub CPU and drives the ALU itself through
# the MMR aperture -- Woody Poco does -- is otherwise invisible to --trace-io,
# which only sees $fdxx. Touch ../rtl/AVHDRAW.v before building or the define
# does not reach Verilator (trap 3).
ifeq ($(DEBUG_AVDRAW),1)
V_DEFINE += +define+DEBUG_AVDRAW
endif

# `make DEBUG_PAL=1` prints one line per write to the eight-entry digital
# palette, with the CPU write strobe alongside:
#
#   PALW idx=<n> <- <value>  WTQEn=<n> RDQEn=<n> addr=$fd3x
#
# WTQEn HIGH on that line means the CPU was NOT writing, i.e. the entry was
# clobbered by a read or by a cycle that merely decoded $fd3x. Touch
# ../rtl/PAL.v before building or the define does not reach Verilator (trap 3).
ifeq ($(DEBUG_PAL),1)
V_DEFINE += +define+DEBUG_PAL
endif

# `make DEBUG_FDC_READ=1` prints one line per byte the controller hands the CPU
# during a sector read, plus the buffer base chosen for each sector:
#
#   FDCSEC start: buff_a=<addr> base=<offset in the fetched blocks> ...
#   FDCRD byte_addr=<n> buff_dout=<byte> ...
#
# Written to settle whether the FIRST byte of every sector is lost because the
# read pointer is wrong or because the SD block fetch has not landed in the
# buffer when DRQ is first raised -- reading the RTL eliminated the obvious
# candidates for both. Touch ../rtl/wd1793.sv before building or the define does
# not reach Verilator (trap 3).
ifeq ($(DEBUG_FDC_READ),1)
V_DEFINE += +define+DEBUG_FDC_READ
endif

# `make DEBUG_SRAM=1` instruments the main/sub shared-RAM aperture in rtl/SRAM.v:
#
#   SRAMBAD main write $<addr> <- $<byte> with SHALTACn HIGH ...
#         a main-side write into $fc80-$fcff issued while the sub CPU has not
#         acknowledged the halt. The write still happens -- `wr_n` is gated by
#         SUBSELn/WTQEn, not by SHALTACn -- but the address/data mux is still
#         pointed at the sub, so it lands on whatever the sub is addressing.
#   SRAMSUM accepted=<n> misdirected=<n>
#         printed at the end. Both references discard a main-side write unless
#         the sub is halted (MAME `main_shared_w`, CSP `mainmem_writeseq.cpp:32`).
ifeq ($(DEBUG_SRAM),1)
V_DEFINE += +define+DEBUG_SRAM
endif

# `make DEBUG_TAPE=1` prints, from rtl/t77_decode.v, the first 24 T77 entries as
# they are actually latched out of SDRAM, then a summary:
#
#   T77 entry <n> addr=$<a> data=$<w> -> level=<0|1> len=<ticks>
#   T77SUM entries=<n> summed_len=<ticks> ticks_elapsed=<clk_9us periods>
#
# `len` is in 9.125 us ticks: a 1200 baud half-bit is ~47, a 2400 baud one ~25.
# summed_len should match the sum of the durations in the .t77, and
# ticks_elapsed should be close to it -- if it is far smaller, the tape is
# playing faster than the image says it should.
ifeq ($(DEBUG_TAPE),1)
V_DEFINE += +define+DEBUG_TAPE
endif

# `make DEBUG_ACK=1` logs every transition of the main/sub read-side-effect
# decodes, including the bus phase. This is intentionally separate from the
# normal trace options: the question is the shape of the decode strobe, not
# merely which addresses software accessed.
ifeq ($(DEBUG_ACK),1)
V_DEFINE += +define+DEBUG_ACK
endif

# `make DEBUG_SCROLL=1` prints one line per change of either page's raster
# offset, from rtl/MB60H010.v:
#
#   SCROLL page0=<hhhh> page1=<hhhh>  active=<n> display=<n>
#
# The AV keeps a scroll offset PER PAGE ($D40E/$D40F select by $D430 bit 5), and
# in 320-colour mode blocks 0/1 read at page 0's while blocks 2/3 read at page
# 1's -- so the two halves of every 12-bit colour index can come from different
# addresses. Written to check whether a title that scrolls one page only is
# being served mismatched halves.
ifeq ($(DEBUG_SCROLL),1)
V_DEFINE += +define+DEBUG_SCROLL
endif

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S), Darwin)
	LIBS += -framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo `sdl2-config --libs`
	LIBS += -L/usr/local/lib -L/opt/local/lib -L/opt/homebrew/lib
	CXXFLAGS += `sdl2-config --cflags`
	CXXFLAGS += `sdl2-config --cflags | sed 's|include/SDL2|include/|'`
	CXXFLAGS += -I/usr/local/include -I/opt/local/include -I/opt/homebrew/include
endif

ifeq ($(UNAME_S), Linux)
	LIBS += -lGL -ldl `sdl2-config --libs`
	CXXFLAGS += `sdl2-config --cflags`
endif

ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
	LIBS += -lgdi32 -lopengl32 -limm32 `pkg-config --static --libs sdl2`
	CXXFLAGS += `pkg-config --cflags sdl2`
endif

CC_OPT    = -O2
V_OPT     = -O3 --x-assign fast --x-initial fast --noassert
CXXFLAGS += $(CC_OPT) $(CXX_DEFINE) -Isim/imgui -Isim
LDFLAGS   = $(LIBS)
EXE       = ./obj_dir/Vemu

# Core RTL.
#
# rtl/rom.v does $readmemh("./roms/<name>.rom.mem"), relative to the working
# directory, so `roms` here is a symlink to ../rtl/roms and the binary must be
# run from this directory.
#
# clocks.svh is compiled as a source, not included: it declares its localparams
# at compilation-unit scope and MB60H010.v/t77_decode.v/pcm.v read them from
# there. That is how the Quartus build resolves them too.
#
# vsim/rtl/sdram.sv replaces rtl/sdram.sv -- the real controller drives SDRAM_*
# pins that do not exist here.
JT12_SRC = ../rtl/jt12/jt03.v \
	../rtl/jt12/jt03_acc.v \
	../rtl/jt12/jt12_csr.v \
	../rtl/jt12/jt12_div.v \
	../rtl/jt12/jt12_dout.v \
	../rtl/jt12/jt12_eg.v \
	../rtl/jt12/jt12_eg_cnt.v \
	../rtl/jt12/jt12_eg_comb.v \
	../rtl/jt12/jt12_eg_ctrl.v \
	../rtl/jt12/jt12_eg_final.v \
	../rtl/jt12/jt12_eg_pure.v \
	../rtl/jt12/jt12_eg_step.v \
	../rtl/jt12/jt12_exprom.v \
	../rtl/jt12/jt12_kon.v \
	../rtl/jt12/jt12_lfo.v \
	../rtl/jt12/jt12_logsin.v \
	../rtl/jt12/jt12_mmr.v \
	../rtl/jt12/jt12_mod.v \
	../rtl/jt12/jt12_op.v \
	../rtl/jt12/jt12_pg.v \
	../rtl/jt12/jt12_pg_comb.v \
	../rtl/jt12/jt12_pg_dt.v \
	../rtl/jt12/jt12_pg_inc.v \
	../rtl/jt12/jt12_pg_sum.v \
	../rtl/jt12/jt12_pm.v \
	../rtl/jt12/jt12_reg.v \
	../rtl/jt12/jt12_reg_ch.v \
	../rtl/jt12/jt12_rst.v \
	../rtl/jt12/jt12_sh.v \
	../rtl/jt12/jt12_sh24.v \
	../rtl/jt12/jt12_sh_rst.v \
	../rtl/jt12/jt12_single_acc.v \
	../rtl/jt12/jt12_sumch.v \
	../rtl/jt12/jt12_timers.v \
	../rtl/jt12/jt12_top.v \
	../rtl/jt12/jt49/jt49.v \
	../rtl/jt12/jt49/jt49_bus.v \
	../rtl/jt12/jt49/jt49_cen.v \
	../rtl/jt12/jt49/jt49_dcrm.v \
	../rtl/jt12/jt49/jt49_dcrm2.v \
	../rtl/jt12/jt49/jt49_div.v \
	../rtl/jt12/jt49/jt49_dly.v \
	../rtl/jt12/jt49/jt49_eg.v \
	../rtl/jt12/jt49/jt49_exp.v \
	../rtl/jt12/jt49/jt49_mave.v \
	../rtl/jt12/jt49/jt49_noise.v

V_SRC = \
	sim.v \
	rtl/sdram.sv \
	$(RTL)/clocks.svh \
	$(RTL)/clk_en.v \
	$(RTL)/CLKCTRL.v \
	$(RTL)/AVMEM.v \
	$(RTL)/AVHDRAW.v \
	$(RTL)/SDRAM_MUX.v \
	$(RTL)/AVPIXEL.v \
	$(RTL)/core.v \
	$(RTL)/CRTRAM.v \
	$(RTL)/FDC.v \
	$(RTL)/FLAGS.v \
	$(RTL)/KEYBOARD.v \
	$(RTL)/AVKEYBOARD.v \
	$(RTL)/KANJI.v \
	$(RTL)/m139.v \
	$(RTL)/MB60H010.v \
	$(RTL)/mc6809i.v \
	$(RTL)/mc6809s.v \
	$(RTL)/MCPU.v \
	$(RTL)/MDECODE.v \
	$(RTL)/MFD.v \
	$(RTL)/MRAM.v \
	$(RTL)/PAL.v \
	$(RTL)/pcm.v \
	$(RTL)/PERIPHERAL.v \
	$(RTL)/ram.v \
	$(RTL)/rom.v \
	$(RTL)/ROMS.v \
	$(RTL)/RS232.v \
	$(RTL)/SCPU.v \
	$(RTL)/SDECODE.v \
	$(RTL)/SMEM.v \
	$(RTL)/SOUND.v \
	$(RTL)/SRAM.v \
	$(RTL)/SUBCRTADDR.v \
	$(RTL)/t77_decode.v \
	$(RTL)/TIMER.v \
	$(RTL)/x74138.v \
	$(RTL)/x74139.v \
	$(RTL)/x74244.v \
	$(RTL)/wd1793.sv \
	$(RTL)/wd1793_dpram.v \
	$(RTL)/jt12/jt03.v \
	$(RTL)/jt12/jt03_acc.v \
	$(RTL)/jt12/jt12_csr.v \
	$(RTL)/jt12/jt12_div.v \
	$(RTL)/jt12/jt12_dout.v \
	$(RTL)/jt12/jt12_eg.v \
	$(RTL)/jt12/jt12_eg_cnt.v \
	$(RTL)/jt12/jt12_eg_comb.v \
	$(RTL)/jt12/jt12_eg_ctrl.v \
	$(RTL)/jt12/jt12_eg_final.v \
	$(RTL)/jt12/jt12_eg_pure.v \
	$(RTL)/jt12/jt12_eg_step.v \
	$(RTL)/jt12/jt12_exprom.v \
	$(RTL)/jt12/jt12_kon.v \
	$(RTL)/jt12/jt12_lfo.v \
	$(RTL)/jt12/jt12_logsin.v \
	$(RTL)/jt12/jt12_mmr.v \
	$(RTL)/jt12/jt12_mod.v \
	$(RTL)/jt12/jt12_op.v \
	$(RTL)/jt12/jt12_pg.v \
	$(RTL)/jt12/jt12_pg_comb.v \
	$(RTL)/jt12/jt12_pg_dt.v \
	$(RTL)/jt12/jt12_pg_inc.v \
	$(RTL)/jt12/jt12_pg_sum.v \
	$(RTL)/jt12/jt12_pm.v \
	$(RTL)/jt12/jt12_reg.v \
	$(RTL)/jt12/jt12_reg_ch.v \
	$(RTL)/jt12/jt12_rst.v \
	$(RTL)/jt12/jt12_sh.v \
	$(RTL)/jt12/jt12_sh24.v \
	$(RTL)/jt12/jt12_sh_rst.v \
	$(RTL)/jt12/jt12_single_acc.v \
	$(RTL)/jt12/jt12_sumch.v \
	$(RTL)/jt12/jt12_timers.v \
	$(RTL)/jt12/jt12_top.v \
	$(RTL)/jt12/jt49/jt49.v \
	$(RTL)/jt12/jt49/jt49_bus.v \
	$(RTL)/jt12/jt49/jt49_cen.v \
	$(RTL)/jt12/jt49/jt49_dcrm.v \
	$(RTL)/jt12/jt49/jt49_dcrm2.v \
	$(RTL)/jt12/jt49/jt49_div.v \
	$(RTL)/jt12/jt49/jt49_dly.v \
	$(RTL)/jt12/jt49/jt49_eg.v \
	$(RTL)/jt12/jt49/jt49_exp.v \
	$(RTL)/jt12/jt49/jt49_mave.v \
	$(RTL)/jt12/jt49/jt49_noise.v

C_SRC = \
	sim_main.cpp dis6809.cpp \
	sim/sim_bus.cpp sim/sim_clock.cpp sim/sim_console.cpp sim/sim_video.cpp \
	sim/sim_blkdevice.cpp \
	sim/sim_input.cpp sim/sim_audio.cpp \
	sim/imgui/imgui_impl_sdl.cpp sim/imgui/imgui_impl_opengl2.cpp \
	sim/imgui/imgui_draw.cpp sim/imgui/imgui_widgets.cpp sim/imgui/imgui_tables.cpp \
	sim/imgui/imgui.cpp sim/imgui/ImGuiFileDialog.cpp \
	sim/imgui/implot.cpp sim/imgui/implot_items.cpp

VOUT = obj_dir/Vemu.cpp

all: $(EXE)

$(VOUT): $(V_SRC) Makefile
	$V -cc $(V_OPT) -LDFLAGS "$(LDFLAGS)" -exe --Mdir ./obj_dir \
		$(V_DEFINE) $(V_INC) $(TOP) -CFLAGS "$(CXXFLAGS)" $(V_SRC) $(C_SRC)

$(EXE): $(VOUT) $(C_SRC)
	(cd obj_dir; $(MAKE) -f Vemu.mk OBJCACHE= OPT_FAST="-O2" OPT_SLOW="-O0" OPT_GLOBAL="-O2")

run: all
	$(EXE)

test: all
	./run_tests.sh

clean:
	rm -rf obj_dir

# Remove generated screenshots but keep the reference set.
clean-shots:
	rm -f screenshot_*.png shots/*.png

# Directed AV memory-map check. It runs independently of the full machine so
# address-map failures remain easy to localize from the boot smoke test.
avmem-test: avmem_tb.sv ../rtl/AVMEM.v ../rtl/wd1793_dpram.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-avmem-obj \
		--top-module avmem_tb avmem_tb.sv ../rtl/AVMEM.v ../rtl/wd1793_dpram.v
	/tmp/fm7-avmem-obj/Vavmem_tb

# Directed check for the shared AV main-CPU / raster VRAM port.
crtram-test: crtram_tb.sv ../rtl/CRTRAM.v ../rtl/wd1793_dpram.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-crtram-obj \
		--top-module crtram_tb crtram_tb.sv ../rtl/CRTRAM.v ../rtl/wd1793_dpram.v
	/tmp/fm7-crtram-obj/Vcrtram_tb

# Kanji ROM readback: the 128 KB image moved from block RAM to SDRAM, so this
# checks the boot.rom download, the base address and the arbiter all line up.
# Nothing else does -- no title in the suite reads the kanji window.
kanji-test: all
	./obj_dir/Vemu --headless --bootrom 0 --stop-at-frame 30 --kanji-check 20 \
		| grep "KANJI CHECK" | tee /dev/stderr | grep -q " 0 mismatched"

# Directed check that a PSG register write reaches the chip and makes sound.
# A full-machine run is a ten-minute experiment; this is seconds, which is the
# only way to iterate the $fd0d/$fd0e bus handshake.
sound-test: sound_tb.sv ../rtl/SOUND.v ../rtl/clk_en.v ../rtl/clocks.svh $(JT12_SRC)
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-sound-obj -I../rtl \
		--top-module sound_tb sound_tb.sv ../rtl/clocks.svh ../rtl/SOUND.v \
		../rtl/clk_en.v $(JT12_SRC)
	/tmp/fm7-sound-obj/Vsound_tb

# Directed check for the FM77AV MB61VH010 drawing ALU.  The byte
# read-modify-write path is the one the 2019 AV demo actually uses.
avhdraw-test: avhdraw_tb.sv ../rtl/AVHDRAW.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-avhdraw-obj \
		--top-module avhdraw_tb avhdraw_tb.sv ../rtl/AVHDRAW.v
	/tmp/fm7-avhdraw-obj/Vavhdraw_tb

# Directed check for the FM77AV keyboard encoder command/status pair.
avkeyboard-test: avkeyboard_tb.sv ../rtl/AVKEYBOARD.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-avkeyboard-obj \
		--top-module avkeyboard_tb avkeyboard_tb.sv ../rtl/AVKEYBOARD.v
	/tmp/fm7-avkeyboard-obj/Vavkeyboard_tb

# Directed check for the AV character-generator aperture and $D430 bank.
smem-test: smem-test.sv ../rtl/SMEM.v ../rtl/ram.v ../rtl/rom.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-smem-obj \
		--top-module smem_tb smem-test.sv ../rtl/SMEM.v ../rtl/ram.v ../rtl/rom.v
	/tmp/fm7-smem-obj/Vsmem_tb

# Directed check for the AV mode-aware raster address and doubled 320-pixel
# shift cadence. It exercises the timing/address front end independently of
# the still-pending 12-plane analog compositor.
mb60h010-test: mb60h010_tb.sv ../rtl/MB60H010.v ../rtl/clk_en.v ../rtl/clocks.svh
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-mb60-obj \
		-I../rtl --top-module mb60h010_tb mb60h010_tb.sv ../rtl/clocks.svh \
		../rtl/MB60H010.v ../rtl/clk_en.v
	/tmp/fm7-mb60-obj/Vmb60h010_tb

# Directed check for the FM77AV analog palette registers at $FD30-$FD34.
pal-test: pal_tb.sv ../rtl/PAL.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-pal-obj \
		--top-module PAL_tb pal_tb.sv ../rtl/PAL.v
	/tmp/fm7-pal-obj/VPAL_tb

# Reference-matched 12-plane pixel-code combiner check.
avpixel-test: avpixel_tb.sv ../rtl/AVPIXEL.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-avpixel-obj \
		--top-module AVPIXEL_tb avpixel_tb.sv ../rtl/AVPIXEL.v
	/tmp/fm7-avpixel-obj/VAVPIXEL_tb

# AV reset-vector and first-frame smoke test. The checker requires both CPUs to
# retire instructions and the raster to produce a frame; it does not bless a
# screenshot, so it remains valid while the AV display is still evolving.
av-boot-test: all av_boot_test.sh
	bash av_boot_test.sh

.PHONY: all run test clean clean-shots avmem-test crtram-test avkeyboard-test smem-test mb60h010-test pal-test avpixel-test avhdraw-test sound-test kanji-test av-boot-test

# Disassembler self-check. Standalone -- no Verilator, no core.
distest: dis6809_test.cpp dis6809.cpp dis6809.h
	c++ -O1 -o obj_dir/distest dis6809_test.cpp dis6809.cpp -I. && ./obj_dir/distest

.PHONY: distest

# `make DEBUG_D430=1` prints one line per $D430 write latched in rtl/SMEM.v:
#
#   D430W <- $a5  displayPage=0 activePage=1 nmimask=1
#
# $D430 bit 6 selects the DISPLAYED VRAM bank and bit 5 the one the CPU draws
# into, so a title that double-buffers -- Ys II writes $85/$a5/$85 in a loop
# from sub RAM at $c06b/$c071/$c078 -- is invisible in a main-CPU $fdxx trace.
# 77AVEMU logs the same writes as `IOWRITE SUB: .... IO:D430 VALUE:xx by Sub
# CPU`, so the two are directly comparable. Touch ../rtl/SMEM.v before building
# or the define does not reach Verilator (trap 3).
ifeq ($(DEBUG_D430),1)
V_DEFINE += +define+DEBUG_D430
endif

# `make DEBUG_VBLOCK=1` counts sub-CPU VRAM writes per 8 KB block in
# rtl/CRTRAM.v and prints one line per gun at exit:
#
#   VBLOCK plane0: blk0=0 blk1=0 blk2=54321 blk3=12345  pagebit0=0 pagebit1=66666
#
# block = {page, SVRADRS[13]}, so blocks 0/1 are VRAM bank 0 and 2/3 are bank 1.
# A title that double-buffers must write both banks. It turns "bank 0 is empty
# in the dump" into "the page bit was never 0 at write time", which separates a
# page-select fault from a drawing fault. Touch ../rtl/CRTRAM.v before building
# or the define does not reach Verilator (trap 3).
ifeq ($(DEBUG_VBLOCK),1)
V_DEFINE += +define+DEBUG_VBLOCK
endif
