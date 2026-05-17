#import "tracking_pipeline.h"

#import "capture.h"
#import "tracking_utils.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#include <math.h>
#include <string.h>

static const uint32_t kAppleCVAPipelineVisionOrientation = 1;

@interface AppleCVATrackingPipeline () <
    AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, readwrite, assign) BOOL running;
@property(nonatomic, readwrite, assign) BOOL useFullBackend;
@property(nonatomic, readwrite, strong) AVCaptureDevice *captureDevice;
@end

@implementation AppleCVATrackingPipeline {
    NSString *_captureQueueLabel;
    AVCaptureSession *_session;
    dispatch_queue_t _captureQueue;
    AppleCVATracker *_tracker;
    AppleCVADetectedFace _detectedFaces[8];
    size_t _detectedFaceCount;
    uint64_t _frameIndex;
    int32_t _lastStatus;
    AppleCVACameraParameters _cameraParameters;
    size_t _cameraWidth;
    size_t _cameraHeight;
    CFTimeInterval _lastFpsTime;
    uint64_t _framesSinceFpsUpdate;
    double _fps;
    BOOL _hasFirstFrameTimestamp;
    double _firstFrameTimestamp;
    AppleCVAFaceOneEuroFilter _faceFilter;
    BOOL _lastOneEuroFilterEnabled;
    AppleCVAOneEuroParameters _oneEuroParameters;
    AppleCVAOneEuroParameters _lastAppliedOneEuroParameters;
}

- (instancetype)initWithFullBackend:(BOOL)useFullBackend
                  captureQueueLabel:(NSString *)captureQueueLabel {
    return [self initWithFullBackend:useFullBackend
                       captureDevice:nil
                   captureQueueLabel:captureQueueLabel];
}

- (instancetype)initWithFullBackend:(BOOL)useFullBackend
                      captureDevice:(AVCaptureDevice *)captureDevice
                  captureQueueLabel:(NSString *)captureQueueLabel {
    self = [super init];
    if (self != nil) {
        _useFullBackend = useFullBackend;
        _captureDevice = captureDevice;
        _useOneEuroFilter = YES;
        _oneEuroParameters = AppleCVAOneEuroParametersDefault();
        _lastAppliedOneEuroParameters = _oneEuroParameters;
        _captureQueueLabel =
            [captureQueueLabel copy] ?: @"local.applecva.tracking-pipeline";
        _lastStatus = APPLECVA_OK;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)start {
    if (self.running) {
        return;
    }

    _lastStatus = [self createTracker];
    if (_lastStatus != APPLECVA_OK) {
        [self deliverStatusMessage:@"AppleCVA tracker creation failed."
                            status:_lastStatus];
        return;
    }

    [AVCaptureDevice
        requestAccessForMediaType:AVMediaTypeVideo
                completionHandler:^(BOOL granted) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                    if (!granted) {
                        [self deliverStatusMessage:@"Camera access was denied."
                                            status:APPLECVA_OK];
                        return;
                    }
                    [self startCaptureSession];
                  });
                }];
}

- (void)stop {
    [_session stopRunning];
    _session = nil;
    _captureQueue = nil;
    self.running = NO;

    if (_tracker != NULL) {
        AppleCVATrackerDestroy(_tracker);
        _tracker = NULL;
    }
}

- (int32_t)createTracker {
    if (_tracker != NULL) {
        AppleCVATrackerDestroy(_tracker);
        _tracker = NULL;
    }

    AppleCVAConfig config;
    AppleCVAConfigInit(&config);
    config.use_full_api = self.useFullBackend;
    return AppleCVATrackerCreate(&config, &_tracker);
}

