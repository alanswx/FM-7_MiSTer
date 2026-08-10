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
ifeq ($(DEBUG_JOY),1)
V_DEFINE += +define+DEBUG_JOY
endif

ifeq ($(DEBUG_FDC),1)
V_DEFINE += +define+DEBUG_FDC_SCAN
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
V_SRC = \
	sim.v \
	rtl/sdram.sv \
	$(RTL)/clocks.svh \
	$(RTL)/clk_en.v \
	$(RTL)/CLKCTRL.v \
	$(RTL)/AVMEM.v \
	$(RTL)/AVPIXEL.v \
	$(RTL)/core.v \
	$(RTL)/CRTRAM.v \
	$(RTL)/FDC.v \
	$(RTL)/FLAGS.v \
	$(RTL)/KEYBOARD.v \
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
	$(RTL)/ym2149_audio.v

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
avmem-test: avmem_tb.sv ../rtl/AVMEM.v ../rtl/ram.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-avmem-obj \
		--top-module avmem_tb avmem_tb.sv ../rtl/AVMEM.v ../rtl/ram.v
	/tmp/fm7-avmem-obj/Vavmem_tb

# Directed check for the shared AV main-CPU / raster VRAM port.
crtram-test: crtram_tb.sv ../rtl/CRTRAM.v ../rtl/wd1793_dpram.v
	verilator --binary --timing -Wno-fatal --Mdir /tmp/fm7-crtram-obj \
		--top-module crtram_tb crtram_tb.sv ../rtl/CRTRAM.v ../rtl/wd1793_dpram.v
	/tmp/fm7-crtram-obj/Vcrtram_tb

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

.PHONY: all run test clean clean-shots avmem-test crtram-test smem-test mb60h010-test pal-test avpixel-test av-boot-test

# Disassembler self-check. Standalone -- no Verilator, no core.
distest: dis6809_test.cpp dis6809.cpp dis6809.h
	c++ -O1 -o obj_dir/distest dis6809_test.cpp dis6809.cpp -I. && ./obj_dir/distest

.PHONY: distest
