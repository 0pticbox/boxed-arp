#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BAArpPattern) {
    BAArpPatternUp = 0,
    BAArpPatternDown,
    BAArpPatternUpDown,
    BAArpPatternRandom
};

typedef NS_ENUM(NSInteger, BAArpDivision) {
    BAArpDivisionQuarter = 0,
    BAArpDivisionEighth,
    BAArpDivisionEighthTriplet,
    BAArpDivisionSixteenth,
    BAArpDivisionSixteenthTriplet,
    BAArpDivisionThirtySecond,
    BAArpDivisionThirtySecondTriplet,
    BAArpDivisionSixtyFourth,
    BAArpDivisionSixtyFourthTriplet
};

typedef struct {
    int32_t sampleOffset;
    uint8_t status;
    uint8_t data1;
    uint8_t data2;
} BAMidiEvent;

typedef void (^BAMidiEmitBlock)(BAMidiEvent event);

@interface BoxedArpDSP : NSObject
@property(nonatomic) BAArpPattern pattern;
@property(nonatomic) BAArpDivision division;
@property(nonatomic) NSInteger octaves;
@property(nonatomic) float gate;
@property(nonatomic) float swing;
@property(nonatomic) BOOL latch;
@property(nonatomic) BOOL hostSync;
@property(nonatomic) double freeBPM;
@property(nonatomic) BOOL scaleLock;
@property(nonatomic) NSInteger rootPitchClass;
@property(nonatomic) uint16_t scaleMask;

- (void)reset;
- (void)processBlockStartSampleTime:(int64_t)sampleTime
                         frameCount:(int32_t)frameCount
                         sampleRate:(double)sampleRate
                          hostTempo:(double)hostTempo
                   hostBeatPosition:(double)beatPosition
                        inputEvents:(const BAMidiEvent *_Nullable)events
                         inputCount:(int32_t)inputCount
                               emit:(BAMidiEmitBlock)emit;
@end

NS_ASSUME_NONNULL_END
