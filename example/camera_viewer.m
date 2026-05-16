#import "applecva.h"

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint16_t a;
    uint16_t b;
} LandmarkEdge;

static bool gMirrorPreview = true;
static bool gShowCameraPreview = true;
static bool gFlipLandmarkShapeY = false;
static bool gFaceRectUsesTopLeftOrigin = true;
static const uint32_t kVisionOrientation = 1;
static const size_t kVisionDetectionInterval = 1;
static const uint64_t kHeldFaceMaxFrames = 12;
static const float kStableFaceMinConfidence = 0.5f;
static const size_t kDisplayedBlendshapeCount = 8;
static const float kBlendshapeDisplayThreshold = 0.01f;

static const LandmarkEdge kLandmarkEdges[] = {
    {0, 2},   {2, 3},   {3, 1},   {1, 5},   {5, 4},   {4, 0},   {0, 6},
    {1, 6},   {7, 9},   {9, 10},  {10, 8},  {8, 12},  {12, 11}, {11, 7},
    {7, 13},  {8, 13},  {14, 15}, {15, 16}, {17, 18}, {18, 19}, {20, 21},
    {21, 22}, {22, 23}, {23, 24}, {24, 25}, {25, 26}, {26, 27}, {27, 28},
    {28, 29}, {29, 30}, {30, 31}, {31, 32}, {32, 33}, {33, 20}, {34, 36},
    {36, 38}, {38, 35}, {35, 39}, {39, 37}, {37, 34}, {40, 41}, {41, 42},
    {42, 43}, {44, 45}, {45, 46}, {46, 47}, {47, 48}, {49, 51}, {50, 52},
    {53, 54}, {54, 55}, {55, 56}, {56, 57}, {57, 58}, {58, 59}, {59, 65},
    {65, 64}, {64, 63}, {63, 62}, {62, 61}, {61, 60},
};

static NSRect aspect_fit_rect(NSSize source_size, NSRect bounds) {
    if (source_size.width <= 0.0 || source_size.height <= 0.0 ||
        bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return bounds;
    }
    const CGFloat source_aspect = source_size.width / source_size.height;
    const CGFloat bounds_aspect = bounds.size.width / bounds.size.height;
    NSRect rect = bounds;
    if (bounds_aspect > source_aspect) {
        rect.size.width = bounds.size.height * source_aspect;
        rect.origin.x += (bounds.size.width - rect.size.width) * 0.5;
    } else {
        rect.size.height = bounds.size.width / source_aspect;
        rect.origin.y += (bounds.size.height - rect.size.height) * 0.5;
    }
    return rect;
}

static NSPoint point_for_image_point(float x, float y, size_t image_width,
                                     size_t image_height, NSRect image_rect,
                                     bool source_uses_top_left_origin,
                                     bool mirror_x) {
    if (source_uses_top_left_origin) {
        y = (float)image_height - y;
    }
    if (mirror_x) {
        x = (float)image_width - x;
    }
    const CGFloat scale_x = image_rect.size.width / (CGFloat)image_width;
    const CGFloat scale_y = image_rect.size.height / (CGFloat)image_height;
    return NSMakePoint(image_rect.origin.x + ((CGFloat)x * scale_x),
                       image_rect.origin.y + ((CGFloat)y * scale_y));
}

static NSRect rect_for_normalized_face_rect(const float rect[4],
                                            NSRect image_rect,
                                            bool source_uses_top_left_origin,
                                            bool mirror_x) {
    CGFloat source_x = (CGFloat)rect[0];
    CGFloat source_y = (CGFloat)rect[1];
    const CGFloat width = (CGFloat)rect[2] * image_rect.size.width;
    const CGFloat height = (CGFloat)rect[3] * image_rect.size.height;
    if (source_uses_top_left_origin) {
        source_y = 1.0 - source_y - (CGFloat)rect[3];
    }
    CGFloat x = image_rect.origin.x + (source_x * image_rect.size.width);
    const CGFloat y = image_rect.origin.y + (source_y * image_rect.size.height);
    if (mirror_x) {
        x = image_rect.origin.x + image_rect.size.width -
            ((source_x + (CGFloat)rect[2]) * image_rect.size.width);
    }
    return NSMakeRect(x, y, width, height);
}

