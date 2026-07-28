//============================================================================
//  FM-7 Verilator simulation
//
//  Two modes:
//    windowed  - ImGui/SDL front end with the video output, a main/sub CPU and
//                video register inspector, and a console. For poking at things
//                by hand.
//    headless  - no SDL at all. Runs a fixed number of frames, optionally
//                injecting keys at given frames and writing PNGs. This is what
//                run_tests.sh drives.
//
//  Everything schedulable is expressed in *frames*, not cycles, because frames
//  stay meaningful across changes to the clocking. A cycle-based schedule has
//  to be rewritten every time a divider moves.
//============================================================================

#include <verilated.h>
#include "Vemu.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <algorithm>

#include "sim_console.h"
#include "sim_bus.h"
#include "sim_video.h"
#include "sim_input.h"
#include "sim_audio.h"
#include "sim_blkdevice.h"
#include "dis6809.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#ifndef _MSC_VER
#include <SDL.h>
#include <SDL_opengl.h>
#endif

//----------------------------------------------------------------------------
// Machine constants
//----------------------------------------------------------------------------

// rtl/MB60H010.v: HBLANKn clears above xx 639 and VBLANKn above yy 199, on a
// 1024 x 262 raster. So the active area the sim captures is:
static const int FM7_WIDTH  = 640;
static const int FM7_HEIGHT = 200;

// rtl/pll: outclk_0. rtl/clocks.svh derives every core divider from this.
static const long CLK_SYS_HZ = 48000000;

// 16 MHz pixel clock / (1024 * 262). Only used to print run lengths in seconds.
static const double FRAME_HZ = 16000000.0 / (1024.0 * 262.0);

//----------------------------------------------------------------------------
// Globals
//----------------------------------------------------------------------------

static Vemu*        top = nullptr;
static vluint64_t   main_time = 0;
double sc_time_stamp() { return main_time; }

static DebugConsole console;
static SimBus       bus(console);
static SimVideo     video(FM7_WIDTH, FM7_HEIGHT, 0);
static SimInput     input(0, console);
static SimAudio     audio(CLK_SYS_HZ, false);
static SimBlockDevice blk(console);

// Not static: sim_video.cpp and sim_input.cpp reference this as an extern to
// skip all GL/SDL work. Same contract as the RX-78 and Apple-IIgs sims.
bool headless = false;
static bool run_enable     = true;
static int  stop_at_frame  = -1;
static int  reset_at_frame = -1;

static std::vector<int> screenshot_frames;
static std::string      screenshot_name_override;
static std::string      screenshot_prefix = "screenshot";
static std::set<int>    screenshots_taken;

static int  opt_bootrom    = 0;      // status[11:10]: 0 Basic, 1..3 DOS
static bool opt_tape_audio = false;  // status[9]

static bool  trace_io  = false;
static bool  trace_io_unknown_only = false;
static FILE* trace_io_file = nullptr;
static bool  pc_profile = false;
static bool  pc_profile_sub = false;

static bool  trace_cpu = false, trace_cpu_sub = false;
static FILE* trace_cpu_file = nullptr;
static int   trace_from  = 0;
static int   trace_until = -1;          // -1 = no limit
static long  trace_max   = 200000;      // line cap, so a wedged run stays usable
static long  trace_lines = 0;
// Separate budget for --trace-mem/--trace-mem-sub. Sharing trace_lines with
// --trace-cpu meant an instruction trace could burn the whole cap in frame 0
// and silently starve the memory trace, which reads as "the CPU never touched
// that address" -- a conclusion that is wrong in an expensive way.
static long  mem_trace_lines = 0;
static int   tail_count  = 16;          // instructions shown in the run stats
// Raw 64K dumps of what each CPU actually saw on its bus. `cmp` one against
// rtl/roms/*.rom at the right offset to prove the shadow (and so every
// disassembly built on it) is correctly aligned.
static std::string dump_shadow_path, dump_shadow_sub_path;
// --trace-mem window. Empty by default (lo > hi never matches).
static unsigned trace_mem_lo = 1, trace_mem_hi = 0;
static unsigned trace_smem_lo = 1, trace_smem_hi = 0;

//----------------------------------------------------------------------------
// Bus shadow
//
// Every byte either CPU puts on its data bus is recorded here, so the
// disassembler has something to read without any extra RTL. `known` matters:
// an address the CPU has never touched prints as "??" rather than as a
// plausible-looking $00, which is exactly the distinction you need when the
// question is "is it executing real code or reading open bus".
//----------------------------------------------------------------------------

struct Shadow {
	uint8_t mem[0x10000];
	uint8_t known[0x10000];
};
static Shadow shadow_m, shadow_s;

static int rd_main(uint16_t a) { return shadow_m.known[a] ? shadow_m.mem[a] : -1; }
static int rd_sub (uint16_t a) { return shadow_s.known[a] ? shadow_s.mem[a] : -1; }

// Ring buffer of retired instruction addresses, printed at exit. A wedged run
// is almost always explained by the last dozen instructions.
struct Retired { int frame; uint16_t pc; };
static std::vector<Retired> tail_m, tail_s;
static size_t tail_m_pos = 0, tail_s_pos = 0;

static void tail_push(std::vector<Retired>& v, size_t& pos, int frame, uint16_t pc) {
	if (tail_count <= 0) return;   // --trace-tail 0 disables history entirely
	if ((int)v.size() < tail_count) { v.push_back({frame, pc}); pos = v.size() % tail_count; }
	else { v[pos] = {frame, pc}; pos = (pos + 1) % tail_count; }
}

// "$fe15  86 3f        LDA   #$3f"
static void format_instr(bool sub, uint16_t pc, char* out, size_t n) {
	char txt[64];
	int len = dis6809(pc, sub ? rd_sub : rd_main, txt, sizeof(txt));
	char bytes[24] = "";
	size_t bl = 0;
	for (int i = 0; i < len && bl + 3 < sizeof(bytes); i++) {
		int v = sub ? rd_sub((uint16_t)(pc + i)) : rd_main((uint16_t)(pc + i));
		bl += snprintf(bytes + bl, sizeof(bytes) - bl, "%s",
		               v < 0 ? "?? " : "");
		if (v >= 0) bl += snprintf(bytes + bl, sizeof(bytes) - bl, "%02x ", v);
	}
	snprintf(out, n, "$%04x  %-15s %s", pc, bytes, txt);
}

// Register state as it stands *after* the traced instruction retired.
static void format_regs(bool sub, char* out, size_t n) {
	char cc[9];
	cc6809_string(sub ? top->dbg_s_cc : top->dbg_m_cc, cc);
	snprintf(out, n, "a=%02x b=%02x x=%04x y=%04x u=%04x s=%04x dp=%02x cc=%s",
	         sub ? top->dbg_s_a  : top->dbg_m_a,  sub ? top->dbg_s_b  : top->dbg_m_b,
	         sub ? top->dbg_s_x  : top->dbg_m_x,  sub ? top->dbg_s_y  : top->dbg_m_y,
	         sub ? top->dbg_s_u  : top->dbg_m_u,  sub ? top->dbg_s_s  : top->dbg_m_s,
	         sub ? top->dbg_s_dp : top->dbg_m_dp, cc);
}

static void print_tail(const char* label, std::vector<Retired>& v, size_t pos, bool sub) {
	if (v.empty()) return;
	printf("%s (oldest first):\n", label);
	// The buffer wraps, so start at `pos` once it is full.
	size_t n = v.size();
	size_t start = ((int)n < tail_count) ? 0 : pos;
	char line[160];
	for (size_t i = 0; i < n; i++) {
		const Retired& r = v[(start + i) % n];
		format_instr(sub, r.pc, line, sizeof(line));
		printf("     f%-6d %s\n", r.frame, line);
	}
}

