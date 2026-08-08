#pragma once

#include <AudioToolbox/AudioToolbox.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <vector>

namespace boxedarp {

enum ParameterAddress : AUParameterAddress {
    osc1Wave = 0,
    osc2Wave,
    oscBlend,
    detuneCents,
    attack,
    decay,
    sustain,
    release,
    cutoff,
    resonance,
    arpPattern,
    arpRate,
    octaveRange,
    gate,
    swing,
    latch,
    outputLevel,
    tempoBPM,
    reservedTempoSource, // v13 address 18 retained for parameter-address compatibility.
    chordRoot,
    chordPreset,
    scalePreset,
    arpEnabled,
    delayEnabled,
    delayTime,
    delayFeedback,
    delayTone,
    delayMix,
    midiOutEnabled,
    arpTimingMode,
    freeRateHz
};

enum class Waveform : int { saw = 0, square = 1, sine = 2 };
enum class Pattern : int { up = 0, down = 1, upDown = 2, random = 3 };

class BoxedArpDSP {
public:
    struct CapturedMIDIEvent {
        int64_t sampleTime = 0;
        double sampleRate = 44100.0;
        double tempo = 120.0;
        uint8_t status = 0;
        uint8_t data1 = 0;
        uint8_t data2 = 0;
    };

    using MIDIEmitter = void (*)(void *context,
                                 uint32_t frameOffset,
                                 uint8_t status,
                                 uint8_t data1,
                                 uint8_t data2) noexcept;

    BoxedArpDSP() { setDefaults(); }

    void prepare(double newSampleRate, uint32_t /*maxFrames*/) noexcept {
        sampleRate = std::max(8000.0, newSampleRate);
        delayBuffer.assign(static_cast<size_t>(std::ceil(sampleRate * 2.0)), 0.0f);
        reset();
    }

    void reset() noexcept {
        held.fill(false);
        physicalDown.fill(false);
        velocity.fill(0);
        for (auto &voice : voices) voice = Voice{};
        filterIC1 = filterIC2 = 0.0f;
        std::fill(delayBuffer.begin(), delayBuffer.end(), 0.0f);
        delayWriteIndex = 0;
        delayFilterState = 0.0f;
        arpWasRunning = pArpEnabled.load(std::memory_order_relaxed) >= 0.5f;
        samplesUntilStep = 0.0;
        stepCounter = 0;
        stepParity = 0;
        randomState = 0x0C71C0DEu;
        currentStep.store(-1, std::memory_order_relaxed);
        currentNote.store(-1, std::memory_order_relaxed);
        heldCount.store(0, std::memory_order_relaxed);
        currentTempo.store(120.0, std::memory_order_relaxed);
        captureRead.store(0, std::memory_order_relaxed);
        captureWrite.store(0, std::memory_order_relaxed);
        captureActive.store(false, std::memory_order_relaxed);
        latestRenderSampleTime.store(0, std::memory_order_relaxed);
        updateHeldCount();
    }

    void setParameter(AUParameterAddress address, AUValue value) noexcept {
        switch (address) {
            case osc1Wave:     pOsc1Wave.store(clamp(value, 0.0f, 2.0f)); break;
            case osc2Wave:     pOsc2Wave.store(clamp(value, 0.0f, 2.0f)); break;
            case oscBlend:     pOscBlend.store(clamp(value, 0.0f, 1.0f)); break;
            case detuneCents:  pDetune.store(clamp(value, -24.0f, 24.0f)); break;
            case attack:       pAttack.store(clamp(value, 0.001f, 2.0f)); break;
            case decay:        pDecay.store(clamp(value, 0.005f, 2.0f)); break;
            case sustain:      pSustain.store(clamp(value, 0.0f, 1.0f)); break;
            case release:      pRelease.store(clamp(value, 0.005f, 4.0f)); break;
            case cutoff:       pCutoff.store(clamp(value, 80.0f, 18000.0f)); break;
            case resonance:    pResonance.store(clamp(value, 0.0f, 0.95f)); break;
            case arpPattern:   pPattern.store(clamp(value, 0.0f, 3.0f)); break;
            case arpRate:      pRate.store(clamp(value, 0.0f, 8.0f)); break;
            case octaveRange:  pOctaves.store(clamp(value, 1.0f, 4.0f)); break;
            case gate:         pGate.store(clamp(value, 0.05f, 0.95f)); break;
            case swing:        pSwing.store(clamp(value, 0.0f, 0.45f)); break;
            case latch:        pLatch.store(value >= 0.5f ? 1.0f : 0.0f); break;
            case outputLevel:  pOutput.store(clamp(value, 0.0f, 1.0f)); break;
            case tempoBPM:     pTempoBPM.store(clamp(value, 40.0f, 240.0f)); break;
            case reservedTempoSource:    break; // Reserved address from v13; project tempo was removed.
            case chordRoot:
                pChordRoot.store(clamp(value, 0.0f, 11.0f));
                updateHeldCount();
                break;
            case chordPreset:
                pChordPreset.store(clamp(value, 0.0f, 8.0f));
                updateHeldCount();
                break;
            case scalePreset:  pScalePreset.store(clamp(value, 0.0f, 48.0f)); break;
            case arpEnabled:    pArpEnabled.store(value >= 0.5f ? 1.0f : 0.0f); break;
            case delayEnabled:  pDelayEnabled.store(value >= 0.5f ? 1.0f : 0.0f); break;
            case delayTime:     pDelayTime.store(clamp(value, 0.03f, 1.20f)); break;
            case delayFeedback: pDelayFeedback.store(clamp(value, 0.0f, 0.88f)); break;
            case delayTone:     pDelayTone.store(clamp(value, 0.0f, 1.0f)); break;
            case delayMix:      pDelayMix.store(clamp(value, 0.0f, 0.75f)); break;
            case midiOutEnabled: pMidiOutEnabled.store(value >= 0.5f ? 1.0f : 0.0f); break;
            case arpTimingMode: pArpTimingMode.store(value >= 0.5f ? 1.0f : 0.0f); break;
            case freeRateHz: pFreeRateHz.store(clamp(value, 0.5f, 50.0f)); break;
            default: break;
        }
    }