static bool
tracked_face_has_drawable_landmarks(const AppleCVATrackedFace *face) {
    return face != NULL && face->valid && face->landmark_pair_count >= 6;
}

static bool tracked_face_is_stable(const AppleCVATrackedFace *face) {
    return tracked_face_has_drawable_landmarks(face) &&
           face->failure_type == 0 &&
           face->confidence >= kStableFaceMinConfidence;
}

static NSString *status_string_for_code(int32_t status) {
    return [NSString
        stringWithFormat:@"%s (%d)", AppleCVAStatusString(status), status];
}

@interface FaceOverlayView : NSView
@property(nonatomic, assign) CVPixelBufferRef pixelBuffer;
@property(nonatomic, assign) AppleCVATrackedFace face;
@property(nonatomic, assign) BOOL hasFace;
@property(nonatomic, assign) size_t detectedFaceCount;
@property(nonatomic, assign) size_t trackedFaceCount;
@property(nonatomic, assign) int32_t lastStatus;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, assign) double fps;
@property(nonatomic, assign) uint64_t badFrameCount;
- (void)updateWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                         face:(const AppleCVATrackedFace *)face
                      hasFace:(BOOL)hasFace
            detectedFaceCount:(size_t)detectedFaceCount
             trackedFaceCount:(size_t)trackedFaceCount
                   lastStatus:(int32_t)lastStatus
                      message:(NSString *)message
                          fps:(double)fps
                badFrameCount:(uint64_t)badFrameCount;
@end

@implementation FaceOverlayView {
    CIContext *_ciContext;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _ciContext = [CIContext contextWithOptions:nil];
        _message = @"Starting camera...";
        _lastStatus = APPLECVA_OK;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
    }
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.window makeFirstResponder:self];
}

- (void)keyDown:(NSEvent *)event {
    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    if ([characters isEqualToString:@"x"]) {
        gMirrorPreview = !gMirrorPreview;
        self.needsDisplay = YES;
        return;
    }
    if ([characters isEqualToString:@"p"]) {
        gShowCameraPreview = !gShowCameraPreview;
        self.needsDisplay = YES;
        return;
    }
    if ([characters isEqualToString:@"y"]) {
        gFlipLandmarkShapeY = !gFlipLandmarkShapeY;
        self.needsDisplay = YES;
        return;
    }
    if ([characters isEqualToString:@"b"]) {
        gFaceRectUsesTopLeftOrigin = !gFaceRectUsesTopLeftOrigin;
        self.needsDisplay = YES;
        return;
    }
    [super keyDown:event];
}

- (void)dealloc {
    if (_pixelBuffer != NULL) {
        CVPixelBufferRelease(_pixelBuffer);
    }
}

- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (_pixelBuffer == pixelBuffer) {
        return;
    }
    if (pixelBuffer != NULL) {
        CVPixelBufferRetain(pixelBuffer);
    }
    if (_pixelBuffer != NULL) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    _pixelBuffer = pixelBuffer;
}