//----------------------------------------------------------------------------
// Cassette
//
// The tape is streamed in over ioctl index 1 ("F1,t77") into the behavioural
// SDRAM in vsim/rtl/sdram.sv, and played by rtl/t77_decode.v -- the same path
// the FPGA build uses. There is no C++-side player: a .t77 is already a list of
// (level, duration) pairs, so decoding it in the host would test nothing.
//
// The transport is driven by the machine: PERIPHERAL.v bit 1 of $fd00 is the
// motor relay, and t77_decode only advances while it is on.
//----------------------------------------------------------------------------

static std::string tape_path;
static std::string disk_path;   // --disk <file.d77>
static bool        tape_rewind_pulse = false;
static int         tape_rewind_frame = -1;

// Ports rtl/ decodes in the $fdxx window. Anything else is "unknown" for
// --trace-io-unknown. Derived from MDECODE.v, MFD.v, RS232.v and PAL.v:
//   $00-$05  keyboard / peripheral / timer / clock control  (MDECODE x74138s)
//   $06-$07  8251 RS-232                                     (RS232.v)
//   $0d-$0f  PSG and the ROM/RAM boot switch                 (MDECODE x74139)
//   $18-$1d  MB8877 floppy registers                         (MFD.v)
//   $1f      floppy drive select                             (MFD.v)
//   $37      VRAM page / display page latch                  (WFD37n)
//   $38-$3f  palette                                         (PLTREGn)
static bool port_is_decoded(uint8_t p) {
	return (p <= 0x07) || (p >= 0x0d && p <= 0x0f) ||
	       (p >= 0x18 && p <= 0x1d) || p == 0x1f ||
	       p == 0x37 || (p >= 0x38 && p <= 0x3f);
}

//----------------------------------------------------------------------------
// Scheduled input injection
//----------------------------------------------------------------------------

struct KeyAction {
	int         frame;
	std::string text;   // literal text to type, or a single @NAME token
};
static std::vector<KeyAction> key_actions;

// How many frames a key is held down. This has to be in frames, not cycles: the
// sub CPU polls the keyboard latch, and a press shorter than its poll interval
// can fall between two samples and be lost.
static int key_hold_frames = 6;

struct PendingKey { int frame; uint16_t code; bool extended; bool down; };
static std::vector<PendingKey> pending_keys;

// PS/2 set-2 scancodes, matching what rtl/KEYBOARD.v decodes.
//
// KEYBOARD.v looks at the full 9-bit {extended, code}, so extended keys must be
// sent with the extended flag or they will not match.
//
// KEYBOARD.v now has a SHIFT table (JIS layout); CTRL / GRAPH / KANA are still
// unimplemented, so those modifiers still produce nothing.
struct KeyMap { uint16_t code; bool extended; bool shift; };

static bool ascii_to_ps2(char c, KeyMap& out) {
	static const uint8_t letters[26] = {
		0x1c,0x32,0x21,0x23,0x24,0x2b,0x34,0x33,0x43,0x3b,0x42,0x4b,0x3a,
		0x31,0x44,0x4d,0x15,0x2d,0x1b,0x2c,0x3c,0x2a,0x1d,0x22,0x35,0x1a
	};
	static const uint8_t digits[10] = {
		0x45,0x16,0x1e,0x26,0x25,0x2e,0x36,0x3d,0x3e,0x46
	};
	out.extended = false;
	out.shift    = false;
	if (c >= 'a' && c <= 'z') { out.code = letters[c - 'a']; return true; }
	if (c >= 'A' && c <= 'Z') { out.code = letters[c - 'A']; out.shift = true; return true; }
	if (c >= '0' && c <= '9') { out.code = digits[c - '0']; return true; }
	switch (c) {
		case ' ':  out.code = 0x29; return true;
		case '\n': case '\r': out.code = 0x5a; return true;
		case '\t': out.code = 0x0d; return true;
		case '\b': out.code = 0x66; return true;
		case '-':  out.code = 0x4e; return true;
		case '^':  out.code = 0x55; return true;
		case '\\': out.code = 0x5d; return true;
		case ',':  out.code = 0x41; return true;
		case '.':  out.code = 0x49; return true;
		case ';':  out.code = 0x4c; return true;
		case ':':  out.code = 0x52; return true;
		case '/':  out.code = 0x4a; return true;
		case '@':  out.code = 0x54; return true;   // the '[' key, JIS
		case '[':  out.code = 0x5b; return true;   // the ']' key, JIS
		// --- shifted, JIS number row and punctuation ---
		case '!':  out.code = 0x16; out.shift = true; return true;
		case '"':  out.code = 0x1e; out.shift = true; return true;
		case '#':  out.code = 0x26; out.shift = true; return true;
		case '$':  out.code = 0x25; out.shift = true; return true;
		case '%':  out.code = 0x2e; out.shift = true; return true;
		case '&':  out.code = 0x36; out.shift = true; return true;
		case '\'': out.code = 0x3d; out.shift = true; return true;
		case '(':  out.code = 0x3e; out.shift = true; return true;
		case ')':  out.code = 0x46; out.shift = true; return true;
		case '=':  out.code = 0x4e; out.shift = true; return true;
		case '~':  out.code = 0x55; out.shift = true; return true;
		case '|':  out.code = 0x5d; out.shift = true; return true;
		case '`':  out.code = 0x54; out.shift = true; return true;
		case '{':  out.code = 0x5b; out.shift = true; return true;
		case '+':  out.code = 0x4c; out.shift = true; return true;
		case '*':  out.code = 0x52; out.shift = true; return true;
		case '<':  out.code = 0x41; out.shift = true; return true;
		case '>':  out.code = 0x49; out.shift = true; return true;
		case '?':  out.code = 0x4a; out.shift = true; return true;
		default: return false;
	}
}

// Named keys, for the ones with no sensible ASCII form.
// Usage: --key 120:@RETURN  /  --key 120:@F1
static bool name_to_ps2(const std::string& n, KeyMap& out) {
	// {code, extended, shift}
	static const std::map<std::string, KeyMap> names = {
		{"SPACE",{0x29,false,false}}, {"RETURN",{0x5a,false,false}}, {"ENTER",{0x5a,false,false}},
		{"TAB",{0x0d,false,false}},   {"BS",{0x66,false,false}},     {"BACKSPACE",{0x66,false,false}},
		{"ESC",{0x76,false,false}},   {"CAPS",{0x58,false,false}},
		{"UP",{0x75,true,false}},     {"DOWN",{0x72,true,false}},
		{"LEFT",{0x6b,true,false}},   {"RIGHT",{0x74,true,false}},
		{"HOME",{0x6c,true,false}},   {"INS",{0x70,true,false}},     {"DEL",{0x71,true,false}},
		{"CTRL",{0x14,false,false}},  {"SHIFT",{0x12,false,false}},
		{"GRAPH",{0x11,false,false}}, {"KANA",{0x11,true,false}},    {"BREAK",{0x14,true,false}},
		{"F1",{0x05,false,false}},  {"F2",{0x06,false,false}},  {"F3",{0x04,false,false}},
		{"F4",{0x0c,false,false}},  {"F5",{0x03,false,false}},  {"F6",{0x0b,false,false}},
		{"F7",{0x83,false,false}},  {"F8",{0x0a,false,false}},  {"F9",{0x01,false,false}},
		{"F10",{0x09,false,false}},
	};
	std::string u = n;
	std::transform(u.begin(), u.end(), u.begin(), ::toupper);
	auto it = names.find(u);
	if (it == names.end()) return false;
	out = it->second;
	return true;
}

