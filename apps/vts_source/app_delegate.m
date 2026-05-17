#import "app_delegate.h"

#import "calibration.h"
#import "client.h"
#import "overlay_view.h"
#import "parameters.h"
#import "tracking_pipeline.h"
#import "tracking_utils.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

#include <math.h>
#include <stdint.h>

static const uint16_t kDefaultVTSPort = 8001;
static const CGFloat kInitialWindowWidth = 1320.0;
static const CGFloat kInitialWindowHeight = 760.0;
static const CGFloat kSettingsPanelWidth = 340.0;
static const CGFloat kSettingsLabelWidth = 94.0;
static const double kOneEuroMinCutoffMinimum = 0.01;
static const double kOneEuroMinCutoffMaximum = 10.0;
static const double kOneEuroBetaMinimum = 0.0;
static const double kOneEuroBetaMaximum = 0.05;
static const double kOneEuroDerivativeCutoffMinimum = 0.01;
static const double kOneEuroDerivativeCutoffMaximum = 10.0;

static NSString *const kDefaultsHostKey = @"vts_source.host";
static NSString *const kDefaultsPortKey = @"vts_source.port";
static NSString *const kDefaultsUseFullBackendKey = @"vts_source.full_backend";
static NSString *const kDefaultsEnableFilterKey = @"vts_source.enable_filter";
static NSString *const kDefaultsIncludeCustomKey = @"vts_source.include_custom";
static NSString *const kDefaultsIncludeARKitAliasesKey =
    @"vts_source.include_arkit_aliases";
static NSString *const kDefaultsIncludeACVABlendshapesKey =
    @"vts_source.include_acva_blendshapes";
static NSString *const kDefaultsMirrorPreviewKey = @"vts_source.mirror_preview";
static NSString *const kDefaultsShowCameraPreviewKey =
    @"vts_source.show_camera_preview";
static NSString *const kDefaultsFlipLandmarkYKey =
    @"vts_source.flip_landmark_y";
static NSString *const kDefaultsTopLeftOriginKey =
    @"vts_source.top_left_origin";
static NSString *const kDefaultsCameraUniqueIDKey =
    @"vts_source.camera.unique_id";
static NSString *const kDefaultsOneEuroMinCutoffKey =
    @"vts_source.one_euro.min_cutoff";
static NSString *const kDefaultsOneEuroBetaKey = @"vts_source.one_euro.beta";
static NSString *const kDefaultsOneEuroDerivativeCutoffKey =
    @"vts_source.one_euro.derivative_cutoff";

static BOOL default_bool(NSString *key, BOOL fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue]
                                                           : fallback;
}

static double default_double(NSString *key, double fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value respondsToSelector:@selector(doubleValue)]
               ? [value doubleValue]
               : fallback;
}

