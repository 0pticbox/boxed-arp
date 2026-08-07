#import "BoxedArpDSP.h"
#include "BoxedArpKernel.hpp"

using namespace boxedarp;

@interface BoxedArpDSP () {
    ArpKernel _kernel;
}
@end

@implementation BoxedArpDSP

- (instancetype)init {
    if ((self = [super init])) {
        _pattern = BAArpPatternUp;
        _division = BAArpDivisionSixteenth;
        _octaves = 1;
        _gate = 0.72f;
        _swing = 0.0f;
        _latch = NO;
        _hostSync = YES;
        _freeBPM = 120.0;
        _scaleLock = NO;
        _rootPitchClass = 0;
        _scaleMask = ScaleMask::Chromatic;
    }
    return self;
}

- (void)reset { _kernel.reset(); }

- (void)pushParameters {
    Parameters p;
    p.pattern = static_cast<Pattern>(_pattern);
    p.division = static_cast<Division>(_division);
    p.octaves = (int)_octaves;
    p.gate = _gate;
    p.swing = _swing;
    p.latch = _latch;
    p.hostSync = _hostSync;
    p.freeBPM = _freeBPM;
    p.scaleLock = _scaleLock;
    p.rootPitchClass = (uint8_t)_rootPitchClass;
    p.scaleMask = _scaleMask;
    _kernel.setParameters(p);
}

struct EmitContext {
    __unsafe_unretained BAMidiEmitBlock block;
};

static void emitThunk(void *ctx, const MidiEvent& e) {
    EmitContext *ec = static_cast<EmitContext *>(ctx);
    BAMidiEvent out { e.sampleOffset, e.status, e.data1, e.data2 };
    ec->block(out);
}

- (void)processBlockStartSampleTime:(int64_t)sampleTime
                         frameCount:(int32_t)frameCount
                         sampleRate:(double)sampleRate
                          hostTempo:(double)hostTempo
                   hostBeatPosition:(double)beatPosition
                        inputEvents:(const BAMidiEvent *)events
                         inputCount:(int32_t)inputCount
                               emit:(BAMidiEmitBlock)emit {
    [self pushParameters];

    // BAMidiEvent and MidiEvent intentionally have the same trivial layout.
    static_assert(sizeof(BAMidiEvent) == sizeof(MidiEvent), "MIDI bridge layout mismatch");
    EmitContext context { emit };
    _kernel.processBlock(sampleTime,
                         frameCount,
                         sampleRate,
                         hostTempo,
                         beatPosition,
                         reinterpret_cast<const MidiEvent *>(events),
                         inputCount,
                         emitThunk,
                         &context);
}

@end