// Expand one --key action into frame-stamped press/release events.
static void schedule_key_action(const KeyAction& a) {
	std::vector<KeyMap> seq;
	if (a.text.size() > 1 && a.text[0] == '@') {
		KeyMap km;
		if (name_to_ps2(a.text.substr(1), km)) seq.push_back(km);
		else printf("Unknown key name: %s\n", a.text.c_str() + 1);
	} else {
		for (char c : a.text) {
			KeyMap km;
			if (ascii_to_ps2(c, km)) seq.push_back(km);
			else printf("No scancode for '%c' (0x%02x)\n", c, (unsigned char)c);
		}
	}
	int f = a.frame;
	for (const KeyMap& km : seq) {
		// Shift must be down before the key and released after it: KEYBOARD.v
		// samples shift_h at the moment the key's press event is decoded.
		if (km.shift) pending_keys.push_back({f, 0x12, false, true});
		pending_keys.push_back({f + (km.shift ? 1 : 0), km.code, km.extended, true});
		pending_keys.push_back({f + key_hold_frames, km.code, km.extended, false});
		if (km.shift) pending_keys.push_back({f + key_hold_frames + 1, 0x12, false, false});
		// Gap between characters so the machine sees a clean release. KEYBOARD.v
		// latches on the RISING edge of press_btn, so two presses with no
		// release between them produce only one keystroke.
		f += key_hold_frames * 2;
	}
}

//----------------------------------------------------------------------------
// Screenshots
//----------------------------------------------------------------------------

static void save_screenshot(int frame) {
	if (!output_ptr) {
		fprintf(stderr, "screenshot: no framebuffer\n");
		return;
	}
	char filename[512];
	if (!screenshot_name_override.empty())
		snprintf(filename, sizeof(filename), "%s", screenshot_name_override.c_str());
	else
		snprintf(filename, sizeof(filename), "%s_frame_%04d.png",
		         screenshot_prefix.c_str(), frame);

	const int w = video.output_width, h = video.output_height;
	uint8_t* rgb = (uint8_t*)malloc((size_t)w * h * 3);
	if (!rgb) { fprintf(stderr, "screenshot: out of memory\n"); return; }

	// sim_video packs pixels as 0xFF000000 | B<<16 | G<<8 | R
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			uint32_t px = output_ptr[y * w + x];
			uint8_t* d = &rgb[((size_t)y * w + x) * 3];
			d[0] = (px >>  0) & 0xFF;
			d[1] = (px >>  8) & 0xFF;
			d[2] = (px >> 16) & 0xFF;
		}
	}
	int ok = stbi_write_png(filename, w, h, 3, rgb, w * 3);
	free(rgb);
	printf(ok ? "Screenshot saved: %s\n" : "Error: could not write %s\n", filename);
	fflush(stdout);
}

//----------------------------------------------------------------------------
// Colour helper
//
// FM-7_MiSTer.sv: VGA_R = grb[1], VGA_G = grb[2], VGA_B = grb[0]. Each palette
// entry in rtl/PAL.v is one of those 3-bit grb values.
//----------------------------------------------------------------------------

static void fm7_colour(uint8_t grb, uint8_t& r, uint8_t& g, uint8_t& b) {
	r = (grb & 0x2) ? 0xff : 0;
	g = (grb & 0x4) ? 0xff : 0;
	b = (grb & 0x1) ? 0xff : 0;
}

static uint8_t pal_entry(int n) { return (top->dbg_pal >> (3 * n)) & 0x7; }

//----------------------------------------------------------------------------
// CLI
//----------------------------------------------------------------------------

static void print_usage(const char* argv0) {
	printf("FM-7 Verilator simulation\n\n");
	printf("Usage: %s [options]\n\n", argv0);
	printf("Media:\n");
	printf("  --disk <file.d77>         Mount a floppy on drive 0, served over the\n");
	printf("                            MiSTer block device (sd_lba/sd_buff_*), the\n");
	printf("                            same path hps_io uses on hardware\n");
	printf("  --tape <file.t77>         Mount a cassette (ioctl index 1 -> SDRAM ->\n");
	printf("                            rtl/t77_decode.v, the path that ships)\n");
	printf("  --tape-audio              Mix the cassette bit and relay click into\n");
	printf("                            the audio output (OSD \"Tape Audio\")\n");
	printf("  --rewind-at-frame <n>     Pulse the tape rewind bit at frame n\n");
	printf("  --bootrom <0-3>           0 = F-BASIC (default), 1-3 = DOS boot ROMs\n");
	printf("\nRun control:\n");
	printf("  --headless, --no-gui      No SDL window. Implied by HEADLESS=1.\n");
	printf("  --stop-at-frame <n>       Exit after frame n. Required headless;\n");
	printf("                            otherwise it stops at 100000.\n");
	printf("  --reset-at-frame <n>      Pulse reset at frame n\n");
	printf("\nCapture:\n");
	printf("  --screenshot <n[,n...]>   Save a PNG at each listed frame\n");
	printf("  --screenshot-name <path>  Exact output path (single screenshot only)\n");
	printf("  --screenshot-prefix <s>   Filename prefix (default \"screenshot\")\n");
	printf("\nInput injection (frame-scheduled):\n");
	printf("  --key <frame>:<text>      Type text, or @NAME for a named key.\n");
	printf("                            Names: SPACE RETURN TAB BS ESC CAPS UP DOWN\n");
	printf("                                   LEFT RIGHT HOME INS DEL CTRL SHIFT\n");
	printf("                                   GRAPH KANA BREAK F1..F10\n");
	printf("  --key-hold <frames>       Frames to hold each key (default 6)\n");
	printf("\nTracing:\n");
	printf("  --trace-io [file]         Log every $fdxx read/write\n");
	printf("  --trace-io-unknown [file] Log only ports rtl/ does not decode\n");
	printf("  --trace-cpu [file]        Disassemble every main-CPU instruction as it\n");
	printf("                            retires, with registers. Bound it with\n");
	printf("                            --trace-from/--trace-until, it is ~8000\n");
	printf("                            lines per frame.\n");
	printf("  --trace-sub-cpu [file]    Same, for the sub CPU\n");
	printf("  --trace-from <frame>      Start tracing at this frame (default 0)\n");
	printf("  --trace-until <frame>     Stop tracing after this frame\n");
	printf("  --trace-max <n>           Cap on trace lines (default 200000)\n");
	printf("  --trace-tail <n>          Instructions of history shown in the run\n");
	printf("                            stats (default 16, 0 disables)\n");
	printf("  --trace-mem <lo>-<hi>     Log every main-CPU bus cycle in that hex\n");
	printf("                            address range, with the ROM/RAM decode\n");
	printf("                            lines. Tells a bad read apart from a bad\n");
	printf("                            chip select.\n");
	printf("  --trace-mem-sub <lo>-<hi> Same for the sub CPU, without the decode\n");
	printf("                            lines. Use it on the shared RAM window.\n");
	printf("  --dump-shadow <file>      Write the 64K main-CPU bus shadow (bytes the\n");
	printf("                            CPU actually saw). cmp it against a ROM to\n");
	printf("                            check the sim, or to see what got loaded.\n");
	printf("  --dump-shadow-sub <file>  Same, for the sub CPU\n");
	printf("  --pc-profile              Histogram of main-CPU instruction addresses,\n");
	printf("                            to find where a wedged CPU is spinning\n");
	printf("  --pc-profile-sub          Same, for the sub CPU\n");
	printf("\nExamples:\n");
	printf("  %s --headless --screenshot 300 --stop-at-frame 320\n", argv0);
	printf("  %s --headless --key 200:print 1+1 --key 260:@RETURN \\\n", argv0);
	printf("      --screenshot 320 --stop-at-frame 340\n");
	printf("  %s --headless --tape game.t77 --key 200:load\\\"\\\" --key 260:@RETURN \\\n", argv0);
	printf("      --stop-at-frame 3000\n");
}