static double clamp_double(double value, double minimum, double maximum) {
    if (!isfinite(value)) {
        return minimum;
    }
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

static BOOL parse_port(NSString *string, uint16_t *outPort) {
    NSString *trimmed = [string
        stringByTrimmingCharactersInSet:NSCharacterSet
                                            .whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSInteger value = 0;
    if (![scanner scanInteger:&value] || !scanner.isAtEnd || value <= 0 ||
        value > UINT16_MAX) {
        return NO;
    }
    if (outPort != NULL) {
        *outPort = (uint16_t)value;
    }
    return YES;
}

static BOOL parse_double_value(NSString *string, double *outValue) {
    NSString *trimmed = [string
        stringByTrimmingCharactersInSet:NSCharacterSet
                                            .whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    double value = 0.0;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value)) {
        return NO;
    }
    if (outValue != NULL) {
        *outValue = value;
    }
    return YES;
}

static NSString *format_float(double value, NSUInteger fractionDigits) {
    return [NSString stringWithFormat:@"%.*f", (int)fractionDigits, value];
}

static NSArray<AVCaptureDevice *> *available_video_capture_devices(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<AVCaptureDevice *> *devices =
        [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
#pragma clang diagnostic pop
    return devices != nil ? devices : @[];
}

static NSString *camera_title(AVCaptureDevice *device,
                              NSString *defaultUniqueID) {
    NSString *name =
        device.localizedName.length != 0 ? device.localizedName : @"Camera";
    if (defaultUniqueID.length != 0 &&
        [device.uniqueID isEqualToString:defaultUniqueID]) {
        return [name stringByAppendingString:@" (System default)"];
    }
    return name;
}

static NSTextField *make_label(NSString *title, CGFloat size,
                               NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:title ?: @""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = NSColor.labelColor;
    return label;
}

static NSTextField *make_section_label(NSString *title) {
    NSTextField *label =
        make_label([title uppercaseString], 11.0, NSFontWeightSemibold);
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

static NSView *make_spacer(CGFloat height) {
    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
    return view;
}

static NSButton *make_checkbox(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title ?: @""
                                          target:target
                                          action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setButtonType:NSButtonTypeSwitch];
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    return button;
}

static NSStackView *make_row(NSString *labelText, NSView *control) {
    NSTextField *label =
        make_label(labelText ?: @"", 12.0, NSFontWeightRegular);
    [label.widthAnchor constraintEqualToConstant:kSettingsLabelWidth].active =
        YES;

    NSStackView *row = [NSStackView stackViewWithViews:@[ label, control ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8.0;
    [control.widthAnchor constraintEqualToConstant:190.0].active = YES;
    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

static NSStackView *make_slider_row(NSString *labelText, NSSlider *slider,
                                    NSTextField *field) {
    NSTextField *label =
        make_label(labelText ?: @"", 12.0, NSFontWeightRegular);
    [label.widthAnchor constraintEqualToConstant:kSettingsLabelWidth].active =
        YES;
    [slider.widthAnchor constraintEqualToConstant:112.0].active = YES;
    [field.widthAnchor constraintEqualToConstant:72.0].active = YES;

    NSStackView *row =
        [NSStackView stackViewWithViews:@[ label, slider, field ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8.0;
    return row;
}

static float parameter_value_for_id(NSArray<NSDictionary *> *parameterValues,
                                    NSString *parameterID, BOOL *outFound) {
    if (outFound != NULL) {
        *outFound = NO;
    }
    for (NSDictionary *parameter in parameterValues) {
        if (![parameter isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *candidateID = parameter[@"id"];
        if (![candidateID isKindOfClass:NSString.class] ||
            ![candidateID isEqualToString:parameterID]) {
            continue;
        }
        NSNumber *value = parameter[@"value"];
        if (![value isKindOfClass:NSNumber.class]) {
            continue;
        }
        if (outFound != NULL) {
            *outFound = YES;
        }
        return value.floatValue;
    }
    return 0.0f;
}

@implementation VTSAppDelegate {
    NSString *_host;
    uint16_t _port;
    BOOL _useFullBackend;
    BOOL _enableFilter;
    BOOL _includeCustomParameters;
    BOOL _includeARKitAliases;
    BOOL _includeACVABlendshapeParameters;
    NSString *_selectedCameraUniqueID;
    NSArray<AVCaptureDevice *> *_cameraDevices;
    AppleCVAOneEuroParameters _oneEuroParameters;

    NSWindow *_window;
    NSView *_rootView;
    AppleCVAOverlayView *_view;
    AppleCVATrackingPipeline *_pipeline;
    VTSCalibrationController *_calibrationController;
    VTSClient *_vtsClient;

    NSButton *_calibrationButton;
    NSTextField *_hostField;
    NSTextField *_portField;
    NSPopUpButton *_cameraPopup;
    NSPopUpButton *_backendPopup;
    NSButton *_useOneEuroCheckbox;
    NSButton *_customParametersCheckbox;
    NSButton *_arkitAliasesCheckbox;
    NSButton *_acvaBlendshapeCheckbox;
    NSButton *_mirrorPreviewCheckbox;
    NSButton *_showCameraPreviewCheckbox;
    NSButton *_flipLandmarkYCheckbox;
    NSButton *_topLeftOriginCheckbox;
    NSSlider *_oneEuroMinCutoffSlider;
    NSSlider *_oneEuroBetaSlider;
    NSSlider *_oneEuroDerivativeCutoffSlider;
    NSTextField *_oneEuroMinCutoffField;
    NSTextField *_oneEuroBetaField;
    NSTextField *_oneEuroDerivativeCutoffField;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *host = [defaults stringForKey:kDefaultsHostKey];
        _host = host.length != 0 ? [host copy] : @"127.0.0.1";

        NSInteger port = [defaults integerForKey:kDefaultsPortKey];
        _port =
            (port > 0 && port <= UINT16_MAX) ? (uint16_t)port : kDefaultVTSPort;
        _useFullBackend = default_bool(kDefaultsUseFullBackendKey, YES);
        _enableFilter = default_bool(kDefaultsEnableFilterKey, YES);
        _includeCustomParameters = default_bool(kDefaultsIncludeCustomKey, YES);
        _includeARKitAliases =
            default_bool(kDefaultsIncludeARKitAliasesKey, YES);
        _includeACVABlendshapeParameters =
            default_bool(kDefaultsIncludeACVABlendshapesKey, NO);
        NSString *cameraUniqueID =
            [defaults stringForKey:kDefaultsCameraUniqueIDKey];
        _selectedCameraUniqueID =
            cameraUniqueID.length != 0 ? [cameraUniqueID copy] : nil;

        _oneEuroParameters = AppleCVAOneEuroParametersDefault();
        _oneEuroParameters.min_cutoff = (float)default_double(
            kDefaultsOneEuroMinCutoffKey, _oneEuroParameters.min_cutoff);
        _oneEuroParameters.beta = (float)default_double(
            kDefaultsOneEuroBetaKey, _oneEuroParameters.beta);
        _oneEuroParameters.derivative_cutoff =
            (float)default_double(kDefaultsOneEuroDerivativeCutoffKey,
                                  _oneEuroParameters.derivative_cutoff);
        _oneEuroParameters =
            AppleCVAOneEuroParametersSanitize(_oneEuroParameters);

        _calibrationController = [[VTSCalibrationController alloc] init];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    _rootView =
        [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, kInitialWindowWidth,
                                                 kInitialWindowHeight)];
    _rootView.wantsLayer = YES;
    _rootView.layer.backgroundColor = NSColor.blackColor.CGColor;

    _view = [[AppleCVAOverlayView alloc] initWithFrame:NSZeroRect];
    _view.translatesAutoresizingMaskIntoConstraints = NO;
    _view.useFullBackend = _useFullBackend;
    _view.useOneEuroFilter = _enableFilter;
    _view.oneEuroMinCutoff = _oneEuroParameters.min_cutoff;
    _view.oneEuroBeta = _oneEuroParameters.beta;
    _view.oneEuroDerivativeCutoff = _oneEuroParameters.derivative_cutoff;
    _view.mirrorPreview = default_bool(kDefaultsMirrorPreviewKey, YES);
    _view.showCameraPreview = default_bool(kDefaultsShowCameraPreviewKey, YES);
    _view.flipLandmarkShapeY = default_bool(kDefaultsFlipLandmarkYKey, NO);
    _view.faceRectUsesTopLeftOrigin =
        default_bool(kDefaultsTopLeftOriginKey, YES);
    _view.showsCalibrationButton = NO;
    [_view setCalibrationTarget:self action:@selector(startCalibration:)];

    NSView *settingsPanel = [self makeSettingsPanel];
    [_rootView addSubview:_view];
    [_rootView addSubview:settingsPanel];
    [NSLayoutConstraint activateConstraints:@[
        [_view.leadingAnchor constraintEqualToAnchor:_rootView.leadingAnchor],
        [_view.topAnchor constraintEqualToAnchor:_rootView.topAnchor],
        [_view.bottomAnchor constraintEqualToAnchor:_rootView.bottomAnchor],
        [_view.trailingAnchor
            constraintEqualToAnchor:settingsPanel.leadingAnchor],
        [settingsPanel.topAnchor constraintEqualToAnchor:_rootView.topAnchor],
        [settingsPanel.bottomAnchor
            constraintEqualToAnchor:_rootView.bottomAnchor],
        [settingsPanel.trailingAnchor
            constraintEqualToAnchor:_rootView.trailingAnchor],
        [settingsPanel.widthAnchor
            constraintEqualToConstant:kSettingsPanelWidth],
    ]];

    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(140.0, 120.0, kInitialWindowWidth,
                                       kInitialWindowHeight)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.title = @"AppleCVA VTS Source";
    _window.minSize = NSMakeSize(1080.0, 620.0);
    _window.contentView = _rootView;
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    __weak VTSAppDelegate *weakSelf = self;
    _view.settingsChangedHandler = ^(AppleCVAOverlayView *view) {
      (void)view;
      VTSAppDelegate *strongSelf = weakSelf;
      if (strongSelf == nil) {
          return;
      }
      [strongSelf applyPreviewSettingsFromView];
    };

    NSNotificationCenter *notificationCenter =
        NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(cameraDevicesChanged:)
                               name:AVCaptureDeviceWasConnectedNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(cameraDevicesChanged:)
                               name:AVCaptureDeviceWasDisconnectedNotification
                             object:nil];

    _pipeline = [self makeTrackingPipeline];
    [_view
        updateWithPixelBuffer:NULL
                         face:NULL
                      hasFace:NO
            detectedFaceCount:0
             trackedFaceCount:0
                   lastStatus:APPLECVA_OK
                      message:@"Calibration required."
              extraStatusLine:[self
                                  currentExtraStatusLineWithParameterValues:nil]
                          fps:0.0];
    [self syncAllControlsFromState];
    [_pipeline start];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_pipeline stop];
    [self stopVTSClient];
}

- (NSView *)makeSettingsPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSZeroRect];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.wantsLayer = YES;
    panel.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8.0;
    stack.edgeInsets = NSEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
    [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor],
    ]];

    NSTextField *title =
        make_label(@"AppleCVA VTS Source", 17.0, NSFontWeightSemibold);
    [stack addArrangedSubview:title];

    _calibrationButton =
        [NSButton buttonWithTitle:@"Calibrate First"
                           target:self
                           action:@selector(startCalibration:)];
    _calibrationButton.translatesAutoresizingMaskIntoConstraints = NO;
    _calibrationButton.bezelStyle = NSBezelStyleRounded;
    [_calibrationButton.widthAnchor
        constraintEqualToConstant:kSettingsPanelWidth - 32.0]
        .active = YES;
    [stack addArrangedSubview:_calibrationButton];

    [stack addArrangedSubview:make_spacer(4.0)];
    [stack addArrangedSubview:make_section_label(@"VTS")];
    _hostField = [self makeTextFieldWithAction:@selector(connectionChanged:)];
    _portField = [self makeTextFieldWithAction:@selector(connectionChanged:)];
    [stack addArrangedSubview:make_row(@"Host", _hostField)];
    [stack addArrangedSubview:make_row(@"Port", _portField)];

    _customParametersCheckbox = make_checkbox(
        @"Inject custom parameters", self, @selector(trackingOptionsChanged:));
    _arkitAliasesCheckbox = make_checkbox(@"Include ARKit aliases", self,
                                          @selector(trackingOptionsChanged:));
    _acvaBlendshapeCheckbox = make_checkbox(@"Fill raw ACVA blendshapes", self,
                                            @selector(trackingOptionsChanged:));
    [stack addArrangedSubview:_customParametersCheckbox];
    [stack addArrangedSubview:_arkitAliasesCheckbox];
    [stack addArrangedSubview:_acvaBlendshapeCheckbox];

    [stack addArrangedSubview:make_spacer(4.0)];
    [stack addArrangedSubview:make_section_label(@"Tracking")];
    _cameraPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                              pullsDown:NO];
    _cameraPopup.translatesAutoresizingMaskIntoConstraints = NO;
    _cameraPopup.target = self;
    _cameraPopup.action = @selector(cameraSelectionChanged:);
    [self reloadCameraDevices];
    [stack addArrangedSubview:make_row(@"Camera", _cameraPopup)];

    _backendPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                               pullsDown:NO];
    _backendPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_backendPopup addItemsWithTitles:@[ @"Lite backend", @"Full backend" ]];
    _backendPopup.target = self;
    _backendPopup.action = @selector(trackingOptionsChanged:);
    [stack addArrangedSubview:make_row(@"Backend", _backendPopup)];

    _useOneEuroCheckbox = make_checkbox(@"Use One Euro filter", self,
                                        @selector(trackingOptionsChanged:));
    [stack addArrangedSubview:_useOneEuroCheckbox];

    [stack addArrangedSubview:make_spacer(4.0)];
    [stack addArrangedSubview:make_section_label(@"One Euro")];
    _oneEuroMinCutoffSlider =
        [self makeSliderWithMin:kOneEuroMinCutoffMinimum
                            max:kOneEuroMinCutoffMaximum
                         action:@selector(oneEuroSliderChanged:)];
    _oneEuroBetaSlider =
        [self makeSliderWithMin:kOneEuroBetaMinimum
                            max:kOneEuroBetaMaximum
                         action:@selector(oneEuroSliderChanged:)];
    _oneEuroDerivativeCutoffSlider =
        [self makeSliderWithMin:kOneEuroDerivativeCutoffMinimum
                            max:kOneEuroDerivativeCutoffMaximum
                         action:@selector(oneEuroSliderChanged:)];
    _oneEuroMinCutoffField =
        [self makeTextFieldWithAction:@selector(oneEuroFieldChanged:)];
    _oneEuroBetaField =
        [self makeTextFieldWithAction:@selector(oneEuroFieldChanged:)];
    _oneEuroDerivativeCutoffField =
        [self makeTextFieldWithAction:@selector(oneEuroFieldChanged:)];
    [stack addArrangedSubview:make_slider_row(@"Min cutoff",
                                              _oneEuroMinCutoffSlider,
                                              _oneEuroMinCutoffField)];
    [stack addArrangedSubview:make_slider_row(@"Beta", _oneEuroBetaSlider,
                                              _oneEuroBetaField)];
    [stack addArrangedSubview:make_slider_row(@"Derivative",
                                              _oneEuroDerivativeCutoffSlider,
                                              _oneEuroDerivativeCutoffField)];

    [stack addArrangedSubview:make_spacer(4.0)];
    [stack addArrangedSubview:make_section_label(@"Preview")];
    _mirrorPreviewCheckbox = make_checkbox(@"Mirror preview", self,
                                           @selector(previewOptionsChanged:));
    _showCameraPreviewCheckbox = make_checkbox(
        @"Show camera preview", self, @selector(previewOptionsChanged:));
    _flipLandmarkYCheckbox = make_checkbox(@"Flip landmark Y", self,
                                           @selector(previewOptionsChanged:));
    _topLeftOriginCheckbox = make_checkbox(@"Top-left source origin", self,
                                           @selector(previewOptionsChanged:));
    [stack addArrangedSubview:_mirrorPreviewCheckbox];
    [stack addArrangedSubview:_showCameraPreviewCheckbox];
    [stack addArrangedSubview:_flipLandmarkYCheckbox];
    [stack addArrangedSubview:_topLeftOriginCheckbox];

    return panel;
}