    AUValue getParameter(AUParameterAddress address) const noexcept {
        switch (address) {
            case osc1Wave: return pOsc1Wave.load();
            case osc2Wave: return pOsc2Wave.load();
            case oscBlend: return pOscBlend.load();
            case detuneCents: return pDetune.load();
            case attack: return pAttack.load();
            case decay: return pDecay.load();
            case sustain: return pSustain.load();
            case release: return pRelease.load();
            case cutoff: return pCutoff.load();
            case resonance: return pResonance.load();
            case arpPattern: return pPattern.load();
            case arpRate: return pRate.load();
            case octaveRange: return pOctaves.load();
            case gate: return pGate.load();
            case swing: return pSwing.load();
            case latch: return pLatch.load();
            case outputLevel: return pOutput.load();
            case tempoBPM: return pTempoBPM.load();
            case reservedTempoSource: return 1.0f; // Reserved address; BOXED ARP always uses its own BPM.
            case chordRoot: return pChordRoot.load();
            case chordPreset: return pChordPreset.load();
            case scalePreset: return pScalePreset.load();
            case arpEnabled: return pArpEnabled.load();
            case delayEnabled: return pDelayEnabled.load();
            case delayTime: return pDelayTime.load();
            case delayFeedback: return pDelayFeedback.load();
            case delayTone: return pDelayTone.load();
            case delayMix: return pDelayMix.load();
            case midiOutEnabled: return pMidiOutEnabled.load();
            case arpTimingMode: return pArpTimingMode.load();
            case freeRateHz: return pFreeRateHz.load();
            default: return 0.0f;
        }
    }

    int uiCurrentStep() const noexcept { return currentStep.load(std::memory_order_relaxed); }
    int uiCurrentNote() const noexcept { return currentNote.load(std::memory_order_relaxed); }
    int uiHeldCount() const noexcept { return heldCount.load(std::memory_order_relaxed); }
    double uiTempo() const noexcept { return currentTempo.load(std::memory_order_relaxed); }

    void startMIDICapture() noexcept {
        captureRead.store(0, std::memory_order_release);
        captureWrite.store(0, std::memory_order_release);
        captureDropped.store(0, std::memory_order_relaxed);
        captureActive.store(true, std::memory_order_release);
    }

    void stopMIDICapture() noexcept {
        captureActive.store(false, std::memory_order_release);
    }

    bool isMIDICaptureActive() const noexcept {
        return captureActive.load(std::memory_order_acquire);
    }

    uint32_t droppedMIDICaptureEventCount() const noexcept {
        return captureDropped.load(std::memory_order_relaxed);
    }

    bool popCapturedMIDIEvent(CapturedMIDIEvent &event) noexcept {
        const uint32_t read = captureRead.load(std::memory_order_relaxed);
        const uint32_t write = captureWrite.load(std::memory_order_acquire);
        if (read == write) return false;
        event = capturedEvents[read];
        captureRead.store((read + 1) % captureCapacity, std::memory_order_release);
        return true;
    }

    void render(AudioBufferList *output,
                uint32_t frameCount,
                const AudioTimeStamp *timestamp,
                const AURenderEvent *events,
                MIDIEmitter emitter = nullptr,
                void *emitterContext = nullptr) noexcept {
        if (!output || output->mNumberBuffers == 0) return;

        // BOXED ARP always uses its own typed/tapped tempo in SYNC mode.
        // FREE mode continues to use pFreeRateHz inside the arp step calculator.
        const double effectiveTempo = std::clamp(
            static_cast<double>(pTempoBPM.load(std::memory_order_relaxed)),
            40.0, 240.0);
        currentTempo.store(effectiveTempo, std::memory_order_relaxed);
        const double blockStart = timestamp ? timestamp->mSampleTime : 0.0;
        latestRenderSampleTime.store(static_cast<int64_t>(blockStart), std::memory_order_relaxed);
        currentEmitter = emitter;
        currentEmitterContext = emitterContext;
        currentBlockStart = static_cast<int64_t>(blockStart);
        currentEventTempo = effectiveTempo;
        const AURenderEvent *event = events;

        for (uint32_t frame = 0; frame < frameCount; ++frame) {
            currentFrameOffset = frame;
            while (event && eventOffset(event, blockStart, frameCount) <= frame) {
                consumeEvent(event);
                event = event->head.next;
            }

            tickArpeggiator(effectiveTempo);

            float mixed = 0.0f;
            for (auto &voice : voices) {
                if (voice.active) mixed += renderVoice(voice);
            }
            mixed *= 0.22f;
            mixed = processFilter(mixed);
            mixed = std::tanh(mixed * 1.25f);
            mixed = processDelay(mixed);
            mixed *= pOutput.load(std::memory_order_relaxed);

            for (UInt32 bufferIndex = 0; bufferIndex < output->mNumberBuffers; ++bufferIndex) {
                auto &buffer = output->mBuffers[bufferIndex];
                if (!buffer.mData) continue;
                auto *samples = static_cast<float *>(buffer.mData);
                const UInt32 channels = std::max<UInt32>(1, buffer.mNumberChannels);
                for (UInt32 channel = 0; channel < channels; ++channel) {
                    samples[frame * channels + channel] = mixed;
                }
            }
        }

        currentEmitter = nullptr;
        currentEmitterContext = nullptr;
    }

private:
    enum class EnvelopeStage { off, attack, decay, sustain, release };

