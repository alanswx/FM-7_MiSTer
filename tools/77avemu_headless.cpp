// Fixed-step, no-window driver for CaptainYS's 77AVEMU/Mutsu.
//
// This file intentionally lives in the FM-7 core repository rather than in
// refs/77AVEMU (refs/ is ignored).  build_77avemu_headless.sh compiles it
// against a locally-built 77AVEMU tree.

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "fm77av.h"
#include "fm77avkey.h"
#include "fm77avparam.h"
#include "fm77avrender.h"
#include "outside_world.h"
#include "yspngenc.h"

class NullWindow final : public Outside_World::WindowInterface
{
public:
    void Start(void) override {}
    void Stop(void) override {}
    void Interval(void) override {}
    void Communicate(Outside_World *) override {}
    void Render(bool) override {}
    void Render(const FM77AVRender::Image &, const FM77AV &) override {}
    bool ImageNeedsFlip(void) override { return false; }
};

class NullSound final : public Outside_World::Sound
{
public:
    void Start(void) override {}
    void Stop(void) override {}
    void Polling(void) override {}
    void FMPSGPlay(std::vector<unsigned char> &) override {}
    void FMPSGPlayStop(void) override {}
    bool FMPSGChannelPlaying(void) override { return false; }
};

class NullWorld final : public Outside_World
{
public:
    std::string GetProgramResourceDirectory(void) const override { return "."; }
    void Start(void) override {}
    void Stop(void) override {}
    void DevicePolling(FM77AV &) override {}
    void SetKeyboardLayout(unsigned int) override {}
    // No `override` on these two deliberately. 77AVEMU removed
    // EnableDiffMouse/ToggleDiffMouse from Outside_World after the build this
    // harness was first written against; with `override` the file stops
    // compiling on the newer tree, and without it it compiles on both -- the
    // keyword is optional where the base still declares them pure virtual, and
    // the methods are simply unused where it does not.
    void EnableDiffMouse(bool) {}
    void ToggleDiffMouse(void) {}
    WindowInterface *CreateWindowInterface(void) const override { return new NullWindow; }
    void DeleteWindowInterface(WindowInterface *p) const override { delete p; }
    Sound *CreateSound(void) const override { return new NullSound; }
    void DeleteSound(Sound *p) const override { delete p; }
};

// ---------------------------------------------------------------------------
// Frame-scheduled input, deliberately the same shape as vsim's --key and
// --joystick.
//
// The two machines have no common instruction count -- they do not even agree
// on the main CPU's clock -- but they do agree on wall-clock machine time, so a
// "frame" here is 1/60 s of vm->state.fm77avTime rather than a raster frame.
//
// THE TWO FRAME UNITS ARE NOT THE SAME LENGTH, and this comment used to claim
// they were ("a frame is 1/60 s of machine time, so the numbers mean the same
// thing here and in vsim" -- wrong by 0.61 %). A frame here is exactly 1/60 s.
// A vsim frame is a real raster frame off the core's video timing, 16 MHz over
// a 1024 x 262 raster (sim_main.cpp:73), i.e. 59.63740 Hz. So
//
//     reference_frame = vsim_frame * 60 * 1024 * 262 / 16000000
//                     = vsim_frame * 1.00608          (exact, not a rounding)
//
// which is +6 frames per 1000: below noise at the 620-frame gate (620 -> 624),
// 12 frames at the sweep's 2000 (-> 2012), 22 at 3700 (-> 3722). Scale the
// number before passing it to --key/--joystick/--shot-every/--stop-at-frame if
// you want the same instant as a vsim frame; do not scale it if you are just
// quoting machine time.
//
// Why this exists: finding out how to start a game is a question about the
// SOFTWARE, not about our RTL, so it should be answered on the known-good
// machine first. Answering it on the core under test conflates "we typed the
// wrong key" with "the core dropped the key".
struct InputEvent
{
    unsigned long long frame;      // 1/60 s of machine time
    bool               isJoystick;
    int                keyCode;    // AVKEY_*, for key events
    unsigned int       keyFlags;   // FM77AVKeyboard::KEYFLAG_SHIFT/_CTRL/_GRAPH
    unsigned int       buttons;    // bit0 up, 1 down, 2 left, 3 right, 4 A, 5 B
    bool               press;      // press or release
    bool               fired;
};