- (NSTextField *)makeTextFieldWithAction:(SEL)action {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.target = self;
    field.action = action;
    field.delegate = self;
    field.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    field.controlSize = NSControlSizeSmall;
    return field;
}

- (NSSlider *)makeSliderWithMin:(double)minimum
                            max:(double)maximum
                         action:(SEL)action {
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minValue = minimum;
    slider.maxValue = maximum;
    slider.continuous = YES;
    slider.target = self;
    slider.action = action;
    slider.controlSize = NSControlSizeSmall;
    return slider;
}

- (AppleCVATrackingPipeline *)makeTrackingPipeline {
    AVCaptureDevice *captureDevice = [self selectedCameraDevice];
    AppleCVATrackingPipeline *pipeline = [[AppleCVATrackingPipeline alloc]
        initWithFullBackend:_useFullBackend
              captureDevice:captureDevice
          captureQueueLabel:@"local.applecva.vts-source.capture"];
    pipeline.useOneEuroFilter = _enableFilter;
    pipeline.oneEuroParameters = _oneEuroParameters;

    __weak VTSAppDelegate *weakSelf = self;
    pipeline.statusHandler = ^(NSString *message, int32_t status) {
      [weakSelf handlePipelineStatusMessage:message status:status];
    };
    pipeline.frameHandler =
        ^(CVPixelBufferRef pixelBuffer, const AppleCVATrackedFace *face,
          BOOL hasFace, size_t detectedFaceCount, size_t trackedFaceCount,
          int32_t status, double timestamp, double fps) {
          (void)timestamp;
          [weakSelf handleTrackingPixelBuffer:pixelBuffer
                                         face:face
                                      hasFace:hasFace
                            detectedFaceCount:detectedFaceCount
                             trackedFaceCount:trackedFaceCount
                                       status:status
                                          fps:fps];
        };
    return pipeline;
}