- (void)updateWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                         face:(const AppleCVATrackedFace *)face
                      hasFace:(BOOL)hasFace
            detectedFaceCount:(size_t)detectedFaceCount
             trackedFaceCount:(size_t)trackedFaceCount
                   lastStatus:(int32_t)lastStatus
                      message:(NSString *)message
                          fps:(double)fps
                badFrameCount:(uint64_t)badFrameCount {
    self.pixelBuffer = pixelBuffer;
    memset(&_face, 0, sizeof(_face));
    if (face != NULL) {
        _face = *face;
    }
    _hasFace = hasFace;
    _detectedFaceCount = detectedFaceCount;
    _trackedFaceCount = trackedFaceCount;
    _lastStatus = lastStatus;
    self.message = message ?: @"";
    _fps = fps;
    _badFrameCount = badFrameCount;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor blackColor] setFill];
    NSRectFill(self.bounds);

    CVPixelBufferRef pixelBuffer = self.pixelBuffer;
    size_t imageWidth = 0;
    size_t imageHeight = 0;
    NSRect imageRect = self.bounds;
    if (pixelBuffer != NULL) {
        imageWidth = CVPixelBufferGetWidth(pixelBuffer);
        imageHeight = CVPixelBufferGetHeight(pixelBuffer);
        imageRect = aspect_fit_rect(
            NSMakeSize((CGFloat)imageWidth, (CGFloat)imageHeight), self.bounds);

        if (gShowCameraPreview) {
            CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
            CGRect fromRect =
                CGRectMake(0.0, 0.0, (CGFloat)imageWidth, (CGFloat)imageHeight);
            if (gMirrorPreview) {
                image = [image
                    imageByApplyingTransform:CGAffineTransformMake(
                                                 -1.0, 0.0, 0.0, 1.0,
                                                 (CGFloat)imageWidth, 0.0)];
                fromRect = image.extent;
            }
            CGImageRef cgImage = [_ciContext createCGImage:image
                                                  fromRect:fromRect];
            if (cgImage != NULL) {
                NSImage *nsImage = [[NSImage alloc]
                    initWithCGImage:cgImage
                               size:NSMakeSize((CGFloat)imageWidth,
                                               (CGFloat)imageHeight)];
                [nsImage drawInRect:imageRect
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationCopy
                           fraction:1.0];
                CGImageRelease(cgImage);
            }
        }
    }

    if (pixelBuffer != NULL && self.hasFace && imageWidth != 0 &&
        imageHeight != 0) {
        [self drawFaceOverlayInImageRect:imageRect
                              imageWidth:imageWidth
                             imageHeight:imageHeight];
    }

    [self drawStatusText];
}

- (void)drawFaceOverlayInImageRect:(NSRect)imageRect
                        imageWidth:(size_t)imageWidth
                       imageHeight:(size_t)imageHeight {
    const AppleCVATrackedFace *face = &_face;

    NSRect landmarkBounds = NSZeroRect;
    const BOOL hasLandmarkBounds =
        [self landmarkBoundsForFace:face
                        inImageRect:imageRect
                         imageWidth:imageWidth
                        imageHeight:imageHeight
            sourceUsesTopLeftOrigin:gFaceRectUsesTopLeftOrigin
                            outRect:&landmarkBounds];
    NSRect faceBounds = NSZeroRect;
    if ((face->rect[2] > 0.0f && face->rect[3] > 0.0f &&
         (faceBounds = rect_for_normalized_face_rect(face->rect, imageRect,
                                                     gFaceRectUsesTopLeftOrigin,
                                                     gMirrorPreview),
          true)) ||
        (hasLandmarkBounds && (faceBounds = landmarkBounds, true))) {
        NSBezierPath *rectPath = [NSBezierPath bezierPathWithRect:faceBounds];
        rectPath.lineWidth = 1.5;
        [[NSColor colorWithCalibratedRed:1.0 green:0.72 blue:0.18
                                   alpha:0.9] setStroke];
        [rectPath stroke];
    }

    [self drawLandmarks:face
              inImageRect:imageRect
               imageWidth:imageWidth
              imageHeight:imageHeight
           landmarkBounds:landmarkBounds
        hasLandmarkBounds:hasLandmarkBounds];
}

