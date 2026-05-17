#ifndef COMMON_TRACKING_PIPELINE_H
#define COMMON_TRACKING_PIPELINE_H

#include "applecva.h"
#include "tracking_utils.h"

#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

@class AVCaptureDevice;

typedef void (^AppleCVATrackingPipelineStatusHandler)(NSString *message,
                                                      int32_t status);

typedef void (^AppleCVATrackingPipelineFrameHandler)(
    CVPixelBufferRef pixelBuffer, const AppleCVATrackedFace *face, BOOL hasFace,
    size_t detectedFaceCount, size_t trackedFaceCount, int32_t status,
    double timestamp, double fps);

@interface AppleCVATrackingPipeline : NSObject

@property(nonatomic, readonly, assign) BOOL running;
@property(nonatomic, readonly, assign) BOOL useFullBackend;
@property(nonatomic, readonly, strong) AVCaptureDevice *captureDevice;
@property(nonatomic, assign) BOOL useOneEuroFilter;
@property(nonatomic, assign) AppleCVAOneEuroParameters oneEuroParameters;
@property(nonatomic, copy) AppleCVATrackingPipelineStatusHandler statusHandler;
@property(nonatomic, copy) AppleCVATrackingPipelineFrameHandler frameHandler;

- (instancetype)initWithFullBackend:(BOOL)useFullBackend
                  captureQueueLabel:(NSString *)captureQueueLabel;
- (instancetype)initWithFullBackend:(BOOL)useFullBackend
                      captureDevice:(AVCaptureDevice *)captureDevice
                  captureQueueLabel:(NSString *)captureQueueLabel;
- (void)start;
- (void)stop;

@end

#endif // COMMON_TRACKING_PIPELINE_H