- (void)syncAllControlsFromState {
    [self syncConnectionControls];
    [self syncCameraControl];
    [self syncTrackingControls];
    [self syncOneEuroControls];
    [self syncPreviewControlsFromView];
    [self syncControlEnabledStates];
    [self updateCalibrationControlOnMain];
}

- (void)syncConnectionControls {
    _hostField.stringValue = _host ?: @"127.0.0.1";
    _portField.stringValue = [NSString stringWithFormat:@"%u", _port];
}

- (void)syncTrackingControls {
    [_backendPopup selectItemAtIndex:_useFullBackend ? 1 : 0];
    _useOneEuroCheckbox.state =
        _enableFilter ? NSControlStateValueOn : NSControlStateValueOff;
    _customParametersCheckbox.state = _includeCustomParameters
                                          ? NSControlStateValueOn
                                          : NSControlStateValueOff;
    _arkitAliasesCheckbox.state =
        _includeARKitAliases ? NSControlStateValueOn : NSControlStateValueOff;
    _acvaBlendshapeCheckbox.state = _includeACVABlendshapeParameters
                                        ? NSControlStateValueOn
                                        : NSControlStateValueOff;
}

- (void)syncOneEuroControls {
    _oneEuroMinCutoffSlider.doubleValue = _oneEuroParameters.min_cutoff;
    _oneEuroBetaSlider.doubleValue = _oneEuroParameters.beta;
    _oneEuroDerivativeCutoffSlider.doubleValue =
        _oneEuroParameters.derivative_cutoff;
    _oneEuroMinCutoffField.stringValue =
        format_float(_oneEuroParameters.min_cutoff, 2);
    _oneEuroBetaField.stringValue = format_float(_oneEuroParameters.beta, 4);
    _oneEuroDerivativeCutoffField.stringValue =
        format_float(_oneEuroParameters.derivative_cutoff, 2);
}