// SHIFT/CTRL/GRAPH are NOT keys you can press here. FM77AVKeyboard::Press takes
// the modifier state as its first argument (fm77avkeyboard.cpp:498-500) and
// pressing AVKEY_LEFT_SHIFT as an ordinary key sets heldDown[] and produces
// nothing -- so scheduling a shift key around a character silently types the
// UNSHIFTED one. That is not hypothetical: it turned `print 12+34` into
// `print 12;34` and `print "HI!"` into `print 2hi12`, which looks like a
// keyboard bug in whatever is being tested rather than a harness limitation.
// Hence the "SHIFT+" / "CTRL+" / "GRAPH+" prefix on --key.
static bool ParseKeyModifier(std::string &name, unsigned int &flags)
{
    for (;;)
    {
        const auto plus = name.find('+');
        if (plus == std::string::npos || 0 == plus) return true;
        const std::string mod = name.substr(0, plus);
        if      (mod == "SHIFT") flags |= FM77AVKeyboard::KEYFLAG_SHIFT;
        else if (mod == "CTRL")  flags |= FM77AVKeyboard::KEYFLAG_CTRL;
        else if (mod == "GRAPH") flags |= FM77AVKeyboard::KEYFLAG_GRAPH;
        else return false;
        name = name.substr(plus + 1);
    }
}

static const unsigned long long FRAME_NS = 1000000000ULL / 60ULL;

static bool ParseFrameArg(const std::string &s, unsigned long long &frame, std::string &rest)
{
    const auto colon = s.find(':');
    if (colon == std::string::npos) return false;
    frame = std::strtoull(s.substr(0, colon).c_str(), nullptr, 10);
    rest = s.substr(colon + 1);
    return true;
}

static unsigned int ParseButtons(const std::string &spec)
{
    unsigned int b = 0;
    size_t pos = 0;
    while (pos <= spec.size())
    {
        const auto plus = spec.find('+', pos);
        const std::string tok = spec.substr(pos, plus == std::string::npos ? std::string::npos : plus - pos);
        if      (tok == "up")    b |= 1u << 0;
        else if (tok == "down")  b |= 1u << 1;
        else if (tok == "left")  b |= 1u << 2;
        else if (tok == "right") b |= 1u << 3;
        else if (tok == "a")     b |= 1u << 4;
        else if (tok == "b")     b |= 1u << 5;
        else if (tok != "none" && !tok.empty())
            std::cerr << "unknown joystick button: " << tok << "\n";
        if (plus == std::string::npos) break;
        pos = plus + 1;
    }
    return b;
}