- (void)startCaptureSession {
    NSError *error = nil;
    AVCaptureDevice *device = self.captureDevice;
    if (device == nil) {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    if (device == nil) {
        [self deliverStatusMessage:@"No video capture device found."
                            status:APPLECVA_OK];
        return;
    }

    AVCaptureDeviceInput *input =
        [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (input == nil) {
        [self deliverStatusMessage:error.localizedDescription
                            status:APPLECVA_OK];
        return;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = self.useFullBackend
                                ? AVCaptureSessionPreset640x480
                                : AVCaptureSessionPreset1280x720;
    if (![session canAddInput:input]) {
        [self deliverStatusMessage:@"Could not add camera input."
                            status:APPLECVA_OK];
        return;
    }
    [session addInput:input];

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey :
            @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
    };

    _captureQueue = dispatch_queue_create(_captureQueueLabel.UTF8String,
                                          DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:_captureQueue];
    if (![session canAddOutput:output]) {
        [self deliverStatusMessage:@"Could not add camera output."
                            status:APPLECVA_OK];
        return;
    }
    [session addOutput:output];

    _session = session;
    self.running = YES;
    NSString *cameraName =
        device.localizedName.length != 0 ? device.localizedName : @"camera";
    [self deliverStatusMessage:[NSString stringWithFormat:@"Using %@. "
                                                          @"Waiting for "
                                                          @"face.",
                                                          cameraName]
                        status:APPLECVA_OK];
    [_session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    (void)output;
    (void)connection;
    if (_tracker == NULL) {
        return;
    }

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == NULL) {
        return;
    }

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    if (width != _cameraWidth || height != _cameraHeight) {
        _cameraWidth = width;
        _cameraHeight = height;
        _detectedFaceCount = 0;
    }
    AppleCVACaptureUpdateCameraParametersFromSampleBuffer(
        sampleBuffer, width, height, &_cameraParameters);

    size_t detectedFaceCount = 0;
    const int32_t detectStatus = AppleCVADetectFacesWithVisionOrientation(
        pixelBuffer, kAppleCVAPipelineVisionOrientation, _detectedFaces,
        sizeof(_detectedFaces) / sizeof(_detectedFaces[0]), &detectedFaceCount);
    if (detectStatus == APPLECVA_OK) {
        _detectedFaceCount = detectedFaceCount;
    }

    AppleCVATrackedFace trackedFaces[4];
    AppleCVAFrameResult result;
    AppleCVAFrameResultInit(&result, trackedFaces,
                            sizeof(trackedFaces) / sizeof(trackedFaces[0]));

    const double timestamp =
        [self trackerTimestampForSampleBuffer:sampleBuffer];
    _lastStatus = AppleCVATrackerProcessFrame(
        _tracker, pixelBuffer, &_cameraParameters, _detectedFaces,
        _detectedFaceCount, timestamp, 150, &result);

    AppleCVATrackedFace bestFace;
    const BOOL hasFace = _lastStatus == APPLECVA_OK &&
                         AppleCVASelectBestTrackedFace(&result, &bestFace);

    AppleCVATrackedFace displayFace;
    memset(&displayFace, 0, sizeof(displayFace));
    BOOL hasDisplayFace = hasFace;
    if (hasDisplayFace) {
        displayFace = bestFace;
    }

    const BOOL oneEuroFilterEnabled = self.useOneEuroFilter;
    const AppleCVAOneEuroParameters currentParameters = self.oneEuroParameters;
    const BOOL parametersChanged =
        memcmp(&_lastAppliedOneEuroParameters, &currentParameters,
               sizeof(AppleCVAOneEuroParameters)) != 0;
    if (parametersChanged) {
        _lastAppliedOneEuroParameters = currentParameters;
        AppleCVAFaceOneEuroFilterReset(&_faceFilter);
    }
    if (!oneEuroFilterEnabled) {
        if (_lastOneEuroFilterEnabled) {
            AppleCVAFaceOneEuroFilterReset(&_faceFilter);
        }
    } else if (!_lastOneEuroFilterEnabled || !hasDisplayFace) {
        AppleCVAFaceOneEuroFilterReset(&_faceFilter);
    }
    _lastOneEuroFilterEnabled = oneEuroFilterEnabled;
    if (oneEuroFilterEnabled && hasDisplayFace) {
        AppleCVAFaceOneEuroFilterApplyWithParameters(
            &_faceFilter, &displayFace, timestamp, &currentParameters);
    }

    ++_frameIndex;
    [self updateFps];

    AppleCVATrackingPipelineFrameHandler handler = self.frameHandler;
    if (handler != nil) {
        handler(pixelBuffer, hasDisplayFace ? &displayFace : NULL,
                hasDisplayFace, result.detected_face_count,
                result.tracked_face_count, _lastStatus, timestamp, _fps);
    }
}

- (double)trackerTimestampForSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMTime presentationTime =
        CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    double timestamp = CMTimeGetSeconds(presentationTime);
    if (!isfinite(timestamp)) {
        timestamp = CACurrentMediaTime();
    }
    if (!_hasFirstFrameTimestamp) {
        _hasFirstFrameTimestamp = YES;
        _firstFrameTimestamp = timestamp;
    }
    timestamp -= _firstFrameTimestamp;
    if (!isfinite(timestamp) || timestamp < 0.0) {
        timestamp = (double)_frameIndex / 30.0;
    }
    return timestamp;
}

- (void)updateFps {
    const CFTimeInterval now = CACurrentMediaTime();
    if (_lastFpsTime == 0.0) {
        _lastFpsTime = now;
        _framesSinceFpsUpdate = 0;
        return;
    }
    ++_framesSinceFpsUpdate;
    const CFTimeInterval elapsed = now - _lastFpsTime;
    if (elapsed >= 0.5) {
        _fps = (double)_framesSinceFpsUpdate / elapsed;
        _framesSinceFpsUpdate = 0;
        _lastFpsTime = now;
    }
}

- (void)deliverStatusMessage:(NSString *)message status:(int32_t)status {
    AppleCVATrackingPipelineStatusHandler handler = self.statusHandler;
    if (handler == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      handler(message ?: @"", status);
    });
}

@end