- (void)syncPreviewControlsFromView {
    _mirrorPreviewCheckbox.state =
        _view.mirrorPreview ? NSControlStateValueOn : NSControlStateValueOff;
    _showCameraPreviewCheckbox.state = _view.showCameraPreview
                                           ? NSControlStateValueOn
                                           : NSControlStateValueOff;
    _flipLandmarkYCheckbox.state = _view.flipLandmarkShapeY
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
    _topLeftOriginCheckbox.state = _view.faceRectUsesTopLeftOrigin
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
}

- (void)syncControlEnabledStates {
    _cameraPopup.enabled = _cameraDevices.count != 0;
    _arkitAliasesCheckbox.enabled = _includeCustomParameters;
    _acvaBlendshapeCheckbox.enabled = _includeCustomParameters;
}

- (void)syncCameraControl {
    if (_cameraPopup == nil) {
        return;
    }
    NSString *selectedUniqueID = _selectedCameraUniqueID ?: @"";
    NSInteger selectedIndex = 0;
    for (NSInteger index = 0; index < _cameraPopup.numberOfItems; ++index) {
        NSMenuItem *item = [_cameraPopup itemAtIndex:index];
        NSString *uniqueID =
            [item.representedObject isKindOfClass:NSString.class]
                ? item.representedObject
                : @"";
        if ([uniqueID isEqualToString:selectedUniqueID]) {
            selectedIndex = index;
            break;
        }
    }
    [_cameraPopup selectItemAtIndex:selectedIndex];
}

- (void)reloadCameraDevices {
    _cameraDevices = [available_video_capture_devices() copy];
    if (_cameraPopup == nil) {
        return;
    }

    [_cameraPopup removeAllItems];
    if (_cameraDevices.count == 0) {
        [_cameraPopup addItemWithTitle:@"No cameras found"];
        _cameraPopup.lastItem.representedObject = @"";
        _cameraPopup.enabled = NO;
        return;
    }

    AVCaptureDevice *defaultDevice =
        [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSString *defaultUniqueID = defaultDevice.uniqueID ?: @"";
    [_cameraPopup addItemWithTitle:@"System default"];
    _cameraPopup.lastItem.representedObject = @"";
    for (AVCaptureDevice *device in _cameraDevices) {
        [_cameraPopup addItemWithTitle:camera_title(device, defaultUniqueID)];
        _cameraPopup.lastItem.representedObject = device.uniqueID ?: @"";
    }
    _cameraPopup.enabled = YES;
    [self syncCameraControl];
}

- (AVCaptureDevice *)selectedCameraDevice {
    if (_selectedCameraUniqueID.length == 0) {
        return nil;
    }
    AVCaptureDevice *device =
        [self selectedCameraDeviceInDevices:_cameraDevices];
    if (device != nil) {
        return device;
    }
    return [AVCaptureDevice deviceWithUniqueID:_selectedCameraUniqueID];
}

- (AVCaptureDevice *)selectedCameraDeviceInDevices:
    (NSArray<AVCaptureDevice *> *)devices {
    if (_selectedCameraUniqueID.length == 0) {
        return nil;
    }
    for (AVCaptureDevice *device in devices) {
        if ([device.uniqueID isEqualToString:_selectedCameraUniqueID]) {
            return device;
        }
    }
    return nil;
}

- (void)saveSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:_host ?: @"127.0.0.1" forKey:kDefaultsHostKey];
    [defaults setInteger:_port forKey:kDefaultsPortKey];
    [defaults setBool:_useFullBackend forKey:kDefaultsUseFullBackendKey];
    [defaults setBool:_enableFilter forKey:kDefaultsEnableFilterKey];
    [defaults setBool:_includeCustomParameters
               forKey:kDefaultsIncludeCustomKey];
    [defaults setBool:_includeARKitAliases
               forKey:kDefaultsIncludeARKitAliasesKey];
    [defaults setBool:_includeACVABlendshapeParameters
               forKey:kDefaultsIncludeACVABlendshapesKey];
    if (_selectedCameraUniqueID.length != 0) {
        [defaults setObject:_selectedCameraUniqueID
                     forKey:kDefaultsCameraUniqueIDKey];
    } else {
        [defaults removeObjectForKey:kDefaultsCameraUniqueIDKey];
    }
    if (_view != nil) {
        [defaults setBool:_view.mirrorPreview forKey:kDefaultsMirrorPreviewKey];
        [defaults setBool:_view.showCameraPreview
                   forKey:kDefaultsShowCameraPreviewKey];
        [defaults setBool:_view.flipLandmarkShapeY
                   forKey:kDefaultsFlipLandmarkYKey];
        [defaults setBool:_view.faceRectUsesTopLeftOrigin
                   forKey:kDefaultsTopLeftOriginKey];
    }
    [defaults setDouble:_oneEuroParameters.min_cutoff
                 forKey:kDefaultsOneEuroMinCutoffKey];
    [defaults setDouble:_oneEuroParameters.beta forKey:kDefaultsOneEuroBetaKey];
    [defaults setDouble:_oneEuroParameters.derivative_cutoff
                 forKey:kDefaultsOneEuroDerivativeCutoffKey];
}

