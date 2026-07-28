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
#                           refuses to guess and demands the flag.
V_DEFINE = +define+SIMULATION=1 \
	-CFLAGS "-I../sim/imgui -I../sim/vinc -I../sim/ -g" \
	--timescale-override 1ps/1ps -Wno-TIMESCALEMOD -Wno-fatal \
	--no-timing --converge-limit 6000 \
	-I$(RTL)

# VCD tracing: `make TRACE=1`, then look at obj_dir/*.vcd. Costs runtime even
# when not dumping, so it is opt-in.
ifeq ($(TRACE),1)
V_DEFINE += --trace
CXX_DEFINE += -DVM_TRACE_VCD=1
else
CXX_DEFINE += -DVM_TRACE_VCD=0
endif

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
	$(RTL)/core.v \
	$(RTL)/CRTRAM.v \
	$(RTL)/FDC.v \
	$(RTL)/FLAGS.v \
	$(RTL)/KEYBOARD.v \
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

.PHONY: all run test clean clean-shots

# Disassembler self-check. Standalone -- no Verilator, no core.
distest: dis6809_test.cpp dis6809.cpp dis6809.h
	c++ -O1 -o obj_dir/distest dis6809_test.cpp dis6809.cpp -I. && ./obj_dir/distest

.PHONY: distest