    struct Voice {
        bool active = false;
        int note = -1;
        float centsOffset = 0.0f;
        float velocity = 0.0f;
        double phase1 = 0.0;
        double phase2 = 0.0;
        double frequency1 = 440.0;
        double frequency2 = 440.0;
        float envelope = 0.0f;
        float releaseStep = 0.0f;
        int64_t gateSamplesRemaining = 0;
        bool midiActive = false;
        EnvelopeStage stage = EnvelopeStage::off;
    };

    static float clamp(float value, float low, float high) noexcept {
        return std::min(high, std::max(low, value));
    }

    void setDefaults() noexcept {
        pOsc1Wave = static_cast<float>(Waveform::saw);
        pOsc2Wave = static_cast<float>(Waveform::square);
        pOscBlend = 0.28f;
        pDetune = 7.0f;
        pAttack = 0.008f;
        pDecay = 0.18f;
        pSustain = 0.72f;
        pRelease = 0.20f;
        pCutoff = 7200.0f;
        pResonance = 0.15f;
        pPattern = static_cast<float>(Pattern::upDown);
        pRate = 4.0f;
        pOctaves = 2.0f;
        pGate = 0.62f;
        pSwing = 0.0f;
        pLatch = 0.0f;
        pOutput = 0.78f;
        pTempoBPM = 120.0f;
        pChordRoot = 0.0f;
        pChordPreset = 0.0f;
        pScalePreset = 0.0f;
        pArpEnabled = 1.0f;
        pDelayEnabled = 0.0f;
        pDelayTime = 0.32f;
        pDelayFeedback = 0.38f;
        pDelayTone = 0.42f;
        pDelayMix = 0.24f;
        pMidiOutEnabled = 1.0f;
        pArpTimingMode = 0.0f;
        pFreeRateHz = 8.0f;
    }

    static uint32_t eventOffset(const AURenderEvent *event,
                                double blockStart,
                                uint32_t frameCount) noexcept {
        if (!event) return frameCount;
        const AUEventSampleTime sampleTime = event->head.eventSampleTime;
        if (sampleTime == AUEventSampleTimeImmediate) return 0;
        const double offset = static_cast<double>(sampleTime) - blockStart;
        if (offset <= 0.0) return 0;
        if (offset >= static_cast<double>(frameCount)) return frameCount;
        return static_cast<uint32_t>(offset);
    }

    void consumeEvent(const AURenderEvent *event) noexcept {
        switch (event->head.eventType) {
            case AURenderEventMIDI: {
                const auto &midi = event->MIDI;
                if (midi.length < 1) break;
                const uint8_t status = midi.data[0];
                const uint8_t data1 = midi.length > 1 ? midi.data[1] : 0;
                const uint8_t data2 = midi.length > 2 ? midi.data[2] : 0;
                handleMIDI(status, data1, data2);
                break;
            }
            case AURenderEventParameter:
            case AURenderEventParameterRamp:
                setParameter(event->parameter.parameterAddress, event->parameter.value);
                break;
            default:
                break;
        }
    }

    void handleMIDI(uint8_t statusByte, uint8_t data1, uint8_t data2) noexcept {
        const uint8_t command = statusByte & 0xF0;
        const int note = std::clamp<int>(data1, 0, 127);

        if (command == 0x90 && data2 > 0) {
            const bool noKeysWereDown = std::none_of(physicalDown.begin(), physicalDown.end(), [](bool v) { return v; });
            physicalDown[note] = true;
            if (pLatch.load(std::memory_order_relaxed) >= 0.5f && noKeysWereDown) {
                held.fill(false);
            }
            held[note] = true;
            velocity[note] = data2;
            samplesUntilStep = 0.0;
            updateHeldCount();
        } else if (command == 0x80 || (command == 0x90 && data2 == 0)) {
            physicalDown[note] = false;
            if (pLatch.load(std::memory_order_relaxed) < 0.5f) held[note] = false;
            updateHeldCount();
        } else if (command == 0xB0 && (data1 == 120 || data1 == 123)) {
            held.fill(false);
            physicalDown.fill(false);
            updateHeldCount();
            releaseAllVoices();
        }
    }

    void updateHeldCount() noexcept {
        std::array<bool, 128> sourceMask = held;
        appendChordPreset(sourceMask);
        int count = 0;
        for (bool isHeld : sourceMask) if (isHeld) ++count;
        heldCount.store(count, std::memory_order_relaxed);
        if (count == 0) currentNote.store(-1, std::memory_order_relaxed);
    }


