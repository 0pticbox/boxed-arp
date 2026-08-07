#include "BoxedArpKernel.hpp"
#include <algorithm>
#include <cmath>

namespace boxedarp {

ArpKernel::ArpKernel() { reset(); }

void ArpKernel::reset() {
    for (auto& h : held_) h = {};
    latched_.fill(0);
    latchedVelocity_.fill(0);
    hadAnyPhysicalDown_ = false;
    sequenceIndex_ = -1;
    upDownDirection_ = 1;
    activeOutput_ = false;
    activeOutputNote_ = 0;
    pendingOffSampleTime_ = -1;
    lastStepOrdinal_ = INT64_MIN;
    rng_ = 0x9E3779B9u;
}

int ArpKernel::clampInt(int v, int lo, int hi) { return std::max(lo, std::min(hi, v)); }
float ArpKernel::clampFloat(float v, float lo, float hi) { return std::max(lo, std::min(hi, v)); }

void ArpKernel::setParameters(const Parameters& p) {
    params_ = p;
    params_.octaves = clampInt(params_.octaves, 1, 4);
    params_.gate = clampFloat(params_.gate, 0.05f, 0.98f);
    params_.swing = clampFloat(params_.swing, 0.0f, 0.45f);
    params_.freeBPM = std::max(20.0, std::min(400.0, params_.freeBPM));
    params_.rootPitchClass %= 12;
    params_.scaleMask &= 0x0FFF;
    if (params_.scaleMask == 0) params_.scaleMask = ScaleMask::Chromatic;
}

double ArpKernel::beatsPerStep(Division d) {
    switch (d) {
        case Division::Quarter: return 1.0;
        case Division::Eighth: return 0.5;
        case Division::EighthTriplet: return 1.0 / 3.0;
        case Division::Sixteenth: return 0.25;
        case Division::SixteenthTriplet: return 1.0 / 6.0;
        case Division::ThirtySecond: return 0.125;
        case Division::ThirtySecondTriplet: return 1.0 / 12.0;
        case Division::SixtyFourth: return 0.0625;
        case Division::SixtyFourthTriplet: return 1.0 / 24.0;
    }
    return 0.25;
}

bool ArpKernel::anyPhysicalDown() const {
    for (const auto& h : held_) if (h.down) return true;
    return false;
}

void ArpKernel::noteOn(uint8_t note, uint8_t velocity) {
    held_[note].note = note;
    held_[note].velocity = velocity ? velocity : 100;
    held_[note].down = true;

    if (params_.latch) {
        // Starting a new chord after all keys were released replaces the old latch.
        if (!hadAnyPhysicalDown_) {
            latched_.fill(0);
            latchedVelocity_.fill(0);
            sequenceIndex_ = -1;
            upDownDirection_ = 1;
        }
        latched_[note] = 1;
        latchedVelocity_[note] = held_[note].velocity;
    }
    hadAnyPhysicalDown_ = true;
}

void ArpKernel::noteOff(uint8_t note) {
    held_[note].down = false;
    if (!params_.latch) {
        held_[note].velocity = 0;
    }
    hadAnyPhysicalDown_ = anyPhysicalDown();
}

void ArpKernel::handleInput(const MidiEvent& e, MidiEmitFn emit, void* ctx) {
    const uint8_t command = e.status & 0xF0;
    if (command == 0x90 && e.data2 > 0) {
        noteOn(e.data1 & 0x7F, e.data2 & 0x7F);
        return; // consume note-on
    }
    if (command == 0x80 || (command == 0x90 && e.data2 == 0)) {
        noteOff(e.data1 & 0x7F);
        return; // consume note-off
    }

    // Pass through non-note MIDI (CC, pitch bend, aftertouch, etc.).
    if (emit) emit(ctx, e);
}

uint8_t ArpKernel::quantizeToScale(uint8_t midiNote) const {
    if (!params_.scaleLock) return midiNote;
    const int root = params_.rootPitchClass;
    int best = midiNote;
    int bestDistance = 128;
    for (int candidate = 0; candidate <= 127; ++candidate) {
        int rel = (candidate - root) % 12;
        if (rel < 0) rel += 12;
        if ((params_.scaleMask & (1u << rel)) == 0) continue;
        int distance = std::abs(candidate - static_cast<int>(midiNote));
        if (distance < bestDistance || (distance == bestDistance && candidate < best)) {
            best = candidate;
            bestDistance = distance;
        }
    }
    return static_cast<uint8_t>(best);
}

int ArpKernel::collectSequence(std::array<uint8_t, 128>& notes,
                               std::array<uint8_t, 128>& velocities) const {
    int count = 0;
    auto addBase = [&](int base, uint8_t velocity) {
        for (int octave = 0; octave < params_.octaves; ++octave) {
            int candidate = base + octave * 12;
            if (candidate > 127 || count >= 128) break;
            uint8_t q = quantizeToScale(static_cast<uint8_t>(candidate));
            // avoid adjacent duplicates created by quantization
            if (count > 0 && notes[count - 1] == q) continue;
            notes[count] = q;
            velocities[count] = velocity;
            ++count;
        }
    };

    if (params_.latch) {
        for (int n = 0; n < 128; ++n) {
            if (latched_[n]) addBase(n, latchedVelocity_[n] ? latchedVelocity_[n] : 100);
        }
    } else {
        for (int n = 0; n < 128; ++n) {
            if (held_[n].down) addBase(n, held_[n].velocity ? held_[n].velocity : 100);
        }
    }
    return count;
}

uint32_t ArpKernel::nextRandom() {
    uint32_t x = rng_;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_ = x;
    return x;
}

int ArpKernel::chooseSequenceIndex(int count) {
    if (count <= 0) return -1;
    switch (params_.pattern) {
        case Pattern::Up:
            sequenceIndex_ = (sequenceIndex_ + 1 + count) % count;
            return sequenceIndex_;
        case Pattern::Down:
            if (sequenceIndex_ < 0 || sequenceIndex_ >= count) sequenceIndex_ = count;
            sequenceIndex_ = (sequenceIndex_ - 1 + count) % count;
            return sequenceIndex_;
        case Pattern::Random:
            sequenceIndex_ = static_cast<int>(nextRandom() % static_cast<uint32_t>(count));
            return sequenceIndex_;
        case Pattern::UpDown:
            if (count == 1) { sequenceIndex_ = 0; return 0; }
            if (sequenceIndex_ < 0 || sequenceIndex_ >= count) {
                sequenceIndex_ = 0;
                upDownDirection_ = 1;
                return sequenceIndex_;
            }
            sequenceIndex_ += upDownDirection_;
            if (sequenceIndex_ >= count - 1) {
                sequenceIndex_ = count - 1;
                upDownDirection_ = -1;
            } else if (sequenceIndex_ <= 0) {
                sequenceIndex_ = 0;
                upDownDirection_ = 1;
            }
            return sequenceIndex_;
    }
    return 0;
}

void ArpKernel::emitNoteOffAt(int32_t sampleOffset, MidiEmitFn emit, void* ctx) {
    if (!activeOutput_) return;
    MidiEvent e;
    e.sampleOffset = std::max<int32_t>(0, sampleOffset);
    e.status = 0x80;
    e.data1 = activeOutputNote_;
    e.data2 = 0;
    if (emit) emit(ctx, e);
    activeOutput_ = false;
    pendingOffSampleTime_ = -1;
}

void ArpKernel::triggerStepAt(int32_t sampleOffset,
                              int64_t absoluteSample,
                              int64_t stepOrdinal,
                              double stepSamples,
                              MidiEmitFn emit,
                              void* ctx) {
    if (stepOrdinal == lastStepOrdinal_) return;
    lastStepOrdinal_ = stepOrdinal;

    if (activeOutput_) emitNoteOffAt(sampleOffset, emit, ctx);

    std::array<uint8_t, 128> notes{};
    std::array<uint8_t, 128> velocities{};
    const int count = collectSequence(notes, velocities);
    if (count <= 0) {
        sequenceIndex_ = -1;
        return;
    }

    const int idx = chooseSequenceIndex(count);
    if (idx < 0) return;

    MidiEvent on;
    on.sampleOffset = std::max<int32_t>(0, sampleOffset);
    on.status = 0x90;
    on.data1 = notes[idx];
    on.data2 = velocities[idx] ? velocities[idx] : 100;
    if (emit) emit(ctx, on);

    activeOutput_ = true;
    activeOutputNote_ = on.data1;
    const auto gateSamples = static_cast<int64_t>(std::max(1.0, std::floor(stepSamples * params_.gate)));
    pendingOffSampleTime_ = absoluteSample + gateSamples;
}

void ArpKernel::processBlock(int64_t blockStartSampleTime,
                             int32_t frameCount,
                             double sampleRate,
                             double hostTempo,
                             double hostBeatPosition,
                             const MidiEvent* input,
                             int32_t inputCount,
                             MidiEmitFn emit,
                             void* emitContext) {
    if (frameCount <= 0 || sampleRate <= 0.0) return;
    const double tempo = params_.hostSync ? hostTempo : params_.freeBPM;
    if (tempo <= 1.0) return;

    const double samplesPerBeat = sampleRate * 60.0 / tempo;
    const double stepBeats = beatsPerStep(params_.division);
    const double stepSamples = samplesPerBeat * stepBeats;
    const double blockStartBeat = params_.hostSync
        ? hostBeatPosition
        : static_cast<double>(blockStartSampleTime) / samplesPerBeat;
    const double blockEndBeat = blockStartBeat + static_cast<double>(frameCount) / samplesPerBeat;

    int32_t inputIndex = 0;

    // Handle a gate-off carried from the previous block if it lands before the first new step.
    auto emitPendingOffIfDueBefore = [&](int32_t boundaryOffset) {
        if (activeOutput_ && pendingOffSampleTime_ >= blockStartSampleTime) {
            const int64_t offOffset64 = pendingOffSampleTime_ - blockStartSampleTime;
            if (offOffset64 >= 0 && offOffset64 < frameCount && offOffset64 <= boundaryOffset) {
                emitNoteOffAt(static_cast<int32_t>(offOffset64), emit, emitContext);
            }
        }
    };

    // Find the first unswung step ordinal that can touch this block.
    int64_t firstOrdinal = static_cast<int64_t>(std::floor(blockStartBeat / stepBeats)) - 1;
    int64_t lastOrdinal = static_cast<int64_t>(std::ceil(blockEndBeat / stepBeats)) + 1;

    for (int64_t ordinal = firstOrdinal; ordinal <= lastOrdinal; ++ordinal) {
        double beat = static_cast<double>(ordinal) * stepBeats;
        if ((ordinal & 1LL) != 0) beat += stepBeats * params_.swing;
        const double offsetD = (beat - blockStartBeat) * samplesPerBeat;
        const int32_t stepOffset = static_cast<int32_t>(std::llround(offsetD));
        if (stepOffset < 0 || stepOffset >= frameCount) continue;

        // Apply incoming events in sample order up to this step.
        while (input && inputIndex < inputCount && input[inputIndex].sampleOffset <= stepOffset) {
            const int32_t eventOffset = std::max<int32_t>(0, std::min<int32_t>(frameCount - 1, input[inputIndex].sampleOffset));
            emitPendingOffIfDueBefore(eventOffset);
            handleInput(input[inputIndex], emit, emitContext);
            ++inputIndex;
        }

        emitPendingOffIfDueBefore(stepOffset);
        const int64_t absSample = blockStartSampleTime + stepOffset;
        triggerStepAt(stepOffset, absSample, ordinal, stepSamples, emit, emitContext);
    }

    // Apply any remaining input events.
    while (input && inputIndex < inputCount) {
        const int32_t eventOffset = std::max<int32_t>(0, std::min<int32_t>(frameCount - 1, input[inputIndex].sampleOffset));
        emitPendingOffIfDueBefore(eventOffset);
        handleInput(input[inputIndex], emit, emitContext);
        ++inputIndex;
    }

    // Gate-off that lands later in this block.
    if (activeOutput_ && pendingOffSampleTime_ >= blockStartSampleTime) {
        const int64_t offOffset = pendingOffSampleTime_ - blockStartSampleTime;
        if (offOffset >= 0 && offOffset < frameCount) {
            emitNoteOffAt(static_cast<int32_t>(offOffset), emit, emitContext);
        }
    }

    // If latch is off and there are no held notes, guarantee the generated note stops.
    if (!params_.latch && !anyPhysicalDown() && activeOutput_) {
        emitNoteOffAt(frameCount - 1, emit, emitContext);
    }
}

} // namespace boxedarp
