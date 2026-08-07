#include "../BoxedArpAU/DSP/BoxedArpKernel.hpp"
#include <iostream>
#include <vector>

using namespace boxedarp;

static void collect(void* ctx, const MidiEvent& e) {
    static_cast<std::vector<MidiEvent>*>(ctx)->push_back(e);
}

int main() {
    ArpKernel arp;
    Parameters p;
    p.pattern = Pattern::Up;
    p.division = Division::Sixteenth;
    p.octaves = 1;
    p.gate = 0.5f;
    arp.setParameters(p);

    MidiEvent in[] = {
        {0, 0x90, 60, 100},
        {0, 0x90, 64, 100},
        {0, 0x90, 67, 100}
    };

    std::vector<MidiEvent> out;
    const double sr = 48000.0;
    const double bpm = 120.0;
    // One beat = 24000 samples. Render 1 beat in 512-frame blocks.
    int64_t sample = 0;
    double beat = 0.0;
    for (int block = 0; block < 47; ++block) {
        const int frames = (block == 46) ? 448 : 512;
        arp.processBlock(sample,
                         frames,
                         sr,
                         bpm,
                         beat,
                         block == 0 ? in : nullptr,
                         block == 0 ? 3 : 0,
                         collect,
                         &out);
        sample += frames;
        beat += double(frames) / (sr * 60.0 / bpm);
    }

    int ons = 0;
    std::cout << "Generated MIDI:\n";
    for (auto& e : out) {
        if ((e.status & 0xF0) == 0x90 && e.data2 > 0) {
            ++ons;
            std::cout << "ON  note=" << int(e.data1) << " offset=" << e.sampleOffset << "\n";
        }
    }
    std::cout << "note-ons=" << ons << "\n";
    return ons >= 3 ? 0 : 1;
}
