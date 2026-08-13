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

#include "fm77av.h"
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

static void Usage(const char *argv0)
{
    std::cerr << "usage: " << argv0
              << " ROMDIR MEDIA [steps] [screenshot.png] [--fm7] [--no-autostart]\n";
    std::cerr << "  MEDIA is a .d77/.d88 disk or .t77 tape image.\n";
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