static void Usage(const char *argv0)
{
    std::cerr << "usage: " << argv0
              << " ROMDIR MEDIA [steps] [screenshot.png] [options]\n";
    std::cerr << "  MEDIA is a .d77/.d88 disk or .t77 tape image.\n";
    std::cerr << "  steps are 6809 instructions and may be omitted entirely when\n";
    std::cerr << "  --stop-at-frame is given; a positional that is not all digits is\n";
    std::cerr << "  taken as the screenshot name.\n";
    std::cerr << "  --fm7                  run as an FM-7 rather than an FM77AV\n";
    std::cerr << "  --no-autostart         do not type the tape start command\n";
    std::cerr << "  --key F:NAME[:HOLD]    press a key at frame F for HOLD frames\n";
    std::cerr << "                         (default 20). NAME is 77AVEMU's own\n";
    std::cerr << "                         label -- RETURN A Z 1 PF1 MINUS\n";
    std::cerr << "                         SEMICOLON MID_SPACE ... (there is no\n";
    std::cerr << "                         plain SPACE: the FM-7 has LEFT_SPACE,\n";
    std::cerr << "                         MID_SPACE and RIGHT_SPACE, and the\n";
    std::cerr << "                         function keys are PF1..PF10).\n";
    std::cerr << "                         Modifiers are a PREFIX, not their own\n";
    std::cerr << "                         key: SHIFT+2 CTRL+C GRAPH+A. Pressing\n";
    std::cerr << "                         LEFT_SHIFT as a key does nothing.\n";
    std::cerr << "  --joystick F:B[:HOLD]  press stick 1 at frame F. B is\n";
    std::cerr << "                         '+'-separated: up down left right a b\n";
    std::cerr << "  --shot-every N         also write screenshot.NNNN.png every N frames\n";
    std::cerr << "  --stop-at-frame N      end the run at machine-time frame N, so the\n";
    std::cerr << "                         final screenshot is taken at a KNOWN instant\n";
    std::cerr << "                         rather than after a given instruction count.\n";
    std::cerr << "                         `steps` stays a backstop; without an explicit\n";
    std::cerr << "                         steps it is raised to 100000 per frame asked\n";
    std::cerr << "                         for, so a wedged run still cannot spin forever.\n";
    std::cerr << "  --trace-io             log every main-CPU $FDxx access, and every\n";
    std::cerr << "                         sub-CPU $D4xx one, as IOWRITE/IOREAD lines.\n";
    std::cerr << "                         Feed both sides to tools/iodiff.py to find\n";
    std::cerr << "                         where this core and the reference part company.\n";
    std::cerr << "  A frame is 1/60 s of MACHINE time. That is NOT the same length as a\n";
    std::cerr << "  vsim frame, which is a 59.63740 Hz raster frame: multiply a vsim frame\n";
    std::cerr << "  number by 1.00608 to get the equivalent frame here (620 -> 624,\n";
    std::cerr << "  2000 -> 2012, 3700 -> 3722).\n";
}

