#import "BoxedArpAudioUnit.h"
#import "../DSP/BoxedArpDSP.hpp"
#include <vector>

using namespace boxedarp;

@implementation BoxedArpMIDIEvent

- (instancetype)initWithSampleTime:(int64_t)sampleTime
                       sampleRate:(double)sampleRate
                            tempo:(double)tempo
                           status:(uint8_t)status
                            data1:(uint8_t)data1
                            data2:(uint8_t)data2 {
    self = [super init];
    if (self) {
        _sampleTime = sampleTime;
        _sampleRate = sampleRate;
        _tempo = tempo;
        _status = status;
        _data1 = data1;
        _data2 = data2;
    }
    return self;
}

@end

struct BoxedArpMIDIOutputContext {
    __unsafe_unretained AUMIDIOutputEventBlock block;
    AUEventSampleTime blockStart;
};

static void BoxedArpEmitMIDI(void *rawContext,
                             uint32_t frameOffset,
                             uint8_t status,
                             uint8_t data1,
                             uint8_t data2) noexcept {
    auto *context = static_cast<BoxedArpMIDIOutputContext *>(rawContext);
    if (!context || !context->block) return;
    const uint8_t bytes[3] { status, data1, data2 };
    const AUEventSampleTime eventTime =
        context->blockStart == AUEventSampleTimeImmediate
            ? AUEventSampleTimeImmediate
            : context->blockStart + static_cast<AUEventSampleTime>(frameOffset);
    context->block(eventTime, 0, 3, bytes);
}

@interface BoxedArpAudioUnit () {
    BoxedArpDSP _dsp;
    AUAudioUnitBus *_outputBus;
    AUAudioUnitBusArray *_outputBusArray;
    AUAudioUnitBusArray *_inputBusArray;
    std::vector<float> _fallbackOutputStorage;
    UInt32 _outputChannelCount;
    BOOL _outputIsInterleaved;
}
@end

@implementation BoxedArpAudioUnit

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                      options:(AudioComponentInstantiationOptions)options
                                        error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (!self) return nil;

    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
    if (!format) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:kAudio_ParamError
                                        userInfo:@{NSLocalizedDescriptionKey: @"Could not create the output format."}];
        }
        return nil;
    }

    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:outError];
    if (!_outputBus) return nil;
    _outputBus.shouldAllocateBuffer = YES;

    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                            busType:AUAudioUnitBusTypeOutput
                                                             busses:@[_outputBus]];
    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                           busType:AUAudioUnitBusTypeInput
                                                            busses:@[]];

    [self buildParameterTree];
    self.maximumFramesToRender = 4096;
    return self;
}