static bool split_frame_arg(const char* s, int& frame, std::string& rest) {
	const char* colon = strchr(s, ':');
	if (!colon) return false;
	frame = atoi(std::string(s, colon - s).c_str());
	rest = colon + 1;
	return true;
}

static int parse_args(int argc, char** argv) {
	const char* env = getenv("HEADLESS");
	if (env && env[0] && env[0] != '0') headless = true;

	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&](void) -> const char* { return (i + 1 < argc) ? argv[++i] : nullptr; };

		if (a == "-h" || a == "--help") { print_usage(argv[0]); return 1; }
		else if (a == "--headless" || a == "--no-gui") headless = true;
		else if (a == "--tape")       { const char* v = next(); if (v) tape_path = v; }
		else if (a == "--disk")       { const char* v = next(); if (v) disk_path = v; }
		else if (a == "--tape-audio") opt_tape_audio = true;
		else if (a == "--bootrom")    { const char* v = next(); if (v) opt_bootrom = atoi(v) & 3; }
		else if (a == "--key-hold")        { const char* v = next(); if (v) key_hold_frames = atoi(v); }
		else if (a == "--stop-at-frame")   { const char* v = next(); if (v) stop_at_frame = atoi(v); }
		else if (a == "--reset-at-frame")  { const char* v = next(); if (v) reset_at_frame = atoi(v); }
		else if (a == "--rewind-at-frame") { const char* v = next(); if (v) tape_rewind_frame = atoi(v); }
		else if (a == "--pc-profile")      pc_profile = true;
		else if (a == "--pc-profile-sub")  { pc_profile = true; pc_profile_sub = true; }
		else if (a == "--screenshot-name")   { const char* v = next(); if (v) screenshot_name_override = v; }
		else if (a == "--screenshot-prefix") { const char* v = next(); if (v) screenshot_prefix = v; }
		else if (a == "--screenshot") {
			const char* v = next();
			if (v) {
				std::string list = v, tok;
				size_t pos = 0;
				while (pos <= list.size()) {
					size_t comma = list.find(',', pos);
					tok = list.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos);
					if (!tok.empty()) screenshot_frames.push_back(atoi(tok.c_str()));
					if (comma == std::string::npos) break;
					pos = comma + 1;
				}
			}
		}
		else if (a == "--key") {
			const char* v = next();
			int f; std::string t;
			if (v && split_frame_arg(v, f, t)) key_actions.push_back({f, t});
			else printf("Error: --key needs <frame>:<text>\n");
		}
		else if (a == "--trace-mem" || a == "--trace-mem-sub") {
			const char* v = next();
			unsigned lo = 0, hi = 0;
			bool sub = (a == "--trace-mem-sub");
			unsigned& dlo = sub ? trace_smem_lo : trace_mem_lo;
			unsigned& dhi = sub ? trace_smem_hi : trace_mem_hi;
			if (v && sscanf(v, "%x-%x", &lo, &hi) == 2) { dlo = lo; dhi = hi; }
			else if (v && sscanf(v, "%x", &lo) == 1)    { dlo = dhi = lo; }
			else printf("Error: %s needs <lo>-<hi> in hex\n", a.c_str());
		}
		else if (a == "--dump-shadow")     { const char* v = next(); if (v) dump_shadow_path = v; }
		else if (a == "--dump-shadow-sub") { const char* v = next(); if (v) dump_shadow_sub_path = v; }
		else if (a == "--trace-from")  { const char* v = next(); if (v) trace_from = atoi(v); }
		else if (a == "--trace-until") { const char* v = next(); if (v) trace_until = atoi(v); }
		else if (a == "--trace-max")   { const char* v = next(); if (v) trace_max = atol(v); }
		else if (a == "--trace-tail")  { const char* v = next(); if (v) tail_count = atoi(v); }
		else if (a == "--trace-cpu" || a == "--trace-sub-cpu") {
			if (a == "--trace-cpu") trace_cpu = true; else trace_cpu_sub = true;
			if (i + 1 < argc && argv[i + 1][0] != '-') {
				const char* path = argv[++i];
				// Both flags can share one file; only open it once.
				if (!trace_cpu_file) {
					trace_cpu_file = fopen(path, "w");
					if (!trace_cpu_file) printf("Error: cannot open %s\n", path);
				}
			}
		}
		else if (a == "--trace-io" || a == "--trace-io-unknown") {
			trace_io = true;
			trace_io_unknown_only = (a == "--trace-io-unknown");
			if (i + 1 < argc && argv[i + 1][0] != '-') {
				const char* path = argv[++i];
				trace_io_file = fopen(path, "w");
				if (!trace_io_file) printf("Error: cannot open %s\n", path);
			}
		}
		else printf("Warning: unrecognised option '%s' (try --help)\n", a.c_str());
	}
	return 0;
}

//----------------------------------------------------------------------------
// Simulation step
//----------------------------------------------------------------------------

static int  reset_hold = 0;        // clk_sys cycles left to hold reset
static int  reset_prologue = 0;    // cycles with reset LOW before it is asserted
static int  rewind_hold = 0;
static long io_counts[256] = {0};

// Liveness counters. The point of these is to tell "the core is wedged" apart
// from "the machine is idle by design", which a still screenshot cannot.
static long stat_m_instr = 0, stat_s_instr = 0;
static long stat_m_irq   = 0, stat_m_firq  = 0, stat_m_nmi = 0;
static long stat_s_irq   = 0, stat_s_firq  = 0, stat_s_nmi = 0;
static long stat_io_cycles = 0;
static long stat_vb_rises  = 0;
static long stat_s_halt_cycles = 0;
static long stat_kstrobes  = 0;
static long stat_tape_edges = 0, stat_tape_motor_cycles = 0;
static long stat_d40a_rd = 0, stat_d40a_wr = 0;
static uint16_t m_pc_lo = 0xffff, m_pc_hi = 0;
static uint16_t s_pc_lo = 0xffff, s_pc_hi = 0;
// Where the main CPU is executing, bucketed. $fd00-$fdff is the I/O window --
// instructions fetched from there mean the CPU has run away into the
// peripherals, which reads $ff for anything undecoded and so never traps.
static long stat_m_in_ram = 0, stat_m_in_io = 0, stat_m_in_rom = 0;
static uint8_t  kdata_seen = 0;
static std::map<uint16_t,long> m_pc_hist, s_pc_hist;

static uint8_t last_m_ifetch = 0, last_s_ifetch = 0;
static uint8_t last_m_irqn = 1, last_m_firqn = 1, last_m_nmin = 1;
static uint8_t last_s_irqn = 1, last_s_firqn = 1, last_s_nmin = 1;
static uint8_t last_io_wr = 0, last_io_rd = 0;
static uint8_t last_vb = 0, last_tape_in = 0, last_kstroben = 1;
static uint16_t m_prev_pc = 0, s_prev_pc = 0;
static bool     have_m_prev = false, have_s_prev = false;
// Bus state as of the end of the previous clk_sys cycle -- see the shadow
// comment in sim_cycle().
static uint16_t pre_m_addr = 0, pre_s_addr = 0;
static uint8_t  pre_m_din = 0, pre_m_dout = 0, pre_m_rw = 1, pre_m_e = 0;
static uint8_t  pre_s_din = 0, pre_s_dout = 0, pre_s_rw = 1, pre_s_e = 0;
static uint8_t  pre_m_mmap = 0, pre_m_romdata = 0;
// Address of the instruction currently executing, for the I/O trace.
static uint16_t m_cur_pc = 0;

