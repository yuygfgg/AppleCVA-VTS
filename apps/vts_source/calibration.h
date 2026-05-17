#ifndef VTS_SOURCE_CALIBRATION_H
#define VTS_SOURCE_CALIBRATION_H

#import "parameters.h"

#import <Foundation/Foundation.h>

@interface VTSCalibrationController : NSObject

@property(nonatomic, readonly, assign) BOOL calibrated;
@property(nonatomic, readonly, assign) BOOL inProgress;
@property(nonatomic, readonly, assign) size_t sampleCount;
@property(nonatomic, readonly, assign) size_t sampleTarget;
@property(nonatomic, readonly, assign) VTSAppleCVACalibration calibration;

- (void)startCalibration;
- (BOOL)collectSampleFromFace:(const AppleCVATrackedFace *)face
                      hasFace:(BOOL)hasFace;
- (NSString *)statusLine;

@end

#endif // VTS_SOURCE_CALIBRATION_H