- (void)buildParameterTree {
    NSMutableArray<AUParameter *> *parameters = [NSMutableArray array];

    AUParameter *(^makeParameter)(NSString *, NSString *, AUParameterAddress, AUValue, AUValue,
                                  AudioUnitParameterUnit, NSArray<NSString *> * _Nullable) =
    ^AUParameter *(NSString *identifier, NSString *name, AUParameterAddress address,
                   AUValue min, AUValue max, AudioUnitParameterUnit unit,
                   NSArray<NSString *> * _Nullable strings) {
        return [AUParameterTree createParameterWithIdentifier:identifier
                                                         name:name
                                                      address:address
                                                          min:min
                                                          max:max
                                                         unit:unit
                                                     unitName:nil
                                                        flags:kAudioUnitParameterFlag_IsWritable | kAudioUnitParameterFlag_IsReadable
                                                 valueStrings:strings
                                          dependentParameters:nil];
    };

    [parameters addObject:makeParameter(@"osc1Wave", @"OSC 1 Wave", osc1Wave, 0, 2,
                                        kAudioUnitParameterUnit_Indexed, @[@"Saw", @"Square", @"Sine"])];
    [parameters addObject:makeParameter(@"osc2Wave", @"OSC 2 Wave", osc2Wave, 0, 2,
                                        kAudioUnitParameterUnit_Indexed, @[@"Saw", @"Square", @"Sine"])];
    [parameters addObject:makeParameter(@"oscBlend", @"Oscillator Blend", oscBlend, 0, 1,
                                        kAudioUnitParameterUnit_Generic, nil)];
    [parameters addObject:makeParameter(@"detune", @"OSC 2 Detune", detuneCents, -24, 24,
                                        kAudioUnitParameterUnit_Cents, nil)];
    [parameters addObject:makeParameter(@"attack", @"Attack", attack, 0.001, 2,
                                        kAudioUnitParameterUnit_Seconds, nil)];
    [parameters addObject:makeParameter(@"decay", @"Decay", decay, 0.005, 2,
                                        kAudioUnitParameterUnit_Seconds, nil)];
    [parameters addObject:makeParameter(@"sustain", @"Sustain", sustain, 0, 1,
                                        kAudioUnitParameterUnit_LinearGain, nil)];
    [parameters addObject:makeParameter(@"release", @"Release", release, 0.005, 4,
                                        kAudioUnitParameterUnit_Seconds, nil)];
    [parameters addObject:makeParameter(@"cutoff", @"Filter Cutoff", cutoff, 80, 18000,
                                        kAudioUnitParameterUnit_Hertz, nil)];
    [parameters addObject:makeParameter(@"resonance", @"Filter Resonance", resonance, 0, 0.95,
                                        kAudioUnitParameterUnit_Generic, nil)];
    [parameters addObject:makeParameter(@"pattern", @"Arp Pattern", arpPattern, 0, 3,
                                        kAudioUnitParameterUnit_Indexed, @[@"Up", @"Down", @"Up/Down", @"Random"])];
    [parameters addObject:makeParameter(@"rate", @"Arp Rate", arpRate, 0, 8,
                                        kAudioUnitParameterUnit_Indexed,
                                        @[@"1/4", @"1/4T", @"1/8", @"1/8T", @"1/16", @"1/16T", @"1/32", @"1/32T", @"1/64T"])];
    [parameters addObject:makeParameter(@"octaves", @"Octave Range", octaveRange, 1, 4,
                                        kAudioUnitParameterUnit_Indexed, @[@"1", @"2", @"3", @"4"])];
    [parameters addObject:makeParameter(@"gate", @"Gate", gate, 0.05, 0.95,
                                        kAudioUnitParameterUnit_Generic, nil)];
    [parameters addObject:makeParameter(@"swing", @"Swing", swing, 0, 0.45,
                                        kAudioUnitParameterUnit_Generic, nil)];
    [parameters addObject:makeParameter(@"latch", @"Latch", latch, 0, 1,
                                        kAudioUnitParameterUnit_Boolean, @[@"Off", @"On"])];
    [parameters addObject:makeParameter(@"output", @"Output", outputLevel, 0, 1,
                                        kAudioUnitParameterUnit_LinearGain, nil)];
    [parameters addObject:makeParameter(@"tempoBPM", @"Tempo", tempoBPM, 40, 240,
                                        kAudioUnitParameterUnit_BPM, nil)];
    // Address 18 remains reserved in the DSP so later parameter addresses stay compatible.
    [parameters addObject:makeParameter(@"chordRoot", @"Chord and Scale Root", chordRoot, 0, 11,
                                        kAudioUnitParameterUnit_Indexed, @[@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"])];
    [parameters addObject:makeParameter(@"chordPreset", @"Built-in Chord", chordPreset, 0, 8,
                                        kAudioUnitParameterUnit_Indexed, @[@"Off", @"Major", @"Minor", @"Maj7", @"Min7", @"Dom7", @"Sus2", @"Sus4", @"Power"])];
    [parameters addObject:makeParameter(@"scalePreset", @"Scale Quantizer", scalePreset, 0, 48,
                                        kAudioUnitParameterUnit_Indexed, @[@"OFF", @"LYDIAN", @"DORIAN", @"PHRYGIAN", @"HARM MIN", @"WHOLE TONE", @"HIRAJOSHI", @"MAJOR PENT", @"IONIAN", @"AEOLIAN", @"MIXOLYDIAN", @"LOCRIAN", @"MELODIC MIN", @"LYDIAN DOM", @"PHRYG DOM", @"DORIAN b2", @"MIXO b6", @"LOCRIAN #2", @"ALTERED", @"DOUBLE HARM", @"HUNGARIAN MIN", @"NEAPOLITAN MIN", @"NEAPOLITAN MAJ", @"ENIGMATIC", @"PROMETHEUS", @"AUGMENTED", @"DIM H-W", @"DIM W-H", @"CHROMATIC", @"MINOR PENT", @"BLUES", @"IN SEN", @"IWATO", @"KUMOI", @"HAMSADHWANI", @"SHIVARANJANI", @"MALKAUNS", @"BHAIRAV", @"TODI", @"MARWA", @"CHARUKESHI", @"AHIR BHAIRAV", @"Micro NEUTRAL DOR", @"Micro NEUTRAL PHR", @"Micro SHRUTI BHAIRAV", @"Micro SHRUTI TODI", @"Micro JUST MAJOR", @"Micro JUST MINOR", @"Micro 19EDO DORIAN"])];
    [parameters addObject:makeParameter(@"arpEnabled", @"Arpeggiator Transport", arpEnabled, 0, 1,
                                        kAudioUnitParameterUnit_Boolean, @[@"Stop", @"Play"])];
    [parameters addObject:makeParameter(@"delayEnabled", @"Analog Delay", delayEnabled, 0, 1,
                                        kAudioUnitParameterUnit_Boolean, @[@"Off", @"On"])];
    [parameters addObject:makeParameter(@"delayTime", @"Delay Time", delayTime, 0.03, 1.20,
                                        kAudioUnitParameterUnit_Seconds, nil)];
    [parameters addObject:makeParameter(@"delayFeedback", @"Delay Feedback", delayFeedback, 0, 0.88,
                                        kAudioUnitParameterUnit_Generic, nil)];
    [parameters addObject:makeParameter(@"delayTone", @"Delay Tone", delayTone, 0, 1,
                                        kAudioUnitParameterUnit_Generic, nil)];
    [parameters addObject:makeParameter(@"delayMix", @"Delay Mix", delayMix, 0, 0.75,
                                        kAudioUnitParameterUnit_Generic, nil)];
    [parameters addObject:makeParameter(@"midiOutEnabled", @"Generated MIDI Output", midiOutEnabled, 0, 1,
                                        kAudioUnitParameterUnit_Boolean, @[@"Off", @"On"])];
    [parameters addObject:makeParameter(@"arpTimingMode", @"Arp Timing Mode", arpTimingMode, 0, 1,
                                        kAudioUnitParameterUnit_Indexed, @[@"Sync", @"Free"])];
    [parameters addObject:makeParameter(@"freeRateHz", @"Free Arp Speed", freeRateHz, 0.5, 50.0,
                                        kAudioUnitParameterUnit_Hertz, nil)];

    AUParameterTree *tree = [AUParameterTree createTreeWithChildren:parameters];
    __weak BoxedArpAudioUnit *weakSelf = self;

    tree.implementorValueObserver = ^(AUParameter *parameter, AUValue value) {
        BoxedArpAudioUnit *strongSelf = weakSelf;
        if (strongSelf) strongSelf->_dsp.setParameter(parameter.address, value);
    };

    tree.implementorValueProvider = ^AUValue(AUParameter *parameter) {
        BoxedArpAudioUnit *strongSelf = weakSelf;
        return strongSelf ? strongSelf->_dsp.getParameter(parameter.address) : 0.0f;
    };

    self.parameterTree = tree;

    for (AUParameter *parameter in parameters) {
        parameter.value = _dsp.getParameter(parameter.address);
    }
}

- (AUAudioUnitBusArray *)inputBusses { return _inputBusArray; }
- (AUAudioUnitBusArray *)outputBusses { return _outputBusArray; }
- (BOOL)isMusicDeviceOrEffect { return YES; }
- (BOOL)canProcessInPlace { return NO; }
- (NSInteger)virtualMIDICableCount { return 1; }
- (NSArray<NSString *> *)MIDIOutputNames { return @[@"BOXED ARP Notes"]; }

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) return NO;

    AVAudioFormat *format = _outputBus.format;
    if (!format.isStandard || format.channelCount == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:kAudioUnitErr_FormatNotSupported
                                        userInfo:@{NSLocalizedDescriptionKey: @"BOXED ARP requires a standard floating-point output format."}];
        }
        [super deallocateRenderResources];
        return NO;
    }

    _outputChannelCount = format.channelCount;
    _outputIsInterleaved = format.isInterleaved;
    const size_t sampleCapacity = static_cast<size_t>(self.maximumFramesToRender) * std::max<UInt32>(1, _outputChannelCount);
    _fallbackOutputStorage.assign(sampleCapacity, 0.0f);

    _dsp.prepare(format.sampleRate, self.maximumFramesToRender);
    return YES;
}