    void appendChordPreset(std::array<bool, 128> &mask) const noexcept {
        const int preset = std::clamp(static_cast<int>(std::lround(pChordPreset.load())), 0, 8);
        if (preset == 0) return;

        int intervals[4] {0, 4, 7, 0};
        int count = 3;
        switch (preset) {
            case 1: intervals[0] = 0; intervals[1] = 4; intervals[2] = 7; count = 3; break;       // Major
            case 2: intervals[0] = 0; intervals[1] = 3; intervals[2] = 7; count = 3; break;       // Minor
            case 3: intervals[0] = 0; intervals[1] = 4; intervals[2] = 7; intervals[3] = 11; count = 4; break; // Maj7
            case 4: intervals[0] = 0; intervals[1] = 3; intervals[2] = 7; intervals[3] = 10; count = 4; break; // Min7
            case 5: intervals[0] = 0; intervals[1] = 4; intervals[2] = 7; intervals[3] = 10; count = 4; break; // Dom7
            case 6: intervals[0] = 0; intervals[1] = 2; intervals[2] = 7; count = 3; break;       // Sus2
            case 7: intervals[0] = 0; intervals[1] = 5; intervals[2] = 7; count = 3; break;       // Sus4
            case 8: intervals[0] = 0; intervals[1] = 7; count = 2; break;                         // Power
            default: return;
        }

        const int base = 60 + std::clamp(static_cast<int>(std::lround(pChordRoot.load())), 0, 11);
        for (int index = 0; index < count; ++index) {
            const int note = std::clamp(base + intervals[index], 0, 127);
            mask[note] = true;
        }
    }

    struct ScaleDefinition {
        std::array<float, 12> cents {};
        int count = 0;
    };

    struct TunedNote {
        int midiNote = 60;
        float centsOffset = 0.0f;
    };