// One trace line per retired instruction, when --trace-cpu/--trace-sub-cpu is
// on and the frame is inside the requested window.
static void emit_cpu_trace(bool sub, uint16_t pc) {
	if (!(sub ? trace_cpu_sub : trace_cpu)) return;
	if (video.count_frame < trace_from) return;
	if (trace_until >= 0 && video.count_frame > trace_until) return;
	if (trace_lines >= trace_max) return;
	char instr[160], regs[128];
	format_instr(sub, pc, instr, sizeof(instr));
	format_regs(sub, regs, sizeof(regs));
	FILE* o = trace_cpu_file ? trace_cpu_file : stdout;
	fprintf(o, "%7d %s  %s  %s\n", video.count_frame, sub ? "sub " : "main", instr, regs);
	if (++trace_lines == trace_max)
		fprintf(o, "... --trace-max %ld reached, tracing stopped\n", trace_max);
}

static void print_pc_hist(const char* label, std::map<uint16_t,long>& h,
                          const char* file) {
	if (h.empty()) return;
	std::vector<std::pair<long,uint16_t>> v;
	for (auto& kv : h) v.push_back({kv.second, kv.first});
	std::sort(v.rbegin(), v.rend());
	long total = 0; for (auto& p : v) total += p.first;
	printf("%s: (%ld instructions, %zu distinct addresses)\n", label, total, v.size());
	for (size_t i = 0; i < v.size() && i < 12; i++)
		printf("     $%04x  %8ld  %5.1f%%\n", v[i].second, v[i].first,
		       100.0 * v[i].first / total);
	FILE* pf = fopen(file, "w");
	if (pf) { for (auto& kv : h) fprintf(pf, "%04x %ld\n", kv.first, kv.second);
	          fclose(pf); printf("     full histogram: %s\n", file); }
}

static void print_run_stats() {
	const int frames = video.count_frame;
	printf("\n--- run stats ---------------------------------------------\n");
	printf("frames            : %d  (%.2f s of machine time)\n",
	       frames, frames / FRAME_HZ);
	printf("vblank edges      : %ld\n", stat_vb_rises);

	printf("main 6809         : %ld instructions", stat_m_instr);
	if (frames > 0) printf("  (%.0f per frame)", (double)stat_m_instr / frames);
	printf("%s\n", stat_m_instr == 0 ? "   <- main CPU never ran" : "");
	printf("     pc range     : $%04x .. $%04x   pc now $%04x\n",
	       m_pc_lo, m_pc_hi, top->dbg_m_pc);
	printf("     fetched from : RAM %ld  ROM %ld  I/O %ld%s\n",
	       stat_m_in_ram, stat_m_in_rom, stat_m_in_io,
	       stat_m_in_io ? "   <- RUNAWAY: executing in the $fdxx I/O window" : "");
	printf("     interrupts   : IRQ %ld  FIRQ %ld  NMI %ld   (lines now: %s%s%s)\n",
	       stat_m_irq, stat_m_firq, stat_m_nmi,
	       top->dbg_m_irqn ? "" : "IRQ ", top->dbg_m_firqn ? "" : "FIRQ ",
	       (top->dbg_m_irqn && top->dbg_m_firqn) ? "idle" : "");

	printf("sub 6809          : %ld instructions", stat_s_instr);
	if (frames > 0) printf("  (%.0f per frame)", (double)stat_s_instr / frames);
	printf("%s\n", stat_s_instr == 0 ? "   <- sub CPU never ran" : "");
	printf("     pc range     : $%04x .. $%04x   pc now $%04x\n",
	       s_pc_lo, s_pc_hi, top->dbg_s_pc);
	printf("     interrupts   : IRQ %ld  FIRQ %ld  NMI %ld\n",
	       stat_s_irq, stat_s_firq, stat_s_nmi);
	// SHALTn low is normal and constant: MB60H010 asserts SVDHALT to stall the
	// sub CPU during active video. A ratio near 100% means it never got the bus.
	printf("     halted        : %.1f%% of cycles%s\n",
	       main_time ? 100.0 * stat_s_halt_cycles / main_time : 0.0,
	       (main_time && stat_s_halt_cycles > main_time * 99 / 100)
	           ? "   <- sub CPU is held in HALT" : "");

	// The main<->sub handshake, which is what a black screen usually comes down
	// to. $fd05 bit 7 is BUSY (FLAGS.v m44_8); the sub clears it by READING
	// $d40a and sets it by WRITING $d40a (SBUSYSETn latches SRWBn).
	printf("sub handshake     : BUSY=%d  SHALTn=%d  SHALTACn=%d   $fd05 would read $%02x\n",
	       top->dbg_busy, top->dbg_s_haltn, top->dbg_s_halt_ackn,
	       (top->dbg_busy << 7) | 0x7e);
	printf("     $d40a access : %ld reads (clear BUSY), %ld writes (set BUSY)%s\n",
	       stat_d40a_rd, stat_d40a_wr,
	       (stat_d40a_rd == 0 && stat_d40a_wr == 0)
	           ? "   <- sub never touched the BUSY flag" : "");
	printf("I/O cycles ($fdxx): %ld\n", stat_io_cycles);
	printf("keyboard          : %ld strobes, codes seen $%02x%s\n",
	       stat_kstrobes, kdata_seen,
	       kdata_seen ? "" : "   (no key ever reached the latch)");
	if (!tape_path.empty()) {
		printf("tape              : motor on %.1f%% of the run, %ld cassette-bit edges\n",
		       main_time ? 100.0 * stat_tape_motor_cycles / main_time : 0.0,
		       stat_tape_edges);
		printf("     sdram addr   : $%06x of $%06x  (%.1f%%)%s%s\n",
		       top->dbg_tape_addr, top->dbg_tape_size,
		       top->dbg_tape_size > 16
		           ? 100.0 * (double)(top->dbg_tape_addr > 16 ? top->dbg_tape_addr - 16 : 0)
		                   / (double)(top->dbg_tape_size - 16)
		           : 0.0,
		       top->dbg_tape_eot ? "  END OF TAPE" : "",
		       stat_tape_motor_cycles ? "" : "   <- the machine never ran the motor");
	}
	printf("video             : palette");
	for (int i = 0; i < 8; i++) printf(" %d", pal_entry(i));
	printf("   $fd37 = $%02x   scroll $%04x   display %s\n",
	       top->dbg_vpage, top->dbg_voffset, top->dbg_svdoffn ? "on" : "OFF");

	if (pc_profile) {
		print_pc_hist("hot main-CPU addresses", m_pc_hist, "pc_profile_main.txt");
		if (pc_profile_sub)
			print_pc_hist("hot sub-CPU addresses", s_pc_hist, "pc_profile_sub.txt");
	}

	if (tail_count > 0) {
		print_tail("last main-CPU instructions", tail_m, tail_m_pos, false);
		print_tail("last sub-CPU instructions",  tail_s, tail_s_pos, true);
	}

	// Bytes never seen on the bus are written as $00, which is indistinguishable
	// from a real $00 -- so a sidecar "<path>.known" carries one flag byte per
	// address. Compare only where that is 1, or a ROM check drowns in the gaps.
	auto dump = [](const std::string& path, const Shadow& s, const char* what) {
		if (path.empty()) return;
		FILE* f = fopen(path.c_str(), "wb");
		if (!f) { printf("Error: cannot write %s\n", path.c_str()); return; }
		fwrite(s.mem, 1, sizeof(s.mem), f);
		fclose(f);
		std::string kp = path + ".known";
		if (FILE* kf = fopen(kp.c_str(), "wb")) { fwrite(s.known, 1, sizeof(s.known), kf); fclose(kf); }
		long n = 0;
		for (int i = 0; i < 0x10000; i++) n += s.known[i] ? 1 : 0;
		printf("%s bus shadow -> %s (+ .known)  (%ld of 65536 addresses seen)\n",
		       what, path.c_str(), n);
	};
	dump(dump_shadow_path,     shadow_m, "main");
	dump(dump_shadow_sub_path, shadow_s, "sub ");

	// A runaway CPU touches all 256 ports, so print contiguous runs as ranges
	// rather than 256 separate entries.
	printf("ports touched     :");
	for (int p = 0; p < 256; ) {
		if (!io_counts[p]) { p++; continue; }
		int q = p;
		while (q + 1 < 256 && io_counts[q + 1]) q++;
		if (q == p) printf(" $%02x", p);
		else        printf(" $%02x-$%02x", p, q);
		p = q + 1;
	}
	printf("\n");
	int undecoded = 0;
	long undecoded_hits = 0;
	for (int p = 0; p < 256; p++)
		if (io_counts[p] && !port_is_decoded(p)) { undecoded++; undecoded_hits += io_counts[p]; }
	if (undecoded) {
		printf("UNDECODED ports   : %d ports, %ld accesses:", undecoded, undecoded_hits);
		int shown = 0;
		for (int p = 0; p < 256 && shown < 16; p++)
			if (io_counts[p] && !port_is_decoded(p)) { printf(" $%02x(%ld)", p, io_counts[p]); shown++; }
		if (shown < undecoded) printf(" ...");
		printf("\n");
	}
	printf("-----------------------------------------------------------\n");
	fflush(stdout);
}