- (void)deallocateRenderResources {
    _dsp.reset();
    _fallbackOutputStorage.clear();
    [super deallocateRenderResources];
}

- (AUInternalRenderBlock)internalRenderBlock {
    __weak BoxedArpAudioUnit *weakSelf = self;
    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags,
                             const AudioTimeStamp *timestamp,
                             AVAudioFrameCount frameCount,
                             NSInteger outputBusNumber,
                             AudioBufferList *outputData,
                             const AURenderEvent *realtimeEventListHead,
                             AURenderPullInputBlock pullInputBlock) {
        (void)actionFlags;
        (void)outputBusNumber;
        (void)pullInputBlock;

        BoxedArpAudioUnit *strongSelf = weakSelf;
        if (!strongSelf) return kAudioUnitErr_Uninitialized;

        // Some hosts provide null mData pointers and expect the Audio Unit to supply storage.
        // The vector is allocated before rendering so this path performs no realtime allocation.
        if (outputData && !strongSelf->_fallbackOutputStorage.empty()) {
            const UInt32 channelCount = std::max<UInt32>(1, strongSelf->_outputChannelCount);
            for (UInt32 index = 0; index < outputData->mNumberBuffers; ++index) {
                AudioBuffer &buffer = outputData->mBuffers[index];
                if (buffer.mData == nullptr) {
                    if (strongSelf->_outputIsInterleaved) {
                        buffer.mData = strongSelf->_fallbackOutputStorage.data();
                        buffer.mNumberChannels = channelCount;
                        buffer.mDataByteSize = frameCount * channelCount * sizeof(float);
                    } else {
                        const size_t offset = static_cast<size_t>(index) * strongSelf.maximumFramesToRender;
                        buffer.mData = strongSelf->_fallbackOutputStorage.data() + offset;
                        buffer.mNumberChannels = 1;
                        buffer.mDataByteSize = frameCount * sizeof(float);
                    }
                } else {
                    const UInt32 channelsInBuffer = std::max<UInt32>(1, buffer.mNumberChannels);
                    buffer.mDataByteSize = frameCount * channelsInBuffer * sizeof(float);
                }
            }
        }

        AUMIDIOutputEventBlock midiOutput = strongSelf.MIDIOutputEventBlock;
        BoxedArpMIDIOutputContext midiContext {
            midiOutput,
            timestamp ? static_cast<AUEventSampleTime>(timestamp->mSampleTime) : AUEventSampleTimeImmediate
        };

        strongSelf->_dsp.render(outputData, frameCount, timestamp, realtimeEventListHead,
                                midiOutput ? BoxedArpEmitMIDI : nullptr,
                                midiOutput ? &midiContext : nullptr);
        return noErr;
    };
}

