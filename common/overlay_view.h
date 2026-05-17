#ifndef COMMON_OVERLAY_VIEW_H
#define COMMON_OVERLAY_VIEW_H

#include "applecva.h"

#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>

@class AppleCVAOverlayView;

typedef void (^AppleCVAOverlayViewSettingsChangedHandler)(
    AppleCVAOverlayView *view);

@interface AppleCVAOverlayView : NSView

@property(nonatomic, assign) CVPixelBufferRef pixelBuffer;
@property(nonatomic, assign) AppleCVATrackedFace face;
@property(nonatomic, assign) BOOL hasFace;
@property(nonatomic, assign) size_t detectedFaceCount;
@property(nonatomic, assign) size_t trackedFaceCount;
@property(nonatomic, assign) int32_t lastStatus;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *extraStatusLine;
@property(nonatomic, assign) double fps;
@property(nonatomic, assign) BOOL mirrorPreview;
@property(nonatomic, assign) BOOL showCameraPreview;
@property(nonatomic, assign) BOOL flipLandmarkShapeY;
@property(nonatomic, assign) BOOL faceRectUsesTopLeftOrigin;
@property(nonatomic, assign) BOOL useOneEuroFilter;
@property(nonatomic, assign) float oneEuroMinCutoff;
@property(nonatomic, assign) float oneEuroBeta;
@property(nonatomic, assign) float oneEuroDerivativeCutoff;
@property(nonatomic, assign) BOOL useFullBackend;
@property(nonatomic, assign) BOOL showsCalibrationButton;
@property(nonatomic, assign) BOOL calibrationButtonEnabled;
@property(nonatomic, copy) NSString *calibrationButtonTitle;
@property(nonatomic, copy)
    AppleCVAOverlayViewSettingsChangedHandler settingsChangedHandler;

- (void)setCalibrationTarget:(id)target action:(SEL)action;

- (void)updateWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                         face:(const AppleCVATrackedFace *)face
                      hasFace:(BOOL)hasFace
            detectedFaceCount:(size_t)detectedFaceCount
             trackedFaceCount:(size_t)trackedFaceCount
                   lastStatus:(int32_t)lastStatus
                      message:(NSString *)message
                          fps:(double)fps;

- (void)updateWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                         face:(const AppleCVATrackedFace *)face
                      hasFace:(BOOL)hasFace
            detectedFaceCount:(size_t)detectedFaceCount
             trackedFaceCount:(size_t)trackedFaceCount
                   lastStatus:(int32_t)lastStatus
                      message:(NSString *)message
              extraStatusLine:(NSString *)extraStatusLine
                          fps:(double)fps;

@end

#endif
