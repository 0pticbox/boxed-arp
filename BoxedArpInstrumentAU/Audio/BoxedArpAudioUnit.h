#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BoxedArpMIDIEvent : NSObject
@property (nonatomic, readonly) int64_t sampleTime;
@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) double tempo;
@property (nonatomic, readonly) uint8_t status;
@property (nonatomic, readonly) uint8_t data1;
@property (nonatomic, readonly) uint8_t data2;
- (instancetype)initWithSampleTime:(int64_t)sampleTime
                       sampleRate:(double)sampleRate
                            tempo:(double)tempo
                           status:(uint8_t)status
                            data1:(uint8_t)data1
                            data2:(uint8_t)data2;
@end

@interface BoxedArpAudioUnit : AUAudioUnit

@property (nonatomic, readonly) NSInteger currentStepForUI;
@property (nonatomic, readonly) NSInteger currentNoteForUI;
@property (nonatomic, readonly) NSInteger heldNoteCountForUI;
@property (nonatomic, readonly) double currentTempoForUI;
@property (nonatomic, readonly) BOOL midiCaptureActive;
@property (nonatomic, readonly) uint32_t droppedMIDICaptureEventCount;

- (void)startMIDICapture;
- (void)stopMIDICapture;
- (NSArray<BoxedArpMIDIEvent *> *)drainCapturedMIDIEvents;

@end

NS_ASSUME_NONNULL_END