static void apply_frame_actions(int frame) {
	static int last_frame = -1;
	if (frame == last_frame) return;
	last_frame = frame;

	for (auto& pk : pending_keys)
		if (pk.frame == frame)
			input.keyEvents.push(SimInput_PS2KeyEvent(0, pk.down, pk.extended, pk.code));
	if (reset_at_frame == frame) {
		console.AddLog("frame %d: reset", frame);
		reset_hold = 20000;
	}
	if (tape_rewind_frame == frame) {
		console.AddLog("frame %d: tape rewind", frame);
		rewind_hold = 2000;
	}
	for (int f : screenshot_frames)
		if (f == frame && !screenshots_taken.count(f)) {
			screenshots_taken.insert(f);
			save_screenshot(f);
		}
}

// One full clk_sys period (two evals).
static void sim_cycle() {
	// --- rising edge -------------------------------------------------
	top->clk_sys = 1;
	bus.BeforeEval();
	blk.BeforeEval((int)main_time);
	input.BeforeEval();

	top->bootrom_sel = opt_bootrom;
	top->tape_audio  = opt_tape_audio;
	top->tape_rewind = (rewind_hold > 0) || tape_rewind_pulse;
	if (rewind_hold > 0) rewind_hold--;

	// FM-7_MiSTer.sv: reset = RESET | status[0] | buttons[1].
	//
	// The prologue matters. ROMS.v latches the boot ROM select with
	//   always @(posedge pre, posedge clr, posedge ck)  ... ck = ~RESETBn
	// -- a flip-flop *clocked by reset being asserted*, not by reset being
	// released. Starting the sim with reset already high gives ~RESETBn no
	// rising edge, so ff_q keeps its power-on 0, RAM1HB2n stays high, the
	// F-BASIC ROM is never chip-selected and every read of $8000-$fbff returns
	// $00. Running a few cycles with reset LOW first reproduces the power-on
	// pulse the board actually delivers.
	top->reset = (reset_prologue == 0) && (reset_hold > 0);
	if (reset_prologue > 0) reset_prologue--;
	else if (reset_hold > 0) reset_hold--;

	top->eval();
	bus.AfterEval();
	blk.AfterEval();

	// --- bus shadow --------------------------------------------------
	// A bus cycle ends on E's falling edge, and that is also the edge
	// mc6809i.v advances its state machine on (`always @(negedge E)`), while
	// the address bus is purely combinational on the new state
	// (`assign ADDR = addr_nxt`). So by the time an eval has completed with E
	// low, the address has already moved on to the next cycle while the data
	// bus still carries the byte the cycle just finished.
	//
	// Sampling the values captured one clk_sys cycle earlier -- i.e. the last
	// moment before that update -- keeps address and data on the same bus
	// cycle. Getting this wrong shifts every byte by one address, which still
	// disassembles, just into convincing nonsense: verify with --dump-shadow.
	if (!top->dbg_m_e && pre_m_e) {
		shadow_m.mem[pre_m_addr]   = pre_m_rw ? pre_m_din : pre_m_dout;
		shadow_m.known[pre_m_addr] = 1;
		// --trace-mem: one line per main-CPU bus cycle in the window, with the
		// memory-map selects. This is how you tell "the CPU read $00" apart
		// from "the decoder never enabled the ROM".
		if (pre_m_addr >= trace_mem_lo && pre_m_addr <= trace_mem_hi &&
		    mem_trace_lines < trace_max) {
			FILE* o = trace_cpu_file ? trace_cpu_file : stdout;
			fprintf(o, "%7d mem  %c $%04x %s $%02x   rom=$%02x mmap=%c%c%c%c%c%c%c%c"
			           " (RDQE MIOS SUBSEL BTRDY BTROM RAM1HB2 RAM1HB1 FCXX)  pc=$%04x\n",
			        video.count_frame, pre_m_rw ? 'R' : 'W', pre_m_addr,
			        pre_m_rw ? "->" : "<-", pre_m_rw ? pre_m_din : pre_m_dout,
			        pre_m_romdata,
			        (pre_m_mmap & 0x80) ? '1' : '0', (pre_m_mmap & 0x40) ? '1' : '0',
			        (pre_m_mmap & 0x20) ? '1' : '0', (pre_m_mmap & 0x10) ? '1' : '0',
			        (pre_m_mmap & 0x08) ? '1' : '0', (pre_m_mmap & 0x04) ? '1' : '0',
			        (pre_m_mmap & 0x02) ? '1' : '0', (pre_m_mmap & 0x01) ? '1' : '0',
			        m_cur_pc);
			mem_trace_lines++;
		}
	}
	if (!top->dbg_s_e && pre_s_e) {
		shadow_s.mem[pre_s_addr]   = pre_s_rw ? pre_s_din : pre_s_dout;
		shadow_s.known[pre_s_addr] = 1;
		if (pre_s_addr == 0xd40a) { if (pre_s_rw) stat_d40a_rd++; else stat_d40a_wr++; }
		// No mmap column here: the sub CPU's selects come from SDECODE.v and are
		// not the same set. The shared-RAM window is what this is usually for.
		if (pre_s_addr >= trace_smem_lo && pre_s_addr <= trace_smem_hi &&
		    mem_trace_lines < trace_max) {
			FILE* o = trace_cpu_file ? trace_cpu_file : stdout;
			fprintf(o, "%7d smem %c $%04x %s $%02x   pc=$%04x\n",
			        video.count_frame, pre_s_rw ? 'R' : 'W', pre_s_addr,
			        pre_s_rw ? "->" : "<-", pre_s_rw ? pre_s_din : pre_s_dout,
			        s_prev_pc);
			mem_trace_lines++;
		}
	}

	// --- liveness ----------------------------------------------------
	// One event per instruction, at the opcode fetch, where the address bus is
	// carrying the instruction's own address. The trace is emitted one
	// instruction late so that every operand byte is already in the shadow.
	if (top->dbg_m_ifetch && !last_m_ifetch) {
		stat_m_instr++;
		uint16_t pc = top->dbg_m_addr;
		if (pc_profile) m_pc_hist[pc]++;
		if (!top->reset) {
			if (pc < m_pc_lo) m_pc_lo = pc;
			if (pc > m_pc_hi) m_pc_hi = pc;
			if      (pc >= 0xfd00 && pc <= 0xfdff) stat_m_in_io++;
			else if (pc >= 0x8000)                 stat_m_in_rom++;
			else                                   stat_m_in_ram++;

			if (have_m_prev) {
				tail_push(tail_m, tail_m_pos, video.count_frame, m_prev_pc);
				emit_cpu_trace(false, m_prev_pc);
			}
			m_prev_pc = pc;
			m_cur_pc  = pc;
			have_m_prev = true;
		}
	}
	last_m_ifetch = top->dbg_m_ifetch;

	if (top->dbg_s_ifetch && !last_s_ifetch) {
		stat_s_instr++;
		uint16_t pc = top->dbg_s_addr;
		if (pc_profile_sub) s_pc_hist[pc]++;
		if (!top->reset) {
			if (pc < s_pc_lo) s_pc_lo = pc;
			if (pc > s_pc_hi) s_pc_hi = pc;

			if (have_s_prev) {
				tail_push(tail_s, tail_s_pos, video.count_frame, s_prev_pc);
				emit_cpu_trace(true, s_prev_pc);
			}
			s_prev_pc = pc;
			have_s_prev = true;
		}
	}
	last_s_ifetch = top->dbg_s_ifetch;

	// All six interrupt lines are active low; count the falling edges.
	if (!top->dbg_m_irqn  && last_m_irqn)  stat_m_irq++;
	if (!top->dbg_m_firqn && last_m_firqn) stat_m_firq++;
	if (!top->dbg_m_nmin  && last_m_nmin)  stat_m_nmi++;
	if (!top->dbg_s_irqn  && last_s_irqn)  stat_s_irq++;
	if (!top->dbg_s_firqn && last_s_firqn) stat_s_firq++;
	if (!top->dbg_s_nmin  && last_s_nmin)  stat_s_nmi++;
	last_m_irqn = top->dbg_m_irqn; last_m_firqn = top->dbg_m_firqn; last_m_nmin = top->dbg_m_nmin;
	last_s_irqn = top->dbg_s_irqn; last_s_firqn = top->dbg_s_firqn; last_s_nmin = top->dbg_s_nmin;
	if (!top->dbg_s_haltn) stat_s_halt_cycles++;

	if (top->VGA_VB && !last_vb) stat_vb_rises++;
	last_vb = top->VGA_VB;

	// KSTROBEn is the sub CPU's FIRQ line, asserted when KEYBOARD.v latches a
	// code. Falling edges are keystrokes that actually reached the machine.
	if (!top->dbg_kstroben && last_kstroben) stat_kstrobes++;
	last_kstroben = top->dbg_kstroben;
	kdata_seen |= top->dbg_kdata;

	if (top->dbg_tape_motor) stat_tape_motor_cycles++;
	if (top->dbg_tape_in != last_tape_in) stat_tape_edges++;
	last_tape_in = top->dbg_tape_in;

	if (top->dbg_io_wr && !last_io_wr) { io_counts[top->dbg_io_port]++; stat_io_cycles++; }
	if (top->dbg_io_rd && !last_io_rd) { io_counts[top->dbg_io_port]++; stat_io_cycles++; }

	if (trace_io) {
		uint8_t p = top->dbg_io_port;
		if ((top->dbg_io_wr && !last_io_wr) &&
		    (!trace_io_unknown_only || !port_is_decoded(p))) {
			FILE* o = trace_io_file ? trace_io_file : stdout;
			fprintf(o, "%8d W $fd%02x <- $%02x   pc=$%04x\n",
			        video.count_frame, p, top->dbg_io_data, m_cur_pc);
		}
		if ((top->dbg_io_rd && !last_io_rd) &&
		    (!trace_io_unknown_only || !port_is_decoded(p))) {
			FILE* o = trace_io_file ? trace_io_file : stdout;
			fprintf(o, "%8d R $fd%02x -> $%02x   pc=$%04x\n",
			        video.count_frame, p, top->dbg_io_data, m_cur_pc);
		}
	}
	last_io_wr = top->dbg_io_wr;
	last_io_rd = top->dbg_io_rd;

	if (top->CE_PIXEL) {
		uint32_t colour = 0xFF000000u |
		                  ((uint32_t)top->VGA_B << 16) |
		                  ((uint32_t)top->VGA_G << 8) |
		                  ((uint32_t)top->VGA_R);
		video.Clock(top->VGA_HB, top->VGA_VB, top->VGA_HS, top->VGA_VS, colour);
	}

	if (!headless) audio.Clock(top->AUDIO_L, top->AUDIO_R);

	// --- falling edge ------------------------------------------------
	top->clk_sys = 0;
	top->eval();

	// Snapshot the buses for the next cycle's shadow update.
	pre_m_addr = top->dbg_m_addr; pre_m_din = top->dbg_m_din;
	pre_m_dout = top->dbg_m_dout; pre_m_rw  = top->dbg_m_rw;  pre_m_e = top->dbg_m_e;
	pre_m_mmap = top->dbg_mmap;   pre_m_romdata = top->dbg_romdata;
	pre_s_addr = top->dbg_s_addr; pre_s_din = top->dbg_s_din;
	pre_s_dout = top->dbg_s_dout; pre_s_rw  = top->dbg_s_rw;  pre_s_e = top->dbg_s_e;

	main_time++;
	apply_frame_actions(video.count_frame);
}