- (BOOL)landmarkBoundsForFace:(const AppleCVATrackedFace *)face
                  inImageRect:(NSRect)imageRect
                   imageWidth:(size_t)imageWidth
                  imageHeight:(size_t)imageHeight
      sourceUsesTopLeftOrigin:(bool)sourceUsesTopLeftOrigin
                      outRect:(NSRect *)outRect {
    if (!tracked_face_has_drawable_landmarks(face) || outRect == NULL) {
        return NO;
    }

    CGFloat minX = CGFLOAT_MAX;
    CGFloat minY = CGFLOAT_MAX;
    CGFloat maxX = -CGFLOAT_MAX;
    CGFloat maxY = -CGFLOAT_MAX;
    size_t validCount = 0;
    for (size_t i = 0; i < face->landmark_pair_count; ++i) {
        const size_t base = i * 2;
        const float x = face->landmarks[base];
        const float y = face->landmarks[base + 1];
        if (!isfinite(x) || !isfinite(y)) {
            continue;
        }
        NSPoint point =
            point_for_image_point(x, y, imageWidth, imageHeight, imageRect,
                                  sourceUsesTopLeftOrigin, gMirrorPreview);
        minX = fmin(minX, point.x);
        minY = fmin(minY, point.y);
        maxX = fmax(maxX, point.x);
        maxY = fmax(maxY, point.y);
        ++validCount;
    }

    if (validCount < 6 || maxX <= minX || maxY <= minY) {
        return NO;
    }

    const CGFloat padX = fmax(18.0, (maxX - minX) * 0.16);
    const CGFloat padY = fmax(18.0, (maxY - minY) * 0.22);
    minX = fmax(NSMinX(imageRect), minX - padX);
    minY = fmax(NSMinY(imageRect), minY - padY);
    maxX = fmin(NSMaxX(imageRect), maxX + padX);
    maxY = fmin(NSMaxY(imageRect), maxY + padY);
    *outRect = NSMakeRect(minX, minY, maxX - minX, maxY - minY);
    return YES;
}

