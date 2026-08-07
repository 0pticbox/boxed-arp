#pragma once

#include <array>
#include <cstdint>

namespace boxedarp {

struct MidiEvent {
    int32_t sampleOffset = 0;
    uint8_t status = 0;
    uint8_t data1 = 0;
    uint8_t data2 = 0;
};

using MidiEmitFn = void(*)(void* context, const MidiEvent& event);

enum class Pattern : uint8_t {
    Up = 0,
    Down,
    UpDown,
    Random
};

enum class Division : uint8_t {
    Quarter = 0,
    Eighth,
    EighthTriplet,
    Sixteenth,
    SixteenthTriplet,
    ThirtySecond,
    ThirtySecondTriplet,
    SixtyFourth,
    SixtyFourthTriplet
};

struct Parameters {
    Pattern pattern = Pattern::Up;
    Division division = Division::Sixteenth;
    int octaves = 1;              // 1...4
    float gate = 0.72f;           // 0.05...0.98
    float swing = 0.0f;           // 0...0.45 (delays every second step)
    bool latch = false;
    bool hostSync = true;
    double freeBPM = 120.0;

    bool scaleLock = false;
    uint8_t rootPitchClass = 0;   // C = 0
    uint16_t scaleMask = 0x0FFF;  // 12-bit pitch-class mask
};

class ArpKernel {
public:
    ArpKernel();

    void reset();
    void setParameters(const Parameters& p);
    const Parameters& parameters() const { return params_; }

    // Process one host render block.
    // input events must be ordered by sampleOffset.
    void processBlock(
        int64_t blockStartSampleTime,
        int32_t frameCount,
        double sampleRate,
        double hostTempo,
        double hostBeatPosition,
        const MidiEvent* input,
        int32_t inputCount,
        MidiEmitFn emit,
        void* emitContext);

private:
    struct HeldNote {
        uint8_t note = 0;
        uint8_t velocity = 0;
        bool down = false;
    };

    Parameters params_{};
    std::array<HeldNote, 128> held_{};
    std::array<uint8_t, 128> latched_{};
    std::array<uint8_t, 128> latchedVelocity_{};

    bool hadAnyPhysicalDown_ = false;
    int sequenceIndex_ = -1;
    int upDownDirection_ = 1;
    uint32_t rng_ = 0x9E3779B9u;

    bool activeOutput_ = false;
    uint8_t activeOutputNote_ = 0;
    int64_t pendingOffSampleTime_ = -1;
    int64_t lastStepOrdinal_ = INT64_MIN;

    static double beatsPerStep(Division division);
    static int clampInt(int v, int lo, int hi);
    static float clampFloat(float v, float lo, float hi);

    void handleInput(const MidiEvent& event, MidiEmitFn emit, void* ctx);
    void noteOn(uint8_t note, uint8_t velocity);
    void noteOff(uint8_t note);
    bool anyPhysicalDown() const;
    int collectSequence(std::array<uint8_t, 128>& notes, std::array<uint8_t, 128>& velocities) const;
    uint8_t quantizeToScale(uint8_t midiNote) const;
    int chooseSequenceIndex(int count);
    uint32_t nextRandom();

    void emitNoteOffAt(int32_t sampleOffset, MidiEmitFn emit, void* ctx);
    void triggerStepAt(int32_t sampleOffset,
                       int64_t absoluteSample,
                       int64_t stepOrdinal,
                       double stepSamples,
                       MidiEmitFn emit,
                       void* ctx);
};

// Handy built-in 12-bit masks, relative to root.
namespace ScaleMask {
    constexpr uint16_t Chromatic = 0x0FFF;
    constexpr uint16_t Major     = (1u<<0)|(1u<<2)|(1u<<4)|(1u<<5)|(1u<<7)|(1u<<9)|(1u<<11);
    constexpr uint16_t Minor     = (1u<<0)|(1u<<2)|(1u<<3)|(1u<<5)|(1u<<7)|(1u<<8)|(1u<<10);
    constexpr uint16_t Dorian    = (1u<<0)|(1u<<2)|(1u<<3)|(1u<<5)|(1u<<7)|(1u<<9)|(1u<<10);
    constexpr uint16_t Lydian    = (1u<<0)|(1u<<2)|(1u<<4)|(1u<<6)|(1u<<7)|(1u<<9)|(1u<<11);
    constexpr uint16_t Hirajoshi = (1u<<0)|(1u<<2)|(1u<<3)|(1u<<7)|(1u<<8);
    constexpr uint16_t Bhairav   = (1u<<0)|(1u<<1)|(1u<<4)|(1u<<5)|(1u<<7)|(1u<<8)|(1u<<11);
    constexpr uint16_t Todi      = (1u<<0)|(1u<<1)|(1u<<3)|(1u<<6)|(1u<<7)|(1u<<8)|(1u<<11);
    constexpr uint16_t Marwa     = (1u<<0)|(1u<<1)|(1u<<4)|(1u<<6)|(1u<<7)|(1u<<9)|(1u<<11);
    constexpr uint16_t Malkauns  = (1u<<0)|(1u<<3)|(1u<<5)|(1u<<8)|(1u<<10);
    constexpr uint16_t Hamsadhwani=(1u<<0)|(1u<<2)|(1u<<4)|(1u<<7)|(1u<<11);
    constexpr uint16_t Charukeshi=(1u<<0)|(1u<<2)|(1u<<4)|(1u<<5)|(1u<<7)|(1u<<8)|(1u<<10);
}

} // namespace boxedarp