- (void)cameraSelectionChanged:(id)sender {
    (void)sender;
    NSMenuItem *selectedItem = _cameraPopup.selectedItem;
    NSString *selectedUniqueID =
        [selectedItem.representedObject isKindOfClass:NSString.class]
            ? selectedItem.representedObject
            : @"";
    NSString *currentUniqueID = _selectedCameraUniqueID ?: @"";
    if ([selectedUniqueID isEqualToString:currentUniqueID]) {
        return;
    }

    _selectedCameraUniqueID =
        selectedUniqueID.length != 0 ? [selectedUniqueID copy] : nil;
    [self saveSettings];
    [self restartTrackingPipelineResetCalibration:YES];
}

- (void)cameraDevicesChanged:(NSNotification *)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
      BOOL selectedCameraWasAvailable =
          [self selectedCameraDeviceInDevices:self->_cameraDevices] != nil;
      [self reloadCameraDevices];
      BOOL selectedCameraIsAvailable =
          [self selectedCameraDeviceInDevices:self->_cameraDevices] != nil;
      [self syncControlEnabledStates];
      if (self->_selectedCameraUniqueID.length != 0 &&
          selectedCameraWasAvailable != selectedCameraIsAvailable) {
          [self restartTrackingPipelineResetCalibration:YES];
      }
    });
}

- (void)restartTrackingPipelineResetCalibration:(BOOL)resetCalibration {
    [self stopVTSClient];
    [_pipeline stop];
    if (resetCalibration) {
        _calibrationController = [[VTSCalibrationController alloc] init];
    }
    _pipeline = [self makeTrackingPipeline];
    [_pipeline start];
    [self updateCalibrationControlOnMain];
    _view.needsDisplay = YES;
}

- (void)connectionChanged:(id)sender {
    (void)sender;
    NSString *host = [_hostField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet
                                            .whitespaceAndNewlineCharacterSet];
    uint16_t port = 0;
    if (host.length == 0 || !parse_port(_portField.stringValue, &port)) {
        NSBeep();
        [self syncConnectionControls];
        return;
    }

    const BOOL changed = ![_host isEqualToString:host] || _port != port;
    if (!changed) {
        return;
    }

    _host = [host copy];
    _port = port;
    [self saveSettings];
    [self stopVTSClient];
    _view.needsDisplay = YES;
}

- (void)trackingOptionsChanged:(id)sender {
    (void)sender;
    const BOOL newUseFullBackend = _backendPopup.indexOfSelectedItem == 1;
    const BOOL newEnableFilter =
        _useOneEuroCheckbox.state == NSControlStateValueOn;
    const BOOL newIncludeCustom =
        _customParametersCheckbox.state == NSControlStateValueOn;
    const BOOL newIncludeAliases =
        _arkitAliasesCheckbox.state == NSControlStateValueOn;
    const BOOL newIncludeACVABlendshapes =
        _acvaBlendshapeCheckbox.state == NSControlStateValueOn;

    const BOOL backendChanged = _useFullBackend != newUseFullBackend;
    const BOOL injectionChanged =
        _includeCustomParameters != newIncludeCustom ||
        _includeARKitAliases != newIncludeAliases ||
        _includeACVABlendshapeParameters != newIncludeACVABlendshapes;

    _useFullBackend = newUseFullBackend;
    _enableFilter = newEnableFilter;
    _includeCustomParameters = newIncludeCustom;
    _includeARKitAliases = newIncludeAliases;
    _includeACVABlendshapeParameters = newIncludeACVABlendshapes;

    _view.useFullBackend = _useFullBackend;
    _view.useOneEuroFilter = _enableFilter;
    _pipeline.useOneEuroFilter = _enableFilter;
    _pipeline.oneEuroParameters = _oneEuroParameters;

    if (backendChanged) {
        [self restartTrackingPipelineResetCalibration:YES];
    } else if (injectionChanged) {
        [self stopVTSClient];
    }

    [self syncTrackingControls];
    [self syncControlEnabledStates];
    [self updateCalibrationControlOnMain];
    [self saveSettings];
    _view.needsDisplay = YES;
}

- (void)previewOptionsChanged:(id)sender {
    (void)sender;
    _view.mirrorPreview = _mirrorPreviewCheckbox.state == NSControlStateValueOn;
    _view.showCameraPreview =
        _showCameraPreviewCheckbox.state == NSControlStateValueOn;
    _view.flipLandmarkShapeY =
        _flipLandmarkYCheckbox.state == NSControlStateValueOn;
    _view.faceRectUsesTopLeftOrigin =
        _topLeftOriginCheckbox.state == NSControlStateValueOn;
    [self applyPreviewSettingsFromView];
}