- (void)drawLandmarks:(const AppleCVATrackedFace *)face
          inImageRect:(NSRect)imageRect
           imageWidth:(size_t)imageWidth
          imageHeight:(size_t)imageHeight
       landmarkBounds:(NSRect)landmarkBounds
    hasLandmarkBounds:(BOOL)hasLandmarkBounds {
    NSBezierPath *linePath = [NSBezierPath bezierPath];
    linePath.lineWidth = 1.5;
    for (size_t i = 0; i < sizeof(kLandmarkEdges) / sizeof(kLandmarkEdges[0]);
         ++i) {
        const LandmarkEdge edge = kLandmarkEdges[i];
        if (edge.a >= face->landmark_pair_count ||
            edge.b >= face->landmark_pair_count) {
            continue;
        }
        const size_t aBase = (size_t)edge.a * 2;
        const size_t bBase = (size_t)edge.b * 2;
        NSPoint a = [self landmarkPointWithX:face->landmarks[aBase]
                                           y:face->landmarks[aBase + 1]
                                 inImageRect:imageRect
                                  imageWidth:imageWidth
                                 imageHeight:imageHeight
                              landmarkBounds:landmarkBounds
                           hasLandmarkBounds:hasLandmarkBounds];
        NSPoint b = [self landmarkPointWithX:face->landmarks[bBase]
                                           y:face->landmarks[bBase + 1]
                                 inImageRect:imageRect
                                  imageWidth:imageWidth
                                 imageHeight:imageHeight
                              landmarkBounds:landmarkBounds
                           hasLandmarkBounds:hasLandmarkBounds];
        [linePath moveToPoint:a];
        [linePath lineToPoint:b];
    }
    [[NSColor colorWithCalibratedRed:0.1 green:1.0 blue:0.55
                               alpha:0.9] setStroke];
    [linePath stroke];

    [[NSColor colorWithCalibratedRed:0.55 green:0.9 blue:1.0
                               alpha:0.95] setFill];
    for (size_t i = 0; i < face->landmark_pair_count; ++i) {
        const size_t base = i * 2;
        NSPoint point = [self landmarkPointWithX:face->landmarks[base]
                                               y:face->landmarks[base + 1]
                                     inImageRect:imageRect
                                      imageWidth:imageWidth
                                     imageHeight:imageHeight
                                  landmarkBounds:landmarkBounds
                               hasLandmarkBounds:hasLandmarkBounds];
        NSRect dot = NSMakeRect(point.x - 2.4, point.y - 2.4, 4.8, 4.8);
        [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    }
}

- (NSPoint)landmarkPointWithX:(float)x
                            y:(float)y
                  inImageRect:(NSRect)imageRect
                   imageWidth:(size_t)imageWidth
                  imageHeight:(size_t)imageHeight
               landmarkBounds:(NSRect)landmarkBounds
            hasLandmarkBounds:(BOOL)hasLandmarkBounds {
    NSPoint point =
        point_for_image_point(x, y, imageWidth, imageHeight, imageRect,
                              gFaceRectUsesTopLeftOrigin, gMirrorPreview);
    if (gFlipLandmarkShapeY && hasLandmarkBounds) {
        point.y = NSMinY(landmarkBounds) + NSMaxY(landmarkBounds) - point.y;
    }
    return point;
}

- (void)appendBlendshapeSummaryToText:(NSMutableString *)text
                                 face:(const AppleCVATrackedFace *)face {
    if (text == nil || face == NULL || face->blendshape_count == 0) {
        return;
    }

    const size_t count = (face->blendshape_count < APPLECVA_MAX_BLENDSHAPES)
                             ? face->blendshape_count
                             : APPLECVA_MAX_BLENDSHAPES;
    bool selected[APPLECVA_MAX_BLENDSHAPES] = {false};
    size_t written = 0;
    [text appendFormat:@"\nblendshapes %zu", face->blendshape_count];
    for (size_t rank = 0; rank < kDisplayedBlendshapeCount; ++rank) {
        size_t bestIndex = count;
        float bestValue = kBlendshapeDisplayThreshold;
        for (size_t i = 0; i < count; ++i) {
            const float value = face->blendshapes[i];
            if (!selected[i] && isfinite(value) && value > bestValue) {
                bestIndex = i;
                bestValue = value;
            }
        }
        if (bestIndex == count) {
            break;
        }

        selected[bestIndex] = true;
        if (written == 0) {
            [text appendString:@":\n"];
        } else if ((written % 4) == 0) {
            [text appendString:@"\n"];
        } else {
            [text appendString:@"  "];
        }
        [text appendFormat:@"%s=%.2f", AppleCVABlendshapeNames[bestIndex],
                           bestValue];
        ++written;
    }

    if (written == 0) {
        [text appendString:@": neutral"];
    }
    if (isfinite(face->tongue_out) &&
        face->tongue_out > kBlendshapeDisplayThreshold) {
        [text
            appendFormat:@"\n%s=%.2f", AppleCVATongueOutName, face->tongue_out];
    }
}

- (void)drawStatusText {
    NSMutableString *text = [NSMutableString string];
    if (self.message.length != 0) {
        [text appendString:self.message];
    }
    if (self.pixelBuffer != NULL) {
        [text appendFormat:@"\nFPS %.1f  detected %zu  tracked %zu", self.fps,
                           self.detectedFaceCount, self.trackedFaceCount];
        if (!gShowCameraPreview) {
            [text appendString:@"  preview off"];
        }
        if (self.badFrameCount != 0) {
            [text appendFormat:@"  bad %llu",
                               (unsigned long long)self.badFrameCount];
        }
        if (self.hasFace) {
            [text appendFormat:@"  confidence %.3f  failure %d",
                               self.face.confidence, self.face.failure_type];
            [text
                appendFormat:@"\nlandmarks %zu", self.face.landmark_pair_count];
            [self appendBlendshapeSummaryToText:text face:&_face];
        }
    }
    if (self.lastStatus != APPLECVA_OK) {
        [text appendFormat:@"\nstatus %@",
                           status_string_for_code(self.lastStatus)];
    }

    NSDictionary *attributes = @{
        NSFontAttributeName :
            [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : NSColor.whiteColor,
    };
    NSSize textSize = [text sizeWithAttributes:attributes];
    NSRect box =
        NSMakeRect(14.0, self.bounds.size.height - textSize.height - 22.0,
                   textSize.width + 18.0, textSize.height + 12.0);
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.58] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:box xRadius:6.0 yRadius:6.0] fill];
    [text drawAtPoint:NSMakePoint(box.origin.x + 9.0, box.origin.y + 6.0)
        withAttributes:attributes];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate,
                                   AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation AppDelegate {
    NSWindow *_window;
    FaceOverlayView *_view;
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
    BOOL _hasLastGoodFace;
    AppleCVATrackedFace _lastGoodFace;
    uint64_t _lastGoodFaceFrameIndex;
    uint64_t _consecutiveBadFrames;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    _view = [[FaceOverlayView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, 960.0, 720.0)];
    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(100.0, 100.0, 960.0, 720.0)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.title = @"AppleCVA Camera Viewer";
    _window.contentView = _view;
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    _lastStatus = [self createTracker];
    if (_lastStatus != APPLECVA_OK) {
        [_view updateWithPixelBuffer:NULL
                                face:NULL
                             hasFace:NO
                   detectedFaceCount:0
                    trackedFaceCount:0
                          lastStatus:_lastStatus
                             message:@"AppleCVA tracker creation failed."
                                 fps:0.0
                       badFrameCount:0];
        return;
    }

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                             completionHandler:^(BOOL granted) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                 if (!granted) {
                                     [self showCameraDenied];
                                     return;
                                 }
                                 [self startCaptureSession];
                               });
                             }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)sender {
    (void)sender;
    return YES;
}