//----------------------------------------------------------------------------
// ImGui panels
//----------------------------------------------------------------------------

#ifndef _MSC_VER
static void draw_colour_swatch(const char* label, uint8_t grb) {
	uint8_t r, g, b;
	fm7_colour(grb, r, g, b);
	ImGui::ColorButton(label, ImVec4(r / 255.0f, g / 255.0f, b / 255.0f, 1.0f),
	                   ImGuiColorEditFlags_NoTooltip, ImVec2(18, 18));
	ImGui::SameLine();
	ImGui::Text("%s = %d", label, grb);
}

static void draw_state_window() {
	ImGui::Begin("FM-7 state");

	ImGui::Text("frame %d   line %d   pixel %d",
	            video.count_frame, video.count_line, video.count_pixel);
	ImGui::Text("beam xx=%d yy=%d", top->h_count, top->v_count);
	ImGui::Separator();

	if (ImGui::CollapsingHeader("CPUs", ImGuiTreeNodeFlags_DefaultOpen)) {
		ImGui::Text("main  pc $%04x  addr $%04x  %s  data $%02x",
		            top->dbg_m_pc, top->dbg_m_addr,
		            top->dbg_m_rw ? "R" : "W",
		            top->dbg_m_rw ? top->dbg_m_din : top->dbg_m_dout);
		ImGui::Text("      IRQ %d FIRQ %d NMI %d HALT %d   %ld instr",
		            !top->dbg_m_irqn, !top->dbg_m_firqn, !top->dbg_m_nmin,
		            !top->dbg_m_haltn, stat_m_instr);
		ImGui::Text("sub   pc $%04x  addr $%04x", top->dbg_s_pc, top->dbg_s_addr);
		ImGui::Text("      IRQ %d FIRQ %d NMI %d HALT %d BUSY %d   %ld instr",
		            !top->dbg_s_irqn, !top->dbg_s_firqn, !top->dbg_s_nmin,
		            !top->dbg_s_haltn, top->dbg_busy, stat_s_instr);
		ImGui::TextDisabled("  HALT toggles every line: MB60H010 stalls the sub");
		ImGui::TextDisabled("  CPU during active video (SVDHALT).");
	}

	if (ImGui::CollapsingHeader("Video", ImGuiTreeNodeFlags_DefaultOpen)) {
		char lbl[16];
		for (int i = 0; i < 8; i++) {
			snprintf(lbl, sizeof(lbl), "pal[%d]", i);
			draw_colour_swatch(lbl, pal_entry(i));
		}
		uint8_t vp = top->dbg_vpage;
		ImGui::Text("$fd37 = $%02x   VRAM access B%c R%c G%c   display B%c R%c G%c",
		            vp,
		            (vp & 0x01) ? '-' : '+', (vp & 0x02) ? '-' : '+', (vp & 0x04) ? '-' : '+',
		            (vp & 0x10) ? '-' : '+', (vp & 0x20) ? '-' : '+', (vp & 0x40) ? '-' : '+');
		ImGui::Text("scroll offset $%04x   display %s",
		            top->dbg_voffset, top->dbg_svdoffn ? "on" : "OFF");
	}

	if (ImGui::CollapsingHeader("Keyboard / tape", ImGuiTreeNodeFlags_DefaultOpen)) {
		ImGui::Text("kdata $%02x (P0=%d)  pending %d  KSTROBEn %d  $fd02 mask %d",
		            top->dbg_kdata, top->dbg_kp0, top->dbg_kpending,
		            top->dbg_kstroben, top->dbg_km77);
		ImGui::Text("tape motor %d  bit %d  sdram addr $%06x  rd %d",
		            top->dbg_tape_motor, top->dbg_tape_in,
		            top->dbg_tape_addr, top->dbg_tape_rd);
	}

	if (ImGui::CollapsingHeader("I/O port hit counts")) {
		if (ImGui::BeginTable("io", 3, ImGuiTableFlags_Borders | ImGuiTableFlags_SizingFixedFit)) {
			ImGui::TableSetupColumn("port");
			ImGui::TableSetupColumn("count");
			ImGui::TableSetupColumn("decoded");
			ImGui::TableHeadersRow();
			for (int p = 0; p < 256; p++) {
				if (!io_counts[p]) continue;
				ImGui::TableNextRow();
				ImGui::TableSetColumnIndex(0); ImGui::Text("$fd%02x", p);
				ImGui::TableSetColumnIndex(1); ImGui::Text("%ld", io_counts[p]);
				ImGui::TableSetColumnIndex(2); ImGui::Text("%s", port_is_decoded(p) ? "yes" : "NO");
			}
			ImGui::EndTable();
		}
		ImGui::TextDisabled("Counts every I/O cycle since start. --trace-io logs them.");
	}

	ImGui::Separator();
	ImGui::Checkbox("run", &run_enable);
	ImGui::SameLine();
	if (ImGui::Button("reset")) reset_hold = 20000;
	ImGui::SameLine();
	if (ImGui::Button("screenshot")) save_screenshot(video.count_frame);
	ImGui::Checkbox("tape audio", &opt_tape_audio);
	ImGui::SameLine();
	ImGui::Checkbox("tape rewind", &tape_rewind_pulse);
	ImGui::SliderInt("boot ROM", &opt_bootrom, 0, 3);

	ImGui::End();
}