    static constexpr int scaleCount = 49;
    inline static constexpr std::array<ScaleDefinition, scaleCount> scaleDefinitions {{
        ScaleDefinition{{0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 0}, // OFF
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 600.0f, 700.0f, 900.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // LYDIAN
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 500.0f, 700.0f, 900.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // DORIAN
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 500.0f, 700.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // PHRYGIAN
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 500.0f, 700.0f, 800.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // HARM MIN
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 600.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 6}, // WHOLE TONE
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 700.0f, 800.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // HIRAJOSHI
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 700.0f, 900.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // MAJOR PENT
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 500.0f, 700.0f, 900.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // IONIAN
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 500.0f, 700.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // AEOLIAN
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 500.0f, 700.0f, 900.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // MIXOLYDIAN
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 500.0f, 600.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // LOCRIAN
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 500.0f, 700.0f, 900.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // MELODIC MIN
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 600.0f, 700.0f, 900.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // LYDIAN DOM
        ScaleDefinition{{0.0f, 100.0f, 400.0f, 500.0f, 700.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // PHRYG DOM
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 500.0f, 700.0f, 900.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // DORIAN b2
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 500.0f, 700.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // MIXO b6
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 500.0f, 600.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // LOCRIAN #2
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 400.0f, 600.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // ALTERED
        ScaleDefinition{{0.0f, 100.0f, 400.0f, 500.0f, 700.0f, 800.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // DOUBLE HARM
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 600.0f, 700.0f, 800.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // HUNGARIAN MIN
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 500.0f, 700.0f, 800.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // NEAPOLITAN MIN
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 500.0f, 700.0f, 900.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // NEAPOLITAN MAJ
        ScaleDefinition{{0.0f, 100.0f, 400.0f, 600.0f, 800.0f, 1000.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // ENIGMATIC
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 600.0f, 900.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 6}, // PROMETHEUS
        ScaleDefinition{{0.0f, 300.0f, 400.0f, 700.0f, 800.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 6}, // AUGMENTED
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 400.0f, 600.0f, 700.0f, 900.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 8}, // DIM H-W
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 500.0f, 600.0f, 800.0f, 900.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 8}, // DIM W-H
        ScaleDefinition{{0.0f, 100.0f, 200.0f, 300.0f, 400.0f, 500.0f, 600.0f, 700.0f, 800.0f, 900.0f, 1000.0f, 1100.0f, }, 12}, // CHROMATIC
        ScaleDefinition{{0.0f, 300.0f, 500.0f, 700.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // MINOR PENT
        ScaleDefinition{{0.0f, 300.0f, 500.0f, 600.0f, 700.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 6}, // BLUES
        ScaleDefinition{{0.0f, 100.0f, 500.0f, 700.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // IN SEN
        ScaleDefinition{{0.0f, 100.0f, 500.0f, 600.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // IWATO
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 700.0f, 900.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // KUMOI
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 700.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // HAMSADHWANI
        ScaleDefinition{{0.0f, 200.0f, 300.0f, 700.0f, 900.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // SHIVARANJANI
        ScaleDefinition{{0.0f, 300.0f, 500.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 5}, // MALKAUNS
        ScaleDefinition{{0.0f, 100.0f, 400.0f, 500.0f, 700.0f, 800.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // BHAIRAV
        ScaleDefinition{{0.0f, 100.0f, 300.0f, 600.0f, 700.0f, 800.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // TODI
        ScaleDefinition{{0.0f, 100.0f, 400.0f, 600.0f, 700.0f, 900.0f, 1100.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // MARWA
        ScaleDefinition{{0.0f, 200.0f, 400.0f, 500.0f, 700.0f, 800.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // CHARUKESHI
        ScaleDefinition{{0.0f, 100.0f, 400.0f, 500.0f, 700.0f, 900.0f, 1000.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // AHIR BHAIRAV
        ScaleDefinition{{0.0f, 200.0f, 350.0f, 500.0f, 700.0f, 900.0f, 1050.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // µ NEUTRAL DOR
        ScaleDefinition{{0.0f, 150.0f, 350.0f, 500.0f, 700.0f, 850.0f, 1050.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // µ NEUTRAL PHR
        ScaleDefinition{{0.0f, 90.0f, 386.0f, 498.0f, 702.0f, 792.0f, 1088.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // µ SHRUTI BHAIRAV
        ScaleDefinition{{0.0f, 90.0f, 294.0f, 590.0f, 702.0f, 792.0f, 1088.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // µ SHRUTI TODI
        ScaleDefinition{{0.0f, 204.0f, 386.0f, 498.0f, 702.0f, 884.0f, 1088.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // µ JUST MAJOR
        ScaleDefinition{{0.0f, 204.0f, 316.0f, 498.0f, 702.0f, 814.0f, 1018.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // µ JUST MINOR
        ScaleDefinition{{0.0f, 189.474f, 315.789f, 505.263f, 694.737f, 884.211f, 1010.526f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}, 7}, // µ 19EDO DORIAN
    }};

    TunedNote quantizeToScale(int note) const noexcept {
        const int preset = std::clamp(static_cast<int>(std::lround(pScalePreset.load())), 0, scaleCount - 1);
        if (preset == 0) return TunedNote{note, 0.0f};

        const auto &definition = scaleDefinitions[static_cast<size_t>(preset)];
        const int root = std::clamp(static_cast<int>(std::lround(pChordRoot.load())), 0, 11);
        const double inputCents = static_cast<double>(note) * 100.0;
        const double rootCents = static_cast<double>(root) * 100.0;
        const int centerOctave = static_cast<int>(std::floor((inputCents - rootCents) / 1200.0));

        double bestTarget = inputCents;
        double bestDistance = 1.0e12;
        for (int octave = centerOctave - 1; octave <= centerOctave + 1; ++octave) {
            for (int degree = 0; degree < definition.count; ++degree) {
                const double target = rootCents + static_cast<double>(octave) * 1200.0
                    + static_cast<double>(definition.cents[static_cast<size_t>(degree)]);
                const double distance = std::abs(target - inputCents);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestTarget = target;
                }
            }
        }

        int midiNote = static_cast<int>(std::lround(bestTarget / 100.0));
        midiNote = std::clamp(midiNote, 0, 127);
        float centsOffset = static_cast<float>(bestTarget - static_cast<double>(midiNote) * 100.0);
        if ((midiNote == 0 && centsOffset < 0.0f) || (midiNote == 127 && centsOffset > 0.0f)) {
            centsOffset = 0.0f;
        }
        return TunedNote{midiNote, centsOffset};
    }

    void tickArpeggiator(double tempo) noexcept {
        for (auto &voice : voices) {
            if (voice.active && voice.gateSamplesRemaining > 0) {
                --voice.gateSamplesRemaining;
                if (voice.gateSamplesRemaining == 0) {
                    emitVoiceNoteOff(voice);
                    beginRelease(voice);
                }
            }
        }

        const bool enabled = pArpEnabled.load(std::memory_order_relaxed) >= 0.5f;
        if (!enabled) {
            if (arpWasRunning) {
                releaseAllVoices();
                currentStep.store(-1, std::memory_order_relaxed);
                currentNote.store(-1, std::memory_order_relaxed);
                samplesUntilStep = 0.0;
                arpWasRunning = false;
            }
            return;
        }
        if (!arpWasRunning) {
            stepCounter = 0;
            stepParity = 0;
            samplesUntilStep = 0.0;
            arpWasRunning = true;
        }

        samplesUntilStep -= 1.0;
        if (samplesUntilStep > 0.0) return;

        const double stepSamples = samplesPerStep(tempo);
        samplesUntilStep += stepSamples;

        std::array<bool, 128> sourceMask = held;
        appendChordPreset(sourceMask);

        std::array<int, 128> notes{};
        int noteCount = 0;
        for (int note = 0; note < 128; ++note) {
            if (sourceMask[note]) notes[noteCount++] = note;
        }
        if (noteCount == 0) return;

        const int octaves = std::clamp(static_cast<int>(std::lround(pOctaves.load())), 1, 4);
        const int expandedLength = noteCount * octaves;
        int expandedIndex = 0;
        const Pattern pattern = static_cast<Pattern>(std::clamp(static_cast<int>(std::lround(pPattern.load())), 0, 3));

        switch (pattern) {
            case Pattern::up:
                expandedIndex = stepCounter % expandedLength;
                break;
            case Pattern::down:
                expandedIndex = expandedLength - 1 - (stepCounter % expandedLength);
                break;
            case Pattern::upDown: {
                const int cycle = expandedLength <= 1 ? 1 : (expandedLength * 2 - 2);
                const int position = stepCounter % cycle;
                expandedIndex = position < expandedLength ? position : cycle - position;
                break;
            }
            case Pattern::random:
                randomState ^= randomState << 13;
                randomState ^= randomState >> 17;
                randomState ^= randomState << 5;
                expandedIndex = static_cast<int>(randomState % static_cast<uint32_t>(expandedLength));
                break;
        }

        const int baseIndex = expandedIndex % noteCount;
        const int octave = expandedIndex / noteCount;
        const int rawArpNote = std::min(127, notes[baseIndex] + octave * 12);
        const TunedNote arpNote = quantizeToScale(rawArpNote);
        const uint8_t storedVelocity = velocity[notes[baseIndex]];
        const float noteVelocity = storedVelocity > 0
            ? static_cast<float>(storedVelocity) / 127.0f
            : 0.82f;
        const int64_t gateSamples = std::max<int64_t>(1, static_cast<int64_t>(stepSamples * pGate.load()));
        triggerVoice(arpNote, noteVelocity, gateSamples);

        currentStep.store(stepCounter % 16, std::memory_order_relaxed);
        currentNote.store(arpNote.midiNote, std::memory_order_relaxed);
        ++stepCounter;
        stepParity ^= 1;
    }

    double samplesPerStep(double tempo) const noexcept {
        double base = 0.0;
        const bool freeRunning = pArpTimingMode.load(std::memory_order_relaxed) >= 0.5f;
        if (freeRunning) {
            // FREE mode is independent of the host grid. The automatable speed
            // parameter is expressed as generated notes per second.
            const double notesPerSecond = std::clamp(
                static_cast<double>(pFreeRateHz.load(std::memory_order_relaxed)), 0.5, 50.0);
            base = sampleRate / notesPerSecond;
        } else {
            // SYNC mode: beats per step, ordered from slowest to fastest.
            static constexpr std::array<double, 9> beatLengths {
                1.0,        // 1/4
                2.0 / 3.0, // 1/4T
                0.5,        // 1/8
                1.0 / 3.0, // 1/8T
                0.25,       // 1/16
                1.0 / 6.0, // 1/16T
                0.125,      // 1/32
                1.0 / 12.0,// 1/32T
                1.0 / 24.0 // 1/64T
            };
            const int rateIndex = std::clamp(static_cast<int>(std::lround(pRate.load())), 0, 8);
            base = sampleRate * 60.0 / tempo * beatLengths[rateIndex];
        }
        const double swingAmount = static_cast<double>(pSwing.load(std::memory_order_relaxed));
        return std::max(1.0, base * (stepParity == 0 ? (1.0 + swingAmount) : (1.0 - swingAmount)));
    }

    void triggerVoice(const TunedNote &tunedNote, float noteVelocity, int64_t gateSamples) noexcept {
        const int midiNote = tunedNote.midiNote;
        Voice *voice = nullptr;
        for (auto &candidate : voices) {
            if (!candidate.active) { voice = &candidate; break; }
        }
        if (!voice) {
            voice = &*std::min_element(voices.begin(), voices.end(), [](const Voice &a, const Voice &b) {
                return a.envelope < b.envelope;
            });
            emitVoiceNoteOff(*voice);
        }

        const double baseFrequency = 440.0 * std::pow(2.0, (static_cast<double>(midiNote) - 69.0 + static_cast<double>(tunedNote.centsOffset) / 100.0) / 12.0);
        const double cents = static_cast<double>(pDetune.load());
        voice->active = true;
        voice->note = midiNote;
        voice->centsOffset = tunedNote.centsOffset;
        voice->velocity = std::max(0.05f, noteVelocity);
        voice->phase1 = 0.0;
        voice->phase2 = 0.0;
        voice->frequency1 = baseFrequency;
        voice->frequency2 = baseFrequency * std::pow(2.0, cents / 1200.0);
        voice->envelope = 0.0f;
        voice->releaseStep = 0.0f;
        voice->gateSamplesRemaining = gateSamples;
        voice->stage = EnvelopeStage::attack;

        const uint8_t midiVelocity = static_cast<uint8_t>(std::clamp<int>(
            static_cast<int>(std::lround(noteVelocity * 127.0f)), 1, 127));
        const bool hostMIDIActive = pMidiOutEnabled.load(std::memory_order_relaxed) >= 0.5f && currentEmitter;
        if (std::abs(tunedNote.centsOffset) >= 0.01f) {
            emitPitchBendRange(hostMIDIActive);
            emitPitchBend(tunedNote.centsOffset, hostMIDIActive);
        }
        emitGeneratedMIDI(0x90, static_cast<uint8_t>(midiNote), midiVelocity, hostMIDIActive);
        voice->midiActive = hostMIDIActive;
    }

    void emitVoiceNoteOff(Voice &voice) noexcept {
        if (voice.note < 0) return;
        emitGeneratedMIDI(0x80, static_cast<uint8_t>(voice.note), 0, voice.midiActive);
        if (std::abs(voice.centsOffset) >= 0.01f) {
            emitPitchBend(0.0f, voice.midiActive);
        }
        voice.centsOffset = 0.0f;
        voice.midiActive = false;
    }

    void emitGeneratedMIDI(uint8_t status, uint8_t data1, uint8_t data2, bool sendToHost) noexcept {
        captureGeneratedMIDI(status, data1, data2);
        if (sendToHost && currentEmitter) {
            currentEmitter(currentEmitterContext, currentFrameOffset, status, data1, data2);
        }
    }

    void emitPitchBendRange(bool sendToHost) noexcept {
        // Configure MIDI channel 1 for a +/- 2 semitone pitch-bend range. This makes
        // the captured microtonal MIDI portable to instruments that honor standard RPN.
        emitGeneratedMIDI(0xB0, 101, 0, sendToHost);
        emitGeneratedMIDI(0xB0, 100, 0, sendToHost);
        emitGeneratedMIDI(0xB0, 6, 2, sendToHost);
        emitGeneratedMIDI(0xB0, 38, 0, sendToHost);
        emitGeneratedMIDI(0xB0, 101, 127, sendToHost);
        emitGeneratedMIDI(0xB0, 100, 127, sendToHost);
    }

    void emitPitchBend(float cents, bool sendToHost) noexcept {
        const double normalized = std::clamp(static_cast<double>(cents) / 200.0, -1.0, 1.0);
        const int bend = std::clamp(static_cast<int>(std::lround(8192.0 + normalized * 8192.0)), 0, 16383);
        emitGeneratedMIDI(0xE0, static_cast<uint8_t>(bend & 0x7F),
                         static_cast<uint8_t>((bend >> 7) & 0x7F), sendToHost);
    }

    void captureGeneratedMIDI(uint8_t status, uint8_t data1, uint8_t data2) noexcept {
        if (!captureActive.load(std::memory_order_acquire)) return;
        const uint32_t write = captureWrite.load(std::memory_order_relaxed);
        const uint32_t next = (write + 1) % captureCapacity;
        if (next == captureRead.load(std::memory_order_acquire)) {
            captureDropped.fetch_add(1, std::memory_order_relaxed);
            return;
        }
        capturedEvents[write] = CapturedMIDIEvent {
            currentBlockStart + static_cast<int64_t>(currentFrameOffset),
            sampleRate,
            currentEventTempo,
            status, data1, data2
        };
        captureWrite.store(next, std::memory_order_release);
    }

    void beginRelease(Voice &voice) noexcept {
        if (!voice.active || voice.stage == EnvelopeStage::release) return;
        const float releaseSeconds = pRelease.load(std::memory_order_relaxed);
        const float samples = std::max(1.0f, releaseSeconds * static_cast<float>(sampleRate));
        voice.releaseStep = voice.envelope / samples;
        voice.stage = EnvelopeStage::release;
    }

    void releaseAllVoices() noexcept {
        for (auto &voice : voices) {
            emitVoiceNoteOff(voice);
            beginRelease(voice);
        }
    }

    float renderVoice(Voice &voice) noexcept {
        const float env = updateEnvelope(voice);
        if (!voice.active) return 0.0f;

        const double increment1 = voice.frequency1 / sampleRate;
        const double increment2 = voice.frequency2 / sampleRate;
        const Waveform wave1 = static_cast<Waveform>(std::clamp(static_cast<int>(std::lround(pOsc1Wave.load())), 0, 2));
        const Waveform wave2 = static_cast<Waveform>(std::clamp(static_cast<int>(std::lround(pOsc2Wave.load())), 0, 2));
        const float a = oscillator(wave1, voice.phase1, increment1);
        const float b = oscillator(wave2, voice.phase2, increment2);
        const float blend = pOscBlend.load(std::memory_order_relaxed);

        voice.phase1 += increment1;
        voice.phase2 += increment2;
        if (voice.phase1 >= 1.0) voice.phase1 -= 1.0;
        if (voice.phase2 >= 1.0) voice.phase2 -= 1.0;

        return (a * (1.0f - blend) + b * blend) * env * voice.velocity;
    }

    float updateEnvelope(Voice &voice) noexcept {
        switch (voice.stage) {
            case EnvelopeStage::attack: {
                const float seconds = pAttack.load(std::memory_order_relaxed);
                voice.envelope += 1.0f / std::max(1.0f, seconds * static_cast<float>(sampleRate));
                if (voice.envelope >= 1.0f) {
                    voice.envelope = 1.0f;
                    voice.stage = EnvelopeStage::decay;
                }
                break;
            }
            case EnvelopeStage::decay: {
                const float target = pSustain.load(std::memory_order_relaxed);
                const float seconds = pDecay.load(std::memory_order_relaxed);
                voice.envelope -= (1.0f - target) / std::max(1.0f, seconds * static_cast<float>(sampleRate));
                if (voice.envelope <= target) {
                    voice.envelope = target;
                    voice.stage = EnvelopeStage::sustain;
                }
                break;
            }
            case EnvelopeStage::sustain:
                voice.envelope = pSustain.load(std::memory_order_relaxed);
                break;
            case EnvelopeStage::release:
                voice.envelope -= std::max(voice.releaseStep, 0.0000001f);
                if (voice.envelope <= 0.0f) {
                    voice.envelope = 0.0f;
                    voice.active = false;
                    voice.stage = EnvelopeStage::off;
                }
                break;
            case EnvelopeStage::off:
                voice.active = false;
                voice.envelope = 0.0f;
                break;
        }
        return voice.envelope;
    }

    static double polyBLEP(double phase, double dt) noexcept {
        if (phase < dt) {
            const double x = phase / dt;
            return x + x - x * x - 1.0;
        }
        if (phase > 1.0 - dt) {
            const double x = (phase - 1.0) / dt;
            return x * x + x + x + 1.0;
        }
        return 0.0;
    }

    static float oscillator(Waveform wave, double phase, double increment) noexcept {
        switch (wave) {
            case Waveform::saw:
                return static_cast<float>((2.0 * phase - 1.0) - polyBLEP(phase, increment));
            case Waveform::square: {
                double value = phase < 0.5 ? 1.0 : -1.0;
                value += polyBLEP(phase, increment);
                double shifted = std::fmod(phase + 0.5, 1.0);
                value -= polyBLEP(shifted, increment);
                return static_cast<float>(value);
            }
            case Waveform::sine:
                return static_cast<float>(std::sin(phase * 2.0 * M_PI));
        }
        return 0.0f;
    }

    float processFilter(float input) noexcept {
        const float maxCutoff = static_cast<float>(sampleRate * 0.45);
        const float cutoffHz = std::min(pCutoff.load(std::memory_order_relaxed), maxCutoff);
        const float resonanceAmount = pResonance.load(std::memory_order_relaxed);
        const float g = std::tan(static_cast<float>(M_PI) * cutoffHz / static_cast<float>(sampleRate));
        const float damping = 2.0f - 1.9f * resonanceAmount;
        const float h = 1.0f / (1.0f + damping * g + g * g);
        const float high = (input - (damping + g) * filterIC1 - filterIC2) * h;
        const float band = g * high + filterIC1;
        const float low = g * band + filterIC2;
        filterIC1 = g * high + band;
        filterIC2 = g * band + low;
        return low;
    }


    float processDelay(float input) noexcept {
        if (delayBuffer.size() < 4) return input;

        const double requestedSamples = static_cast<double>(pDelayTime.load(std::memory_order_relaxed)) * sampleRate;
        const double delaySamples = std::clamp(requestedSamples, 1.0, static_cast<double>(delayBuffer.size() - 2));
        double readPosition = static_cast<double>(delayWriteIndex) - delaySamples;
        while (readPosition < 0.0) readPosition += static_cast<double>(delayBuffer.size());

        const size_t first = static_cast<size_t>(readPosition) % delayBuffer.size();
        const size_t second = (first + 1) % delayBuffer.size();
        const float fraction = static_cast<float>(readPosition - std::floor(readPosition));
        const float delayed = delayBuffer[first] + (delayBuffer[second] - delayBuffer[first]) * fraction;

        // Darker repeats mimic bandwidth loss in a bucket-brigade delay.
        const float tone = pDelayTone.load(std::memory_order_relaxed);
        const float toneCoefficient = 0.012f + tone * 0.42f;
        delayFilterState += toneCoefficient * (delayed - delayFilterState);

        const float feedback = pDelayFeedback.load(std::memory_order_relaxed);
        const float feedbackSignal = std::tanh(delayFilterState * 1.35f) * feedback;
        delayBuffer[delayWriteIndex] = std::tanh(input + feedbackSignal);
        delayWriteIndex = (delayWriteIndex + 1) % delayBuffer.size();

        const float enabled = pDelayEnabled.load(std::memory_order_relaxed) >= 0.5f ? 1.0f : 0.0f;
        const float mix = pDelayMix.load(std::memory_order_relaxed) * enabled;
        return input * (1.0f - mix) + delayFilterState * mix;
    }

    double sampleRate = 44100.0;
    std::array<bool, 128> held{};
    std::array<bool, 128> physicalDown{};
    std::array<uint8_t, 128> velocity{};
    std::array<Voice, 12> voices{};

    double samplesUntilStep = 0.0;
    int stepCounter = 0;
    int stepParity = 0;
    uint32_t randomState = 0x0C71C0DEu;
    float filterIC1 = 0.0f;
    float filterIC2 = 0.0f;
    std::vector<float> delayBuffer{};
    size_t delayWriteIndex = 0;
    float delayFilterState = 0.0f;
    bool arpWasRunning = true;

    MIDIEmitter currentEmitter = nullptr;
    void *currentEmitterContext = nullptr;
    uint32_t currentFrameOffset = 0;
    int64_t currentBlockStart = 0;
    double currentEventTempo = 120.0;
    std::atomic<int64_t> latestRenderSampleTime {0};

    static constexpr uint32_t captureCapacity = 16384;
    std::array<CapturedMIDIEvent, captureCapacity> capturedEvents{};
    std::atomic<uint32_t> captureRead {0};
    std::atomic<uint32_t> captureWrite {0};
    std::atomic<uint32_t> captureDropped {0};
    std::atomic<bool> captureActive {false};

    std::atomic<int> currentStep {-1};
    std::atomic<int> currentNote {-1};
    std::atomic<int> heldCount {0};
    std::atomic<double> currentTempo {120.0};

    std::atomic<float> pOsc1Wave {0};
    std::atomic<float> pOsc2Wave {1};
    std::atomic<float> pOscBlend {0.28f};
    std::atomic<float> pDetune {7.0f};
    std::atomic<float> pAttack {0.008f};
    std::atomic<float> pDecay {0.18f};
    std::atomic<float> pSustain {0.72f};
    std::atomic<float> pRelease {0.20f};
    std::atomic<float> pCutoff {7200.0f};
    std::atomic<float> pResonance {0.15f};
    std::atomic<float> pPattern {2};
    std::atomic<float> pRate {4};
    std::atomic<float> pOctaves {2};
    std::atomic<float> pGate {0.62f};
    std::atomic<float> pSwing {0};
    std::atomic<float> pLatch {0};
    std::atomic<float> pOutput {0.78f};
    std::atomic<float> pTempoBPM {120.0f};
    std::atomic<float> pChordRoot {0.0f};
    std::atomic<float> pChordPreset {0.0f};
    std::atomic<float> pScalePreset {0.0f};
    std::atomic<float> pArpEnabled {1.0f};
    std::atomic<float> pDelayEnabled {0.0f};
    std::atomic<float> pDelayTime {0.32f};
    std::atomic<float> pDelayFeedback {0.38f};
    std::atomic<float> pDelayTone {0.42f};
    std::atomic<float> pDelayMix {0.24f};
    std::atomic<float> pMidiOutEnabled {1.0f};
    std::atomic<float> pArpTimingMode {0.0f};
    std::atomic<float> pFreeRateHz {8.0f};
};

} // namespace boxedarp