- (NSInteger)currentStepForUI { return _dsp.uiCurrentStep(); }
- (NSInteger)currentNoteForUI { return _dsp.uiCurrentNote(); }
- (NSInteger)heldNoteCountForUI { return _dsp.uiHeldCount(); }
- (double)currentTempoForUI { return _dsp.uiTempo(); }
- (BOOL)midiCaptureActive { return _dsp.isMIDICaptureActive(); }
- (uint32_t)droppedMIDICaptureEventCount { return _dsp.droppedMIDICaptureEventCount(); }

- (void)startMIDICapture { _dsp.startMIDICapture(); }
- (void)stopMIDICapture { _dsp.stopMIDICapture(); }

- (NSArray<BoxedArpMIDIEvent *> *)drainCapturedMIDIEvents {
    NSMutableArray<BoxedArpMIDIEvent *> *events = [NSMutableArray array];
    BoxedArpDSP::CapturedMIDIEvent event;
    while (_dsp.popCapturedMIDIEvent(event)) {
        [events addObject:[[BoxedArpMIDIEvent alloc] initWithSampleTime:event.sampleTime
                                                            sampleRate:event.sampleRate
                                                                 tempo:event.tempo
                                                                status:event.status
                                                                 data1:event.data1
                                                                 data2:event.data2]];
    }
    return events;
}

@end