- (void)applyPreviewSettingsFromView {
    _enableFilter = _view.useOneEuroFilter;
    _pipeline.useOneEuroFilter = _enableFilter;
    _pipeline.oneEuroParameters = _oneEuroParameters;
    [self syncTrackingControls];
    [self syncPreviewControlsFromView];
    [self saveSettings];
    _view.needsDisplay = YES;
}

- (void)oneEuroSliderChanged:(id)sender {
    AppleCVAOneEuroParameters parameters = _oneEuroParameters;
    if (sender == _oneEuroMinCutoffSlider) {
        parameters.min_cutoff = (float)_oneEuroMinCutoffSlider.doubleValue;
    } else if (sender == _oneEuroBetaSlider) {
        parameters.beta = (float)_oneEuroBetaSlider.doubleValue;
    } else if (sender == _oneEuroDerivativeCutoffSlider) {
        parameters.derivative_cutoff =
            (float)_oneEuroDerivativeCutoffSlider.doubleValue;
    }
    [self applyOneEuroParameters:parameters];
}

- (void)oneEuroFieldChanged:(id)sender {
    (void)sender;
    double minCutoff = 0.0;
    double beta = 0.0;
    double derivativeCutoff = 0.0;
    if (!parse_double_value(_oneEuroMinCutoffField.stringValue, &minCutoff) ||
        !parse_double_value(_oneEuroBetaField.stringValue, &beta) ||
        !parse_double_value(_oneEuroDerivativeCutoffField.stringValue,
                            &derivativeCutoff)) {
        NSBeep();
        [self syncOneEuroControls];
        return;
    }

    AppleCVAOneEuroParameters parameters = _oneEuroParameters;
    parameters.min_cutoff = (float)minCutoff;
    parameters.beta = (float)beta;
    parameters.derivative_cutoff = (float)derivativeCutoff;
    [self applyOneEuroParameters:parameters];
}

- (void)applyOneEuroParameters:(AppleCVAOneEuroParameters)parameters {
    parameters.min_cutoff =
        (float)clamp_double(parameters.min_cutoff, kOneEuroMinCutoffMinimum,
                            kOneEuroMinCutoffMaximum);
    parameters.beta = (float)clamp_double(parameters.beta, kOneEuroBetaMinimum,
                                          kOneEuroBetaMaximum);
    parameters.derivative_cutoff = (float)clamp_double(
        parameters.derivative_cutoff, kOneEuroDerivativeCutoffMinimum,
        kOneEuroDerivativeCutoffMaximum);
    _oneEuroParameters = AppleCVAOneEuroParametersSanitize(parameters);

    _pipeline.oneEuroParameters = _oneEuroParameters;
    _view.oneEuroMinCutoff = _oneEuroParameters.min_cutoff;
    _view.oneEuroBeta = _oneEuroParameters.beta;
    _view.oneEuroDerivativeCutoff = _oneEuroParameters.derivative_cutoff;
    [self syncOneEuroControls];
    [self saveSettings];
    _view.needsDisplay = YES;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    id object = notification.object;
    if (object == _hostField || object == _portField) {
        [self connectionChanged:object];
        return;
    }
    if (object == _oneEuroMinCutoffField || object == _oneEuroBetaField ||
        object == _oneEuroDerivativeCutoffField) {
        [self oneEuroFieldChanged:object];
        return;
    }
}

- (void)startCalibration:(id)sender {
    (void)sender;
    [_calibrationController startCalibration];
    [self stopVTSClient];
    [self updateCalibrationControlOnMain];
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_view.needsDisplay = YES;
    });
}

- (void)handlePipelineStatusMessage:(NSString *)message status:(int32_t)status {
    [_view
        updateWithPixelBuffer:NULL
                         face:NULL
                      hasFace:NO
            detectedFaceCount:0
             trackedFaceCount:0
                   lastStatus:status
                      message:message ?: @""
              extraStatusLine:[self
                                  currentExtraStatusLineWithParameterValues:nil]
                          fps:0.0];
}

- (void)handleTrackingPixelBuffer:(CVPixelBufferRef)pixelBuffer
                             face:(const AppleCVATrackedFace *)face
                          hasFace:(BOOL)hasFace
                detectedFaceCount:(size_t)detectedFaceCount
                 trackedFaceCount:(size_t)trackedFaceCount
                           status:(int32_t)status
                              fps:(double)fps {
    const BOOL calibrationCompleted =
        [_calibrationController collectSampleFromFace:face hasFace:hasFace];
    if (calibrationCompleted) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self updateCalibrationControlOnMain];
        });
    }

    VTSClient *client = nil;
    NSArray<NSDictionary *> *parameterValues = nil;
    VTSAppleCVACalibration calibrationSnapshot =
        _calibrationController.calibration;
    const BOOL calibrated = _calibrationController.calibrated;
    if (calibrated) {
        client = [self ensureVTSClientStartedIfNeeded];
        NSSet<NSString *> *defaultParameterNames =
            [client defaultParameterNamesSnapshot];
        parameterValues = VTSAppleCVAParameterValues(
            face, hasFace, defaultParameterNames, &calibrationSnapshot,
            _includeCustomParameters, _includeARKitAliases,
            _includeACVABlendshapeParameters);
        [client injectParameterValues:parameterValues faceFound:hasFace];
    }

    NSString *message = [self displayMessageForFaceFound:hasFace
                                              calibrated:calibrated];
    NSString *extraStatusLine =
        [self currentExtraStatusLineWithParameterValues:parameterValues];
    const AppleCVATrackedFace faceSnapshot =
        face != NULL ? *face : (AppleCVATrackedFace){0};
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateCalibrationControlOnMain];
      [self->_view updateWithPixelBuffer:pixelBuffer
                                    face:hasFace ? &faceSnapshot : NULL
                                 hasFace:hasFace
                       detectedFaceCount:detectedFaceCount
                        trackedFaceCount:trackedFaceCount
                              lastStatus:status
                                 message:message
                         extraStatusLine:extraStatusLine
                                     fps:fps];
      CVPixelBufferRelease(pixelBuffer);
    });
}