static void draw_video_window() {
	ImGui::Begin("FM-7 video");
	ImGui::Text("%dx%d  %.1f fps", video.output_width, video.output_height, video.stats_fps);
	ImGui::Image(video.texture_id,
	             ImVec2(video.output_width * 1.0f, video.output_height * 2.0f));
	ImGui::End();
}
#endif

//----------------------------------------------------------------------------
// main
//----------------------------------------------------------------------------

int main(int argc, char** argv, char** env) {
	Verilated::commandArgs(argc, argv);
	if (parse_args(argc, argv)) return 0;

	top = new Vemu();

	// Hook the ioctl download engine up to the core's upload port.
	bus.ioctl_addr     = &top->ioctl_addr;
	bus.ioctl_index    = &top->ioctl_index;
	bus.ioctl_wait     = &top->ioctl_wait;
	bus.ioctl_download = &top->ioctl_download;
	bus.ioctl_wr       = &top->ioctl_wr;
	bus.ioctl_dout     = &top->ioctl_dout;
	input.ps2_key      = &top->ps2_key;

	// Block device -> the FDC. Only drive 0 is wired; sd_lba/sd_buff_din are
	// per-drive arrays in SimBlockDevice, so element 0 points at our scalars.
	blk.sd_lba[0]      = &top->sd_lba;
	blk.sd_buff_din[0] = &top->sd_buff_din;
	blk.sd_rd          = &top->sd_rd;
	blk.sd_wr          = &top->sd_wr;
	blk.sd_ack         = &top->sd_ack;
	blk.sd_buff_addr   = &top->sd_buff_addr;
	blk.sd_buff_dout   = &top->sd_buff_dout;
	blk.sd_buff_wr     = &top->sd_buff_wr;
	blk.img_mounted    = &top->img_mounted;
	blk.img_readonly   = &top->img_readonly;
	blk.img_size       = &top->img_size;

	if (!disk_path.empty()) {
		printf("Mounting disk on drive 0: %s\n", disk_path.c_str());
		blk.MountDisk(disk_path, 0);
	}

	if (!tape_path.empty()) {
		// CONF_STR "F1,t77,Load Tape" -> ioctl_index 1. t77_decode.v rewinds to
		// byte 16 (past the "XM7 TAPE IMAGE 0" header) when the download ends.
		printf("Mounting tape over ioctl index 1: %s\n", tape_path.c_str());
		bus.QueueDownload(tape_path, 1, true);
	}

	for (const KeyAction& a : key_actions) schedule_key_action(a);
	// SimInput drains its queue on a cycle timer. A frame is ~805k clk_sys
	// cycles, so this is short enough that a whole frame's press/release events
	// land inside that frame.
	input.keyEventWait = 4000;

	reset_prologue = 64;
	reset_hold = 20000;

	if (headless) {
		// SimVideo::Initialise allocates the framebuffer as part of GL setup,
		// which we are skipping, so do it by hand.
		output_ptr = (uint32_t*)calloc((size_t)FM7_WIDTH * FM7_HEIGHT, sizeof(uint32_t));
		if (!output_ptr) { fprintf(stderr, "Cannot allocate framebuffer\n"); return 1; }

		int last_reported = -1;
		while (true) {
			sim_cycle();
			if (stop_at_frame >= 0 && video.count_frame > stop_at_frame) break;
			// Progress ping so long runs don't look hung.
			if (video.count_frame != last_reported && (video.count_frame % 100) == 0) {
				last_reported = video.count_frame;
				printf("frame %d\n", video.count_frame);
				fflush(stdout);
			}
			if (stop_at_frame < 0 && video.count_frame > 100000) break;  // safety
		}
		printf("Finished at frame %d\n", video.count_frame);
		print_run_stats();
		for (int f : screenshot_frames)
			if (!screenshots_taken.count(f))
				printf("Warning: never reached frame %d for screenshot\n", f);
		if (trace_io_file) fclose(trace_io_file);
		top->final();
		return 0;
	}

#ifndef _MSC_VER
	if (video.Initialise("FM-7") == 1) return 1;
	audio.Initialise();

	bool done = false;
	while (!done) {
		SDL_Event event;
		while (SDL_PollEvent(&event)) {
			ImGui_ImplSDL2_ProcessEvent(&event);
			if (event.type == SDL_QUIT) done = true;
		}
		input.Read();

		// StartFrame only does the backend NewFrame calls; the ImGui frame
		// scope itself has to be opened here, and UpdateTexture() closes it
		// with ImGui::Render(). Calling Begin() outside this pair asserts.
		video.StartFrame();
		ImGui::NewFrame();

		if (run_enable) {
			// Run one video frame worth of clk_sys per UI frame.
			int start_frame = video.count_frame;
			int guard = 4 * 1000 * 1000;
			while (video.count_frame == start_frame && guard-- > 0) sim_cycle();
		}

		if (stop_at_frame >= 0 && video.count_frame > stop_at_frame) done = true;

		draw_video_window();
		draw_state_window();
		console.Draw("Console", nullptr, ImVec2(700, 300));

		video.UpdateTexture();
	}

	audio.CleanUp();
	video.CleanUp();
#endif

	if (trace_io_file) fclose(trace_io_file);
	top->final();
	delete top;
	return 0;
}