// The positional `steps` argument is optional, so a bare positional has to be
// told apart from a file name rather than fed to strtoull and silently read as
// zero.
static bool IsNumber(const std::string &s)
{
    if (s.empty()) return false;
    // strtoull(.., 0) only reads hex behind an explicit 0x, so anything else
    // must be all decimal digits -- otherwise a screenshot called "ref.png"
    // parses as 0 and the run does nothing.
    const bool hex = (s.size() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'));
    for (size_t i = (hex ? 2 : 0); i < s.size(); ++i)
    {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        if (!(hex ? std::isxdigit(c) : std::isdigit(c))) return false;
    }
    return true;
}

static bool HasSuffix(const std::string &s, const char *suffix)
{
    const auto n = std::string(suffix).size();
    return s.size() >= n && s.compare(s.size() - n, n, suffix) == 0;
}

int main(int argc, char **argv)
{
    if (argc < 3)
    {
        Usage(argv[0]);
        return 2;
    }

    const std::string romDir = argv[1];
    const std::string media = argv[2];
    unsigned long long steps = 2000000;
    std::string screenshot;
    bool fm7 = false;
    bool autoStartTape = true;

    std::vector<InputEvent> events;
    unsigned long long shotEvery = 0;

    // --stop-at-frame ends the run at a machine-time instant instead of after an
    // instruction count, which is the only way to render the reference at the
    // SAME moment as a vsim shot (docs/REFERENCE.md traps 42 and 49: comparing a
    // fixed-step reference against a fixed-frame core render reported a 32-point
    // improvement as a 9-point regression). `steps` remains the backstop.
    unsigned long long stopAtFrame = 0;
    bool stopAtFrameSet = false;
    bool stepsGiven = false;

    bool traceIO = false;
    int positional = 0;
    for (int i = 3; i < argc; ++i)
    {
        const std::string arg = argv[i];
        if (arg == "--fm7")
        {
            fm7 = true;
        }
        else if (arg == "--no-autostart")
        {
            autoStartTape = false;
        }
        else if (arg == "--key" && i + 1 < argc)
        {
            unsigned long long f; std::string rest;
            if (!ParseFrameArg(argv[++i], f, rest)) { Usage(argv[0]); return 2; }
            unsigned long long hold = 20;
            const auto c2 = rest.find(':');
            if (c2 != std::string::npos)
            {
                hold = std::strtoull(rest.substr(c2 + 1).c_str(), nullptr, 10);
                rest = rest.substr(0, c2);
            }
            unsigned int flags = 0;
            if (!ParseKeyModifier(rest, flags))
            {
                std::cerr << "unknown key modifier in: " << rest << "\n";
                return 2;
            }
            const int code = FM77AVKeyLabelToKeyCode(rest);
            if (code <= 0)
            {
                std::cerr << "unknown key name: " << rest << "\n";
                return 2;
            }
            events.push_back({f,        false, code, flags, 0, true,  false});
            events.push_back({f + hold, false, code, flags, 0, false, false});
        }
        else if (arg == "--joystick" && i + 1 < argc)
        {
            unsigned long long f; std::string rest;
            if (!ParseFrameArg(argv[++i], f, rest)) { Usage(argv[0]); return 2; }
            unsigned long long hold = 60;
            const auto c2 = rest.find(':');
            if (c2 != std::string::npos)
            {
                hold = std::strtoull(rest.substr(c2 + 1).c_str(), nullptr, 10);
                rest = rest.substr(0, c2);
            }
            const unsigned int b = ParseButtons(rest);
            events.push_back({f,        true, 0, 0, b, true,  false});
            events.push_back({f + hold, true, 0, 0, 0, false, false});
        }
        else if (arg == "--shot-every" && i + 1 < argc)
        {
            shotEvery = std::strtoull(argv[++i], nullptr, 10);
        }
        else if (arg == "--stop-at-frame" && i + 1 < argc)
        {
            stopAtFrame = std::strtoull(argv[++i], nullptr, 10);
            stopAtFrameSet = true;
        }
        else if (arg == "--trace-io")
        {
            traceIO = true;
        }
        else if (positional == 0 && IsNumber(arg))
        {
            steps = std::strtoull(arg.c_str(), nullptr, 0);
            stepsGiven = true;
            ++positional;
        }
        else if (positional == 0)
        {
            // `steps` is optional now that --stop-at-frame exists, so
            // `... --stop-at-frame 624 shot.png` has to work. Without this,
            // strtoull("shot.png") returned 0, the run executed ZERO
            // instructions, and the screenshot slot was never filled -- a
            // successful exit with no output and no complaint.
            screenshot = arg;
            positional = 2;
        }
        else if (positional == 1)
        {
            screenshot = arg;
            ++positional;
        }
        else
        {
            Usage(argv[0]);
            return 2;
        }
    }

    // The default `steps` (2,000,000) is ~2.2 s of machine time, i.e. about 130
    // frames -- far short of any frame worth stopping at. If a stop frame was
    // asked for and no explicit step count was given, size the backstop off the
    // frame instead: 20,000,000 steps is ~1320 frames (trap 42), so ~15,000
    // steps per frame is the real rate and 100,000 leaves a 6x margin for a
    // title that runs the CPU slowly. The loop still exits on machine time; this
    // only stops a pathological run from spinning forever.
    if (stopAtFrameSet && !stepsGiven)
    {
        steps = stopAtFrame * 100000ULL + 1000000ULL;
    }

    FM77AVParam param;
    param.ROMPath = romDir;
    param.machineType = (fm7 ? MACHINETYPE_FM7 : MACHINETYPE_FM77AV);
    param.noWait = true;
    if (HasSuffix(media, ".t77") || HasSuffix(media, ".T77"))
    {
        param.t77Path = media;
        // Let 77AVEMU start the tape itself. autoLoadTapeFile makes it watch the
        // sub-system shared RAM for command $04 -- the machine saying BASIC has
        // reached the point where a load command will take -- and type the start
        // command exactly then (fm77avio.cpp:100-109). This was false, and the
        // crude fallback below typed it after a fixed 500000 instructions
        // instead, which is not the same moment: under that scheme the reference
        // never got a tape moving at all (motor off, tape_ptr=0 on every image
        // tried, commercial or generated), so there was no reference to compare
        // this core's cassette path against.
        param.autoLoadTapeFile = true;
    }
    else
    {
        param.fdImgFName[0] = media;
        // Honour the image's own write-protect flag -- do NOT force it on.
        //
        // This was `true`, which made the reference report WRITE PROTECT in
        // $FD18 b6 for every title regardless of the disk. 77AVEMU reads the
        // real flag (DiskDrive::WriteProtected -> DiskImage::WriteProtected ->
        // d77.GetDisk(idx)->IsWriteProtected(), i.e. `0 != d77Img[0x1a]`) and
        // every image in the collection checked so far has 0x1a = 0x00, so the
        // override was inventing a difference this core was then blamed for:
        // Shounen Mike's $FD18 read 97 x $40 and 6 x $44 with it on, and
        // 1385 x $00 / 7 x $04 with it off, which is this core's own profile.
        //
        // Safe: SaveModifiedDiskImages() is only reached from 77AVEMU's GUI
        // thread runner, never from here, so nothing is written back to the
        // .d77 files. Verified render-identical on Woody Poco and Shounen Mike.
        param.fdImgWriteProtect[0] = false;
    }

    NullWorld world;
    NullWindow window;
    std::unique_ptr<FM77AV> vm(new FM77AV);

    // 77AVEMU already logs any I/O access we ask it to -- FM77AV::IOWrite and
    // ::IORead each open with a monitor check (fm77avio.cpp:9 and :636) and
    // print `IOWRITE MAIN:pc IO:fdxx VALUE:vv`. Switching every port on turns
    // that into a full bus trace, with no change to the upstream tree: refs/ is
    // gitignored, so a patch there would not survive a rebuild.
    //
    // This is the reference half of the differential tracer. Ours comes from
    // `vsim --trace-io`, which already prints the same four fields.
    if (traceIO)
    {
        for (int i = 0; i < 256; ++i)
        {
            vm->var.monitorIOReadMain[i]  = true;
            vm->var.monitorIOWriteMain[i] = true;
            vm->var.monitorIOReadSub[i]   = true;
            vm->var.monitorIOWriteSub[i]  = true;
        }
    }
    if (!vm->SetUp(param, &world, &window))
    {
        std::cerr << "77AVEMU setup failed\n";
        return 1;
    }

    // SetUp does NOT give the data recorder its Outside_World, and the recorder
    // dereferences it the moment a tape moves:
    //
    //     void FM77AVDataRecorder::Move(uint64_t t) {
    //       if (state.motor && !state.primary.ptr.eot) {
    //         ...
    //         outside_world->indicatedTapePosition = state.primary.ptr.dataPtr;
    //
    // The only assignment upstream is in FM77AVThread (fm77avthread.cpp:45),
    // which is the GUI runner this harness does not use, so the pointer stayed
    // null (fm77avtape.h:103) and every tape run died of SIGSEGV the first time
    // the motor turned. It is a tape-only path -- disks never touch it -- which
    // is why this went unnoticed while every disk render worked, and why there
    // has never been a reference tape screenshot to compare against.
    vm->dataRecorder.outside_world = &world;
    // The disk boot path clears the reset-time busy latch through the normal
    // sub-monitor handshake; leave it clear so the headless run follows the
    // same path as the simulator.
    vm->state.subSysBusy = false;

    unsigned long long mainCount = 0;
    unsigned long long lastShotBucket = ~0ULL;
    bool tapeStarted = false;
    bool hitStopFrame = false;
    unsigned long long i = 0;
    for (; i < steps; ++i)
    {
        const auto oldPc = vm->mainCPU.state.PC;
        vm->RunOneInstruction();
        if (oldPc != vm->mainCPU.state.PC)
        {
            ++mainCount;
        }

        if (!tapeStarted && autoStartTape && !param.t77Path.empty() && mainCount >= 500000)
        {
            vm->TypeCommandForStartingTapeProgram();
            tapeStarted = true;
            std::cerr << "autostart main_count=" << mainCount << " step=" << i << "\n";
        }

        vm->ProcessInterrupts();
        vm->RunFastDevicePolling();
        vm->RunScheduledTasks(vm->state.fm77avTime);

        // Periodic screenshots, so an attract sequence can be watched rather
        // than guessed at. Thexder's runs for MINUTES of machine time -- title,
        // then credits -- which is far past anything a Verilator run reaches,
        // and is why it looks unresponsive there.
        if (0 != shotEvery && !screenshot.empty())
        {
            const unsigned long long f = vm->state.fm77avTime / FRAME_NS;
            if (f / shotEvery != lastShotBucket)
            {
                lastShotBucket = f / shotEvery;
                FM77AVRender r;
                vm->RenderQuiet(r);
                const auto img = r.GetImage();
                char name[1024];
                std::string stem = screenshot;
                const auto dot = stem.rfind('.');
                if (dot != std::string::npos) stem = stem.substr(0, dot);
                snprintf(name, sizeof(name), "%s.%06llu.png", stem.c_str(), f);
                YsRawPngEncoder enc;
                enc.EncodeToFile(name, img.wid, img.hei, 8, 6, img.rgba);
            }
        }

        // Deliver anything scheduled for a frame we have now reached. Driven off
        // machine time rather than the step counter so the frame numbers mean
        // the same thing as vsim's.
        const unsigned long long frameNow = vm->state.fm77avTime / FRAME_NS;
        for (auto &e : events)
        {
            if (e.fired || e.frame > frameNow) continue;
            e.fired = true;
            if (e.isJoystick)
            {
                // Port 0 is stick 1, the one vsim's --joystick drives.
                auto &port = vm->gameport.state.ports[0];
                port.device = FM77AVGamePort::GAMEPAD;
                port.SetGamePadState(0 != (e.buttons & (1u << 4)),   // A
                                     0 != (e.buttons & (1u << 5)),   // B
                                     0 != (e.buttons & (1u << 2)),   // left
                                     0 != (e.buttons & (1u << 3)),   // right
                                     0 != (e.buttons & (1u << 0)),   // up
                                     0 != (e.buttons & (1u << 1)),   // down
                                     false, false, vm->state.fm77avTime);
                std::cerr << "INPUT frame=" << e.frame << " joystick="
                          << (e.press ? e.buttons : 0u) << "\n";
            }
            else if (e.press)
            {
                vm->keyboard.Press(e.keyFlags, e.keyCode);
                std::cerr << "INPUT frame=" << e.frame << " press key=" << e.keyCode
                          << " flags=" << e.keyFlags << "\n";
            }
            else
            {
                vm->keyboard.Release(e.keyFlags, e.keyCode);
            }
        }

        if (0 == (i % 100000ULL))
        {
            std::cout << "REF step=" << i
                      << " time=" << vm->state.fm77avTime
                      << " main_count=" << mainCount
                      << " pc=$" << std::hex << vm->mainCPU.state.PC
                      << " sub=$" << vm->subCPU.state.PC
                      << " motor=" << std::dec << vm->dataRecorder.state.motor
                      << " tape_ptr=" << vm->dataRecorder.state.primary.ptr.dataPtr
                      << "\n";
        }

        // Last thing in the body, so everything scheduled for this frame -- the
        // input events and the --shot-every capture above -- has already run.
        if (stopAtFrameSet && frameNow >= stopAtFrame)
        {
            hitStopFrame = true;
            ++i;                 // count the step we just executed
            break;
        }
    }

    const unsigned long long endFrame = vm->state.fm77avTime / FRAME_NS;
    if (stopAtFrameSet && !hitStopFrame)
    {
        // Say so rather than silently handing back a screenshot from the wrong
        // instant -- an early stop is exactly what a wedged run looks like.
        std::cerr << "WARNING: step backstop (" << steps << ") hit at frame "
                  << endFrame << " before --stop-at-frame " << stopAtFrame
                  << "; the screenshot is NOT at the requested instant\n";
    }

    // Optional main-memory dump, the counterpart of the VRAM dump below.
    // docs/REFERENCE.md trap 19: when a screen is wrong, dump the bytes and diff
    // them before theorising about the thing that draws them. The same applies
    // to a CPU stuck on a flag -- "what is at $2432 on a machine that gets past
    // this" is a question a dump answers and a disassembly argues about.
    //
    // Writes the whole 256 KB physical space, so a main-CPU address needs its
    // MMR mapping applied: with MMR off the FM-7 machine page is $30000, i.e.
    // main $2432 is at offset $32432.
    if (const char *memOut = std::getenv("FM77AV_MEM_DUMP"))
    {
        FILE *fp = fopen(memOut, "wb");
        if (nullptr == fp)
        {
            std::cerr << "mem dump failed: " << memOut << "\n";
            return 1;
        }
        fwrite(vm->physMem.state.data, 1, sizeof(vm->physMem.state.data), fp);
        fclose(fp);
        std::cerr << "mem dump: " << memOut << " ("
                  << sizeof(vm->physMem.state.data) << " bytes)\n";
    }

    // Optional VRAM dump for differential triage against the Verilator core.
    // Emits bank 0 then bank 1, each 0xC000 bytes: blue, red, green in order.
    if (const char *vramOut = std::getenv("FM77AV_VRAM_DUMP"))
    {
        FILE *fp = fopen(vramOut, "wb");
        if (nullptr == fp)
        {
            std::cerr << "vram dump failed: " << vramOut << "\n";
            return 1;
        }
        for (int bank = 0; bank < 2; ++bank)
        {
            const uint8_t *p = vm->physMem.GetVRAMBank(bank);
            fwrite(p, 1, vm->physMem.GetVRAMBankSize(bank), fp);
        }
        fclose(fp);
        std::cerr << "vram dump: " << vramOut << "\n";
    }

    if (!screenshot.empty())
    {
        FM77AVRender render;
        vm->RenderQuiet(render);
        const auto image = render.GetImage();
        YsRawPngEncoder encoder;
        if (YSOK != encoder.EncodeToFile(screenshot.c_str(), image.wid, image.hei, 8, 6, image.rgba))
        {
            std::cerr << "screenshot failed: " << screenshot << "\n";
            return 1;
        }
    }

    // Did the software ever READ the gamepad? Port::Read() stamps lastAccessTime
    // and PowerOn() zeroes it, so a non-zero value is proof the title polls the
    // stick -- no instrumentation needed, and far cheaper than looking for it in
    // a Verilator run.
    //
    // Note what this can and cannot see. 77AVEMU routes the gameport ONLY through
    // the $FD15/$FD16 YM2203 window (fm77avsound.cpp:182-186); a read of PSG
    // register 14 through the $FD0D/$FD0E AY window returns the AY's own register
    // (:428) and never reaches the port. That matches CaptainYS's note in
    // fm77avkeyboard.h -- gamepads became common "after Fujitsu released YM2203C
    // expansion card" -- so on a base FM-7 this probe reads 0 for almost
    // everything, and that is a fact about the machine, not a gap in the probe.
    std::cout << "GAMEPORT port0_last_read=" << vm->gameport.state.ports[0].lastAccessTime
              << " port1_last_read=" << vm->gameport.state.ports[1].lastAccessTime
              << "\n";

    std::cout << "RESULT steps=" << i
              << " steps_cap=" << steps
              << " frame=" << endFrame
              << " time=" << vm->state.fm77avTime
              << " main_count=" << mainCount
              << " pc=$" << std::hex << vm->mainCPU.state.PC
              << " sub=$" << vm->subCPU.state.PC
              << " motor=" << std::dec << vm->dataRecorder.state.motor
              << " tape_ptr=" << vm->dataRecorder.state.primary.ptr.dataPtr
              << "\n";
    return 0;
}
