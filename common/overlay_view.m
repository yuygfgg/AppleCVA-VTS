#import "overlay_view.h"

#import "tracking_utils.h"

#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

typedef struct {
    uint16_t a;
    uint16_t b;
} LandmarkEdge;

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

static NSString *status_string_for_code(int32_t status) {
    return [NSString
        stringWithFormat:@"%s (%d)", AppleCVAStatusString(status), status];
}

@implementation AppleCVAOverlayView {
    CIContext *_ciContext;
    NSButton *_calibrationButton;
    __weak id _calibrationTarget;
    SEL _calibrationAction;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _ciContext = [CIContext contextWithOptions:nil];
        _message = @"Starting camera...";
        _lastStatus = APPLECVA_OK;
        _mirrorPreview = YES;
        _showCameraPreview = YES;
        _faceRectUsesTopLeftOrigin = YES;
        AppleCVAOneEuroParameters defaults = AppleCVAOneEuroParametersDefault();
        _oneEuroMinCutoff = defaults.min_cutoff;
        _oneEuroBeta = defaults.beta;
        _oneEuroDerivativeCutoff = defaults.derivative_cutoff;
        _calibrationButtonTitle = @"Calibrate";
        _calibrationButtonEnabled = YES;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;

        _calibrationButton =
            [NSButton buttonWithTitle:_calibrationButtonTitle
                               target:self
                               action:@selector(performCalibrationAction:)];
        _calibrationButton.bezelStyle = NSBezelStyleRounded;
        _calibrationButton.hidden = YES;
        _calibrationButton.toolTip =
            @"Relax your mouth, look straight at the camera, then calibrate.";
        [self addSubview:_calibrationButton];
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

- (void)layout {
    [super layout];
    const CGFloat width = 112.0;
    const CGFloat height = 30.0;
    _calibrationButton.frame =
        NSMakeRect(NSMaxX(self.bounds) - width - 14.0,
                   NSMaxY(self.bounds) - height - 14.0, width, height);
}

- (void)setShowsCalibrationButton:(BOOL)showsCalibrationButton {
    _showsCalibrationButton = showsCalibrationButton;
    _calibrationButton.hidden = !showsCalibrationButton;
}

- (void)setCalibrationButtonEnabled:(BOOL)calibrationButtonEnabled {
    _calibrationButtonEnabled = calibrationButtonEnabled;
    _calibrationButton.enabled = calibrationButtonEnabled;
}

- (void)setCalibrationButtonTitle:(NSString *)calibrationButtonTitle {
    _calibrationButtonTitle = [calibrationButtonTitle copy] ?: @"Calibrate";
    _calibrationButton.title = _calibrationButtonTitle;
}

- (void)setCalibrationTarget:(id)target action:(SEL)action {
    _calibrationTarget = target;
    _calibrationAction = action;
}

- (void)performCalibrationAction:(id)sender {
    if (!self.calibrationButtonEnabled) {
        return;
    }
    if (_calibrationTarget == nil || _calibrationAction == NULL) {
        return;
    }
    [NSApp sendAction:_calibrationAction to:_calibrationTarget from:sender];
}

- (void)notifySettingsChanged {
    if (self.settingsChangedHandler != nil) {
        self.settingsChangedHandler(self);
    }
}

- (void)keyDown:(NSEvent *)event {
    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    if ([characters isEqualToString:@"c"]) {
        [self performCalibrationAction:self];
        return;
    }
    if ([characters isEqualToString:@"x"]) {
        self.mirrorPreview = !self.mirrorPreview;
        [self notifySettingsChanged];
        self.needsDisplay = YES;
        return;
    }
    if ([characters isEqualToString:@"p"]) {
        self.showCameraPreview = !self.showCameraPreview;
        [self notifySettingsChanged];
        self.needsDisplay = YES;
        return;
    }
    if ([characters isEqualToString:@"y"]) {
        self.flipLandmarkShapeY = !self.flipLandmarkShapeY;
        [self notifySettingsChanged];
        self.needsDisplay = YES;
        return;
    }
    if ([characters isEqualToString:@"b"]) {
        self.faceRectUsesTopLeftOrigin = !self.faceRectUsesTopLeftOrigin;
        [self notifySettingsChanged];
        self.needsDisplay = YES;
        return;
    }
    if ([characters isEqualToString:@"e"]) {
        self.useOneEuroFilter = !self.useOneEuroFilter;
        [self notifySettingsChanged];
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
                          fps:(double)fps {
    [self updateWithPixelBuffer:pixelBuffer
                           face:face
                        hasFace:hasFace
              detectedFaceCount:detectedFaceCount
               trackedFaceCount:trackedFaceCount
                     lastStatus:lastStatus
                        message:message
                extraStatusLine:self.extraStatusLine
                            fps:fps];
}

- (void)updateWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                         face:(const AppleCVATrackedFace *)face
                      hasFace:(BOOL)hasFace
            detectedFaceCount:(size_t)detectedFaceCount
             trackedFaceCount:(size_t)trackedFaceCount
                   lastStatus:(int32_t)lastStatus
                      message:(NSString *)message
              extraStatusLine:(NSString *)extraStatusLine
                          fps:(double)fps {
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
    self.extraStatusLine = extraStatusLine ?: @"";
    _fps = fps;
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

        if (self.showCameraPreview) {
            CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
            CGRect fromRect =
                CGRectMake(0.0, 0.0, (CGFloat)imageWidth, (CGFloat)imageHeight);
            if (self.mirrorPreview) {
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
            sourceUsesTopLeftOrigin:self.faceRectUsesTopLeftOrigin
                            outRect:&landmarkBounds];
    NSRect faceBounds = NSZeroRect;
    if ((face->rect[2] > 0.0f && face->rect[3] > 0.0f &&
         (faceBounds = rect_for_normalized_face_rect(
              face->rect, imageRect, self.faceRectUsesTopLeftOrigin,
              self.mirrorPreview),
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
    if (!AppleCVATrackedFaceHasDrawableLandmarks(face) || outRect == NULL) {
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
                                  sourceUsesTopLeftOrigin, self.mirrorPreview);
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
    NSPoint point = point_for_image_point(
        x, y, imageWidth, imageHeight, imageRect,
        self.faceRectUsesTopLeftOrigin, self.mirrorPreview);
    if (self.flipLandmarkShapeY && hasLandmarkBounds) {
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
        if (!self.showCameraPreview) {
            [text appendString:@"  preview off"];
        }
        [text appendFormat:@"\nbackend %@  one-euro %@",
                           self.useFullBackend ? @"full" : @"lite",
                           self.useOneEuroFilter ? @"on" : @"off"];
        [text appendFormat:@"  min %.2f beta %.4f d %.2f",
                           self.oneEuroMinCutoff, self.oneEuroBeta,
                           self.oneEuroDerivativeCutoff];
        if (self.extraStatusLine.length != 0) {
            [text appendFormat:@"\n%@", self.extraStatusLine];
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
