// Fixed-step, no-window driver for CaptainYS's 77AVEMU/Mutsu.
//
// This file intentionally lives in the FM-7 core repository rather than in
// refs/77AVEMU (refs/ is ignored).  build_77avemu_headless.sh compiles it
// against a locally-built 77AVEMU tree.

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
    void EnableDiffMouse(bool) override {}
    void ToggleDiffMouse(void) override {}
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
// That makes a sequence portable: the same numbers drive the reference and the
// core, and "it starts on the reference at frame 700" is directly checkable
// against vsim at frame 700.
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
    unsigned int       buttons;    // bit0 up, 1 down, 2 left, 3 right, 4 A, 5 B
    bool               press;      // press or release
    bool               fired;
};

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
    std::cerr << "  --fm7                  run as an FM-7 rather than an FM77AV\n";
    std::cerr << "  --no-autostart         do not type the tape start command\n";
    std::cerr << "  --key F:NAME[:HOLD]    press a key at frame F for HOLD frames\n";
    std::cerr << "                         (default 20). NAME is 77AVEMU's own\n";
    std::cerr << "                         label: SPACE RETURN A Z 1 F1 ...\n";
    std::cerr << "  --joystick F:B[:HOLD]  press stick 1 at frame F. B is\n";
    std::cerr << "                         '+'-separated: up down left right a b\n";
    std::cerr << "  --shot-every N         also write screenshot.NNNN.png every N frames\n";
    std::cerr << "  A frame is 1/60 s of MACHINE time, so the numbers mean the same\n";
    std::cerr << "  thing here and in vsim.\n";
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
            const int code = FM77AVKeyLabelToKeyCode(rest);
            if (code <= 0)
            {
                std::cerr << "unknown key name: " << rest << "\n";
                return 2;
            }
            events.push_back({f,        false, code, 0, true,  false});
            events.push_back({f + hold, false, code, 0, false, false});
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
            events.push_back({f,        true, 0, b, true,  false});
            events.push_back({f + hold, true, 0, 0, false, false});
        }
        else if (arg == "--shot-every" && i + 1 < argc)
        {
            shotEvery = std::strtoull(argv[++i], nullptr, 10);
        }
        else if (positional == 0)
        {
            steps = std::strtoull(arg.c_str(), nullptr, 0);
            ++positional;
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

    FM77AVParam param;
    param.ROMPath = romDir;
    param.machineType = (fm7 ? MACHINETYPE_FM7 : MACHINETYPE_FM77AV);
    param.noWait = true;
    if (HasSuffix(media, ".t77") || HasSuffix(media, ".T77"))
    {
        param.t77Path = media;
        param.autoLoadTapeFile = false;
    }
    else
    {
        param.fdImgFName[0] = media;
        param.fdImgWriteProtect[0] = true;
    }

    NullWorld world;
    NullWindow window;
    std::unique_ptr<FM77AV> vm(new FM77AV);
    if (!vm->SetUp(param, &world, &window))
    {
        std::cerr << "77AVEMU setup failed\n";
        return 1;
    }
    // The disk boot path clears the reset-time busy latch through the normal
    // sub-monitor handshake; leave it clear so the headless run follows the
    // same path as the simulator.
    vm->state.subSysBusy = false;

    unsigned long long mainCount = 0;
    unsigned long long lastShotBucket = ~0ULL;
    bool tapeStarted = false;
    for (unsigned long long i = 0; i < steps; ++i)
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
                vm->keyboard.Press(0, e.keyCode);
                std::cerr << "INPUT frame=" << e.frame << " press key=" << e.keyCode << "\n";
            }
            else
            {
                vm->keyboard.Release(0, e.keyCode);
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

    std::cout << "RESULT steps=" << steps
              << " time=" << vm->state.fm77avTime
              << " main_count=" << mainCount
              << " pc=$" << std::hex << vm->mainCPU.state.PC
              << " sub=$" << vm->subCPU.state.PC
              << " motor=" << std::dec << vm->dataRecorder.state.motor
              << " tape_ptr=" << vm->dataRecorder.state.primary.ptr.dataPtr
              << "\n";
    return 0;
}