- (NSString *)displayMessageForFaceFound:(BOOL)hasFace
                              calibrated:(BOOL)calibrated {
    if (calibrated) {
        return hasFace ? @"Tracking face." : @"Waiting for face...";
    }
    if (_calibrationController.inProgress) {
        return hasFace ? @"Calibrating neutral pose."
                       : @"Calibration waiting for face.";
    }
    return hasFace ? @"Press Calibrate to unlock VTS."
                   : @"Calibration required.";
}

- (VTSClient *)ensureVTSClientStartedIfNeeded {
    @synchronized(self) {
        if (_vtsClient == nil) {
            _vtsClient =
                [[VTSClient alloc] initWithHost:_host
                                               port:_port
                            includeCustomParameters:_includeCustomParameters
                                includeARKitAliases:_includeARKitAliases
                    includeACVABlendshapeParameters:
                        _includeACVABlendshapeParameters];
            [_vtsClient start];
        }
        return _vtsClient;
    }
}

- (void)stopVTSClient {
    VTSClient *client = nil;
    @synchronized(self) {
        client = _vtsClient;
        _vtsClient = nil;
    }
    [client stop];
}

- (VTSClient *)currentVTSClient {
    @synchronized(self) {
        return _vtsClient;
    }
}

- (NSString *)currentExtraStatusLineWithParameterValues:
    (NSArray<NSDictionary *> *)parameterValues {
    NSString *targetStatus =
        [NSString stringWithFormat:@"target %@:%u", _host, _port];
    NSString *customStatus =
        _includeCustomParameters ? @"custom on" : @"custom off";
    NSString *aliasStatus = (_includeCustomParameters && _includeARKitAliases)
                                ? @"aliases on"
                                : @"aliases off";
    NSString *acvaRawStatus =
        (_includeCustomParameters && _includeACVABlendshapeParameters)
            ? @"acva raw on"
            : @"acva raw off";
    NSString *calibrationStatus = [_calibrationController statusLine];
    if (!_calibrationController.calibrated) {
        return
            [NSString stringWithFormat:@"vts locked  %@  %@  %@  %@  %@",
                                       targetStatus, customStatus, aliasStatus,
                                       acvaRawStatus, calibrationStatus];
    }

    VTSClient *client = [self currentVTSClient];
    NSString *vtsStatus = client != nil ? [client statusLine] : @"vts starting";
    NSString *base =
        [NSString stringWithFormat:@"%@  %@  %@  %@  %@  %@", vtsStatus,
                                   targetStatus, customStatus, aliasStatus,
                                   acvaRawStatus, calibrationStatus];
    if (parameterValues.count == 0) {
        return base;
    }

    BOOL hasMouth = NO;
    const float mouth =
        parameter_value_for_id(parameterValues, @"MouthOpen", &hasMouth);
    BOOL hasJaw = NO;
    const float jaw =
        parameter_value_for_id(parameterValues, @"ACVAJawOpen", &hasJaw);
    BOOL hasEyeLeft = NO;
    BOOL hasEyeRight = NO;
    BOOL hasYaw = NO;
    BOOL hasPitch = NO;
    const float eyeLeft =
        parameter_value_for_id(parameterValues, @"EyeOpenLeft", &hasEyeLeft);
    const float eyeRight =
        parameter_value_for_id(parameterValues, @"EyeOpenRight", &hasEyeRight);
    float yaw = parameter_value_for_id(parameterValues, @"FaceAngleX", &hasYaw);
    if (!hasYaw) {
        yaw =
            parameter_value_for_id(parameterValues, @"ACVAFaceAngleX", &hasYaw);
    }
    float pitch =
        parameter_value_for_id(parameterValues, @"FaceAngleY", &hasPitch);
    if (!hasPitch) {
        pitch = parameter_value_for_id(parameterValues, @"ACVAFaceAngleY",
                                       &hasPitch);
    }
    if (!hasMouth && !hasJaw && !hasEyeLeft && !hasEyeRight && !hasYaw &&
        !hasPitch) {
        return base;
    }
    return [base
        stringByAppendingFormat:@"  mouthVTS %@ jaw %@ eyeL %.2f eyeR %.2f "
                                @"yaw %.1f pitch %.1f",
                                hasMouth
                                    ? [NSString stringWithFormat:@"%.2f", mouth]
                                    : @"-",
                                hasJaw
                                    ? [NSString stringWithFormat:@"%.2f", jaw]
                                    : @"-",
                                eyeLeft, eyeRight, yaw, pitch];
}

- (void)updateCalibrationControlOnMain {
    NSString *title = @"Calibrate First";
    BOOL enabled = YES;
    if (_calibrationController.inProgress) {
        title = @"Calibrating...";
        enabled = NO;
    } else if (_calibrationController.calibrated) {
        title = @"Recalibrate";
        enabled = YES;
    }
    _calibrationButton.title = title;
    _calibrationButton.enabled = enabled;
    _view.calibrationButtonTitle = title;
    _view.calibrationButtonEnabled = enabled;
}

@end