- (int32_t)createTracker {
    if (_tracker != NULL) {
        AppleCVATrackerDestroy(_tracker);
        _tracker = NULL;
    }

    AppleCVAConfig config;
    AppleCVAConfigInit(&config);
    config.enable_rgb_fallback_conversion = true;
    return AppleCVATrackerCreate(&config, &_tracker);
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_session stopRunning];
    if (_tracker != NULL) {
        AppleCVATrackerDestroy(_tracker);
        _tracker = NULL;
    }
}

- (void)showCameraDenied {
    [_view updateWithPixelBuffer:NULL
                            face:NULL
                         hasFace:NO
               detectedFaceCount:0
                trackedFaceCount:0
                      lastStatus:APPLECVA_OK
                         message:@"Camera access was denied."
                             fps:0.0
                   badFrameCount:0];
}

- (void)startCaptureSession {
    NSError *error = nil;
    AVCaptureDevice *device =
        [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (device == nil) {
        [_view updateWithPixelBuffer:NULL
                                face:NULL
                             hasFace:NO
                   detectedFaceCount:0
                    trackedFaceCount:0
                          lastStatus:APPLECVA_OK
                             message:@"No video capture device found."
                                 fps:0.0
                       badFrameCount:0];
        return;
    }

    AVCaptureDeviceInput *input =
        [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (input == nil) {
        [_view updateWithPixelBuffer:NULL
                                face:NULL
                             hasFace:NO
                   detectedFaceCount:0
                    trackedFaceCount:0
                          lastStatus:APPLECVA_OK
                             message:error.localizedDescription
                                 fps:0.0
                       badFrameCount:0];
        return;
    }

    _session = [[AVCaptureSession alloc] init];
    _session.sessionPreset = AVCaptureSessionPreset1280x720;
    if ([_session canAddInput:input]) {
        [_session addInput:input];
    }

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey :
            @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
    };
    _captureQueue = dispatch_queue_create("local.applecva.camera-viewer",
                                          DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:_captureQueue];
    if ([_session canAddOutput:output]) {
        [_session addOutput:output];
    }

    [_view updateWithPixelBuffer:NULL
                            face:NULL
                         hasFace:NO
               detectedFaceCount:0
                trackedFaceCount:0
                      lastStatus:APPLECVA_OK
                         message:@"Waiting for face..."
                             fps:0.0
                   badFrameCount:0];

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
        AppleCVAMakeDefaultCameraParameters(width, height, 1.0f,
                                            &_cameraParameters);
        _detectedFaceCount = 0;
    }

    if ((_frameIndex % kVisionDetectionInterval) == 0 ||
        _detectedFaceCount == 0) {
        size_t detectedFaceCount = 0;
        const int32_t detectStatus = AppleCVADetectFacesWithVisionOrientation(
            pixelBuffer, kVisionOrientation, _detectedFaces,
            sizeof(_detectedFaces) / sizeof(_detectedFaces[0]),
            &detectedFaceCount);
        if (detectStatus == APPLECVA_OK) {
            _detectedFaceCount = detectedFaceCount;
        }
    }

    AppleCVATrackedFace trackedFaces[4];
    AppleCVAFrameResult result;
    AppleCVAFrameResultInit(&result, trackedFaces,
                            sizeof(trackedFaces) / sizeof(trackedFaces[0]));

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

    _lastStatus = AppleCVATrackerProcessFrame(
        _tracker, pixelBuffer, &_cameraParameters, _detectedFaces,
        _detectedFaceCount, timestamp, 150, &result);

    AppleCVATrackedFace bestFace;
    memset(&bestFace, 0, sizeof(bestFace));
    BOOL hasFace = NO;
    if (_lastStatus == APPLECVA_OK) {
        for (size_t i = 0; i < result.tracked_faces_written; ++i) {
            const AppleCVATrackedFace *candidate = &result.tracked_faces[i];
            if (!tracked_face_has_drawable_landmarks(candidate)) {
                continue;
            }
            if (!hasFace || candidate->failure_type < bestFace.failure_type ||
                (candidate->failure_type == bestFace.failure_type &&
                 candidate->confidence > bestFace.confidence)) {
                bestFace = *candidate;
                hasFace = YES;
            }
        }
    }

    const BOOL hasDetectedFace =
        (result.detected_face_count != 0 || _detectedFaceCount != 0);
    const BOOL hasLiveFace = hasFace;
    const BOOL hasStableLiveFace =
        hasLiveFace && tracked_face_is_stable(&bestFace);
    BOOL usingHeldFace = NO;
    BOOL usingLowConfidenceFace = NO;
    if (hasStableLiveFace) {
        _lastGoodFace = bestFace;
        _hasLastGoodFace = YES;
        _lastGoodFaceFrameIndex = _frameIndex;
    }
    if (hasLiveFace) {
        _consecutiveBadFrames = 0;
    } else if (hasDetectedFace) {
        ++_consecutiveBadFrames;
    } else {
        _consecutiveBadFrames = 0;
    }

    AppleCVATrackedFace displayFace;
    memset(&displayFace, 0, sizeof(displayFace));
    BOOL hasDisplayFace = NO;
    if (hasStableLiveFace) {
        displayFace = bestFace;
        hasDisplayFace = YES;
    } else if (hasLiveFace) {
        displayFace = bestFace;
        hasDisplayFace = YES;
        usingLowConfidenceFace = YES;
    } else if (_hasLastGoodFace && hasDetectedFace &&
               (_frameIndex - _lastGoodFaceFrameIndex) <= kHeldFaceMaxFrames) {
        displayFace = _lastGoodFace;
        hasDisplayFace = YES;
        usingHeldFace = YES;
    } else if (_hasLastGoodFace && hasDetectedFace) {
        _hasLastGoodFace = NO;
        memset(&_lastGoodFace, 0, sizeof(_lastGoodFace));
    } else if (!hasDetectedFace) {
        _hasLastGoodFace = NO;
        memset(&_lastGoodFace, 0, sizeof(_lastGoodFace));
    }

    ++_frameIndex;
    [self updateFps];

    NSString *message = nil;
    if (usingHeldFace) {
        message = @"Holding last stable face.";
    } else if (usingLowConfidenceFace) {
        message = @"Low confidence tracking.";
    } else if (hasDisplayFace) {
        message = @"Tracking face.";
    } else {
        message = @"Waiting for face...";
    }
    const int32_t displayStatus = _lastStatus;
    const uint64_t displayBadFrameCount = _consecutiveBadFrames;
    const size_t displayDetectedFaceCount = result.detected_face_count;
    const size_t displayTrackedFaceCount = result.tracked_face_count;
    const double displayFps = _fps;
    const AppleCVATrackedFace faceSnapshot = displayFace;
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(dispatch_get_main_queue(), ^{
      [_view updateWithPixelBuffer:pixelBuffer
                              face:hasDisplayFace ? &faceSnapshot : NULL
                           hasFace:hasDisplayFace
                 detectedFaceCount:displayDetectedFaceCount
                  trackedFaceCount:displayTrackedFaceCount
                        lastStatus:displayStatus
                           message:message
                               fps:displayFps
                     badFrameCount:displayBadFrameCount];
      CVPixelBufferRelease(pixelBuffer);
    });
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

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
