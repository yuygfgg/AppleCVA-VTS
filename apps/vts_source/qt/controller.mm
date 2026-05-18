#include "controller.h"

#include "calibration.h"
#include "client.h"
#include "parameters.h"
#include "preview_item.h"
#include "tracking_pipeline.h"
#include "tracking_utils.h"

#include <AVFoundation/AVFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <Foundation/Foundation.h>

#include <QImage>
#include <QMetaObject>
#include <QPointer>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>

static const uint16_t kDefaultVTSPort = 8001;
static const int kDefaultBackendMode = APPLECVA_BACKEND_MODE_AUTO;
static const double kOneEuroMinCutoffMinimum = 0.01;
static const double kOneEuroMinCutoffMaximum = 10.0;
static const double kOneEuroBetaMinimum = 0.0;
static const double kOneEuroBetaMaximum = 0.05;
static const double kOneEuroDerivativeCutoffMinimum = 0.01;
static const double kOneEuroDerivativeCutoffMaximum = 10.0;

static NSString *const kDefaultsHostKey = @"vts_source.host";
static NSString *const kDefaultsPortKey = @"vts_source.port";
static NSString *const kDefaultsBackendModeKey = @"vts_source.backend_mode";
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

struct VTSController::Impl {
    mutable std::mutex settingsMutex;
    std::mutex clientMutex;

    QString host = QStringLiteral("127.0.0.1");
    int port = kDefaultVTSPort;
    int backendMode = kDefaultBackendMode;
    bool enableFilter = true;
    bool includeCustomParameters = true;
    bool includeARKitAliases = true;
    bool includeACVABlendshapeParameters = false;
    bool mirrorPreview = true;
    bool showCameraPreview = true;
    bool flipLandmarkY = false;
    bool topLeftOrigin = true;
    QString selectedCameraUniqueID;
    AppleCVAOneEuroParameters oneEuroParameters =
        AppleCVAOneEuroParametersDefault();

    QStringList cameraNames;
    int cameraIndex = 0;
    __strong NSArray<AVCaptureDevice *> *cameraDevices = nil;

    __strong AppleCVATrackingPipeline *pipeline = nil;
    __strong VTSCalibrationController *calibration =
        [[VTSCalibrationController alloc] init];
    __strong VTSClient *client = nil;
    __strong id cameraConnectedObserver = nil;
    __strong id cameraDisconnectedObserver = nil;

    QPointer<VTSPreviewItem> previewItem;

    QString message = QStringLiteral("Calibration required.");
    QString extraStatusLine;
    double fps = 0.0;
    int detectedFaceCount = 0;
    int trackedFaceCount = 0;
    bool hasFace = false;
    double confidence = 0.0;
    int lastStatus = APPLECVA_OK;
};

struct SettingsSnapshot {
    QString host;
    int port = kDefaultVTSPort;
    int backendMode = kDefaultBackendMode;
    bool enableFilter = true;
    bool includeCustomParameters = true;
    bool includeARKitAliases = true;
    bool includeACVABlendshapeParameters = false;
    bool mirrorPreview = true;
    bool showCameraPreview = true;
    bool flipLandmarkY = false;
    bool topLeftOrigin = true;
    QString selectedCameraUniqueID;
    AppleCVAOneEuroParameters oneEuroParameters =
        AppleCVAOneEuroParametersDefault();
};

static QString qStringFromNSString(NSString *string) {
    return string != nil ? QString::fromUtf8(string.UTF8String) : QString();
}

static NSString *nsStringFromQString(const QString &string) {
    const QByteArray bytes = string.toUtf8();
    return [NSString stringWithUTF8String:bytes.constData()];
}

static BOOL default_bool(NSString *key, BOOL fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue]
                                                           : fallback;
}

static int default_int(NSString *key, int fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value respondsToSelector:@selector(integerValue)]
               ? static_cast<int>([value integerValue])
               : fallback;
}

static double default_double(NSString *key, double fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value respondsToSelector:@selector(doubleValue)]
               ? [value doubleValue]
               : fallback;
}

static double clamp_double(double value, double minimum, double maximum) {
    if (!std::isfinite(value)) {
        return minimum;
    }
    return std::min(std::max(value, minimum), maximum);
}

static int sanitize_backend_mode(int mode) {
    switch (mode) {
    case APPLECVA_BACKEND_MODE_LITE:
    case APPLECVA_BACKEND_MODE_FULL:
    case APPLECVA_BACKEND_MODE_AUTO:
        return mode;
    default:
        return kDefaultBackendMode;
    }
}

static SettingsSnapshot snapshotSettings(const VTSController::Impl *impl) {
    std::lock_guard<std::mutex> lock(impl->settingsMutex);
    SettingsSnapshot snapshot;
    snapshot.host = impl->host;
    snapshot.port = impl->port;
    snapshot.backendMode = impl->backendMode;
    snapshot.enableFilter = impl->enableFilter;
    snapshot.includeCustomParameters = impl->includeCustomParameters;
    snapshot.includeARKitAliases = impl->includeARKitAliases;
    snapshot.includeACVABlendshapeParameters =
        impl->includeACVABlendshapeParameters;
    snapshot.mirrorPreview = impl->mirrorPreview;
    snapshot.showCameraPreview = impl->showCameraPreview;
    snapshot.flipLandmarkY = impl->flipLandmarkY;
    snapshot.topLeftOrigin = impl->topLeftOrigin;
    snapshot.selectedCameraUniqueID = impl->selectedCameraUniqueID;
    snapshot.oneEuroParameters = impl->oneEuroParameters;
    return snapshot;
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

static AVCaptureDevice *
selectedCameraDeviceInDevices(NSArray<AVCaptureDevice *> *devices,
                              const QString &selectedUniqueID) {
    if (selectedUniqueID.isEmpty()) {
        return nil;
    }
    NSString *uniqueID = nsStringFromQString(selectedUniqueID);
    for (AVCaptureDevice *device in devices) {
        if ([device.uniqueID isEqualToString:uniqueID]) {
            return device;
        }
    }
    return nil;
}

static AVCaptureDevice *selectedCameraDevice(VTSController::Impl *impl) {
    const SettingsSnapshot settings = snapshotSettings(impl);
    if (settings.selectedCameraUniqueID.isEmpty()) {
        return nil;
    }
    AVCaptureDevice *device = selectedCameraDeviceInDevices(
        impl->cameraDevices, settings.selectedCameraUniqueID);
    if (device != nil) {
        return device;
    }
    return [AVCaptureDevice
        deviceWithUniqueID:nsStringFromQString(
                               settings.selectedCameraUniqueID)];
}

static int clamp8(int value) { return std::min(std::max(value, 0), 255); }

static QImage imageFromPixelBuffer(CVPixelBufferRef pixelBuffer) {
    if (pixelBuffer == nullptr) {
        return QImage();
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    const OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    QImage image;

    if (format == kCVPixelFormatType_32BGRA) {
        const int width = static_cast<int>(CVPixelBufferGetWidth(pixelBuffer));
        const int height =
            static_cast<int>(CVPixelBufferGetHeight(pixelBuffer));
        const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        const auto *base = static_cast<const uchar *>(
            CVPixelBufferGetBaseAddress(pixelBuffer));
        if (base != nullptr && width > 0 && height > 0) {
            image = QImage(base, width, height, static_cast<int>(bytesPerRow),
                           QImage::Format_ARGB32)
                        .copy();
        }
    } else if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
               format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        const int width =
            static_cast<int>(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0));
        const int height =
            static_cast<int>(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0));
        const auto *yPlane = static_cast<const uchar *>(
            CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0));
        const auto *uvPlane = static_cast<const uchar *>(
            CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1));
        const size_t yStride =
            CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        const size_t uvStride =
            CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        if (yPlane != nullptr && uvPlane != nullptr && width > 0 &&
            height > 0) {
            image = QImage(width, height, QImage::Format_RGB888);
            const bool videoRange =
                format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            for (int row = 0; row < height; ++row) {
                uchar *out = image.scanLine(row);
                const uchar *yRow =
                    yPlane + (static_cast<size_t>(row) * yStride);
                const uchar *uvRow =
                    uvPlane + (static_cast<size_t>(row / 2) * uvStride);
                for (int col = 0; col < width; ++col) {
                    int y = yRow[col];
                    if (videoRange) {
                        y = std::max(0, y - 16) * 255 / 219;
                    }
                    const size_t uvIndex = static_cast<size_t>(col / 2) * 2;
                    const int u = static_cast<int>(uvRow[uvIndex]) - 128;
                    const int v = static_cast<int>(uvRow[uvIndex + 1]) - 128;
                    const int r = clamp8(static_cast<int>(y + (1.402 * v)));
                    const int g = clamp8(
                        static_cast<int>(y - (0.344136 * u) - (0.714136 * v)));
                    const int b = clamp8(static_cast<int>(y + (1.772 * u)));
                    out[(col * 3) + 0] = static_cast<uchar>(r);
                    out[(col * 3) + 1] = static_cast<uchar>(g);
                    out[(col * 3) + 2] = static_cast<uchar>(b);
                }
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return image;
}

static float parameter_value_for_id(NSArray<NSDictionary *> *parameterValues,
                                    NSString *parameterID, bool *outFound) {
    if (outFound != nullptr) {
        *outFound = false;
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
        if (outFound != nullptr) {
            *outFound = true;
        }
        return value.floatValue;
    }
    return 0.0f;
}

static VTSClient *currentVTSClient(VTSController::Impl *impl) {
    std::lock_guard<std::mutex> lock(impl->clientMutex);
    return impl->client;
}

static VTSClient *
ensureVTSClientStartedIfNeeded(VTSController::Impl *impl,
                               const SettingsSnapshot &settings) {
    std::lock_guard<std::mutex> lock(impl->clientMutex);
    if (impl->client == nil) {
        impl->client =
            [[VTSClient alloc] initWithHost:nsStringFromQString(settings.host)
                                           port:(uint16_t)settings.port
                        includeCustomParameters:settings.includeCustomParameters
                            includeARKitAliases:settings.includeARKitAliases
                includeACVABlendshapeParameters:
                    settings.includeACVABlendshapeParameters];
        [impl->client start];
    }
    return impl->client;
}

static void stopVTSClient(VTSController::Impl *impl) {
    VTSClient *client = nil;
    {
        std::lock_guard<std::mutex> lock(impl->clientMutex);
        client = impl->client;
        impl->client = nil;
    }
    [client stop];
}

static QString displayMessageForFaceFound(VTSController::Impl *impl,
                                          bool hasFace) {
    if (impl->calibration.calibrated) {
        return hasFace ? QStringLiteral("Tracking face.")
                       : QStringLiteral("Waiting for face...");
    }
    if (impl->calibration.inProgress) {
        return hasFace ? QStringLiteral("Calibrating neutral pose.")
                       : QStringLiteral("Calibration waiting for face.");
    }
    return hasFace ? QStringLiteral("Press Calibrate to unlock VTS.")
                   : QStringLiteral("Calibration required.");
}

static QString currentExtraStatusLineWithParameterValues(
    VTSController::Impl *impl, const SettingsSnapshot &settings,
    NSArray<NSDictionary *> *parameterValues) {
    const QString targetStatus =
        QStringLiteral("target %1:%2").arg(settings.host).arg(settings.port);
    const QString customStatus = settings.includeCustomParameters
                                     ? QStringLiteral("custom on")
                                     : QStringLiteral("custom off");
    const QString aliasStatus =
        (settings.includeCustomParameters && settings.includeARKitAliases)
            ? QStringLiteral("aliases on")
            : QStringLiteral("aliases off");
    const QString acvaRawStatus = (settings.includeCustomParameters &&
                                   settings.includeACVABlendshapeParameters)
                                      ? QStringLiteral("acva raw on")
                                      : QStringLiteral("acva raw off");
    const QString calibrationStatus =
        qStringFromNSString([impl->calibration statusLine]);
    if (!impl->calibration.calibrated) {
        return QStringLiteral("vts locked  %1  %2  %3  %4  %5")
            .arg(targetStatus, customStatus, aliasStatus, acvaRawStatus,
                 calibrationStatus);
    }

    VTSClient *client = currentVTSClient(impl);
    const QString vtsStatus = client != nil
                                  ? qStringFromNSString([client statusLine])
                                  : QStringLiteral("vts starting");
    QString base = QStringLiteral("%1  %2  %3  %4  %5  %6")
                       .arg(vtsStatus, targetStatus, customStatus, aliasStatus,
                            acvaRawStatus, calibrationStatus);
    if (parameterValues.count == 0) {
        return base;
    }

    bool hasMouth = false;
    const float mouth =
        parameter_value_for_id(parameterValues, @"MouthOpen", &hasMouth);
    bool hasJaw = false;
    const float jaw =
        parameter_value_for_id(parameterValues, @"ACVAJawOpen", &hasJaw);
    bool hasEyeLeft = false;
    bool hasEyeRight = false;
    bool hasYaw = false;
    bool hasPitch = false;
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
    return base +
           QStringLiteral("  mouthVTS %1 jaw %2 eyeL %3 eyeR %4 yaw %5 "
                          "pitch %6")
               .arg(hasMouth ? QString::number(mouth, 'f', 2)
                             : QStringLiteral("-"),
                    hasJaw ? QString::number(jaw, 'f', 2) : QStringLiteral("-"),
                    QString::number(eyeLeft, 'f', 2),
                    QString::number(eyeRight, 'f', 2),
                    QString::number(yaw, 'f', 1),
                    QString::number(pitch, 'f', 1));
}

VTSController::VTSController(QObject *parent)
    : QObject(parent), d(std::make_unique<Impl>()) {
    loadSettings();
    reloadCameraDevices();
    installCameraObservers();
    d->extraStatusLine = currentExtraStatusLineWithParameterValues(
        d.get(), snapshotSettings(d.get()), nil);
}

VTSController::~VTSController() {
    stop();
    removeCameraObservers();
}

QString VTSController::host() const { return snapshotSettings(d.get()).host; }

int VTSController::port() const { return snapshotSettings(d.get()).port; }

QStringList VTSController::cameraNames() const { return d->cameraNames; }

int VTSController::cameraIndex() const { return d->cameraIndex; }

int VTSController::backendMode() const {
    return snapshotSettings(d.get()).backendMode;
}

void VTSController::setBackendMode(int mode) {
    const int backendMode = sanitize_backend_mode(mode);
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->backendMode == backendMode) {
            return;
        }
        d->backendMode = backendMode;
    }
    saveSettings();
    emit backendModeChanged();
    restartTrackingPipeline(true);
}

bool VTSController::enableFilter() const {
    return snapshotSettings(d.get()).enableFilter;
}

void VTSController::setEnableFilter(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->enableFilter == enabled) {
            return;
        }
        d->enableFilter = enabled;
    }
    const SettingsSnapshot settings = snapshotSettings(d.get());
    if (d->pipeline != nil) {
        d->pipeline.useOneEuroFilter = settings.enableFilter;
        d->pipeline.oneEuroParameters = settings.oneEuroParameters;
    }
    saveSettings();
    emit enableFilterChanged();
}

bool VTSController::includeCustomParameters() const {
    return snapshotSettings(d.get()).includeCustomParameters;
}

void VTSController::setIncludeCustomParameters(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->includeCustomParameters == enabled) {
            return;
        }
        d->includeCustomParameters = enabled;
    }
    stopVTSClient();
    saveSettings();
    emit includeCustomParametersChanged();
}

bool VTSController::includeARKitAliases() const {
    return snapshotSettings(d.get()).includeARKitAliases;
}

void VTSController::setIncludeARKitAliases(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->includeARKitAliases == enabled) {
            return;
        }
        d->includeARKitAliases = enabled;
    }
    stopVTSClient();
    saveSettings();
    emit includeARKitAliasesChanged();
}

bool VTSController::includeACVABlendshapeParameters() const {
    return snapshotSettings(d.get()).includeACVABlendshapeParameters;
}

void VTSController::setIncludeACVABlendshapeParameters(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->includeACVABlendshapeParameters == enabled) {
            return;
        }
        d->includeACVABlendshapeParameters = enabled;
    }
    stopVTSClient();
    saveSettings();
    emit includeACVABlendshapeParametersChanged();
}

bool VTSController::mirrorPreview() const {
    return snapshotSettings(d.get()).mirrorPreview;
}

void VTSController::setMirrorPreview(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->mirrorPreview == enabled) {
            return;
        }
        d->mirrorPreview = enabled;
    }
    saveSettings();
    emit mirrorPreviewChanged();
}

bool VTSController::showCameraPreview() const {
    return snapshotSettings(d.get()).showCameraPreview;
}

void VTSController::setShowCameraPreview(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->showCameraPreview == enabled) {
            return;
        }
        d->showCameraPreview = enabled;
    }
    saveSettings();
    emit showCameraPreviewChanged();
}

bool VTSController::flipLandmarkY() const {
    return snapshotSettings(d.get()).flipLandmarkY;
}

void VTSController::setFlipLandmarkY(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->flipLandmarkY == enabled) {
            return;
        }
        d->flipLandmarkY = enabled;
    }
    saveSettings();
    emit flipLandmarkYChanged();
}

bool VTSController::topLeftOrigin() const {
    return snapshotSettings(d.get()).topLeftOrigin;
}

void VTSController::setTopLeftOrigin(bool enabled) {
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->topLeftOrigin == enabled) {
            return;
        }
        d->topLeftOrigin = enabled;
    }
    saveSettings();
    emit topLeftOriginChanged();
}

double VTSController::oneEuroMinCutoff() const {
    return snapshotSettings(d.get()).oneEuroParameters.min_cutoff;
}

void VTSController::setOneEuroMinCutoff(double value) {
    SettingsSnapshot settings = snapshotSettings(d.get());
    applyOneEuroParameters(value, settings.oneEuroParameters.beta,
                           settings.oneEuroParameters.derivative_cutoff);
}

double VTSController::oneEuroBeta() const {
    return snapshotSettings(d.get()).oneEuroParameters.beta;
}

void VTSController::setOneEuroBeta(double value) {
    SettingsSnapshot settings = snapshotSettings(d.get());
    applyOneEuroParameters(settings.oneEuroParameters.min_cutoff, value,
                           settings.oneEuroParameters.derivative_cutoff);
}

double VTSController::oneEuroDerivativeCutoff() const {
    return snapshotSettings(d.get()).oneEuroParameters.derivative_cutoff;
}

void VTSController::setOneEuroDerivativeCutoff(double value) {
    SettingsSnapshot settings = snapshotSettings(d.get());
    applyOneEuroParameters(settings.oneEuroParameters.min_cutoff,
                           settings.oneEuroParameters.beta, value);
}

QString VTSController::message() const { return d->message; }

QString VTSController::extraStatusLine() const { return d->extraStatusLine; }

double VTSController::fps() const { return d->fps; }

int VTSController::detectedFaceCount() const { return d->detectedFaceCount; }

int VTSController::trackedFaceCount() const { return d->trackedFaceCount; }

bool VTSController::hasFace() const { return d->hasFace; }

double VTSController::confidence() const { return d->confidence; }

QString VTSController::calibrationButtonText() const {
    if (d->calibration.inProgress) {
        return QStringLiteral("Calibrating...");
    }
    if (d->calibration.calibrated) {
        return QStringLiteral("Recalibrate");
    }
    return QStringLiteral("Calibrate First");
}

bool VTSController::calibrationBusy() const {
    return d->calibration.inProgress;
}

int VTSController::calibrationSampleCount() const {
    return static_cast<int>(d->calibration.sampleCount);
}

int VTSController::calibrationSampleTarget() const {
    return static_cast<int>(d->calibration.sampleTarget);
}

void VTSController::start() {
    if (d->pipeline != nil) {
        return;
    }
    restartTrackingPipeline(false);
}

void VTSController::stop() {
    stopVTSClient();
    [d->pipeline stop];
    d->pipeline = nil;
}

void VTSController::setPreviewItem(QObject *item) {
    d->previewItem = qobject_cast<VTSPreviewItem *>(item);
}

void VTSController::applyConnection(const QString &host,
                                    const QString &portText) {
    const QString trimmedHost = host.trimmed();
    bool ok = false;
    const int parsedPort = portText.trimmed().toInt(&ok);
    if (trimmedHost.isEmpty() || !ok || parsedPort <= 0 ||
        parsedPort > UINT16_MAX) {
        d->message = QStringLiteral("Invalid VTS connection settings.");
        emit statusChanged();
        return;
    }

    bool hostChanged = false;
    bool portChanged = false;
    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        hostChanged = d->host != trimmedHost;
        portChanged = d->port != parsedPort;
        if (!hostChanged && !portChanged) {
            return;
        }
        d->host = trimmedHost;
        d->port = parsedPort;
    }
    stopVTSClient();
    saveSettings();
    if (hostChanged) {
        emit this->hostChanged();
    }
    if (portChanged) {
        emit this->portChanged();
    }
    d->extraStatusLine = currentExtraStatusLineWithParameterValues(
        d.get(), snapshotSettings(d.get()), nil);
    emit statusChanged();
}

void VTSController::setCameraIndex(int index) {
    QString selectedUniqueID;
    if (index > 0 &&
        static_cast<NSUInteger>(index - 1) < d->cameraDevices.count) {
        AVCaptureDevice *device = d->cameraDevices[index - 1];
        selectedUniqueID = qStringFromNSString(device.uniqueID);
    }

    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (d->selectedCameraUniqueID == selectedUniqueID) {
            return;
        }
        d->selectedCameraUniqueID = selectedUniqueID;
    }
    d->cameraIndex = std::max(0, index);
    saveSettings();
    emit cameraIndexChanged();
    restartTrackingPipeline(true);
}

void VTSController::refreshCameras() { reloadCameraDevices(); }

void VTSController::startCalibration() {
    [d->calibration startCalibration];
    stopVTSClient();
    emit calibrationStateChanged();
    d->message = QStringLiteral("Calibrating neutral pose.");
    d->extraStatusLine = currentExtraStatusLineWithParameterValues(
        d.get(), snapshotSettings(d.get()), nil);
    emit statusChanged();
}

void VTSController::loadSettings() {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *host = [defaults stringForKey:kDefaultsHostKey];
    SettingsSnapshot settings = snapshotSettings(d.get());
    settings.host = host.length != 0 ? qStringFromNSString(host)
                                     : QStringLiteral("127.0.0.1");

    const NSInteger port = [defaults integerForKey:kDefaultsPortKey];
    settings.port = (port > 0 && port <= UINT16_MAX) ? static_cast<int>(port)
                                                     : kDefaultVTSPort;
    settings.backendMode = sanitize_backend_mode(
        default_int(kDefaultsBackendModeKey, kDefaultBackendMode));
    settings.enableFilter = default_bool(kDefaultsEnableFilterKey, YES);
    settings.includeCustomParameters =
        default_bool(kDefaultsIncludeCustomKey, YES);
    settings.includeARKitAliases =
        default_bool(kDefaultsIncludeARKitAliasesKey, YES);
    settings.includeACVABlendshapeParameters =
        default_bool(kDefaultsIncludeACVABlendshapesKey, NO);
    settings.mirrorPreview = default_bool(kDefaultsMirrorPreviewKey, YES);
    settings.showCameraPreview =
        default_bool(kDefaultsShowCameraPreviewKey, YES);
    settings.flipLandmarkY = default_bool(kDefaultsFlipLandmarkYKey, NO);
    settings.topLeftOrigin = default_bool(kDefaultsTopLeftOriginKey, YES);

    NSString *cameraUniqueID =
        [defaults stringForKey:kDefaultsCameraUniqueIDKey];
    settings.selectedCameraUniqueID = cameraUniqueID.length != 0
                                          ? qStringFromNSString(cameraUniqueID)
                                          : QString();

    settings.oneEuroParameters = AppleCVAOneEuroParametersDefault();
    settings.oneEuroParameters.min_cutoff = static_cast<float>(default_double(
        kDefaultsOneEuroMinCutoffKey, settings.oneEuroParameters.min_cutoff));
    settings.oneEuroParameters.beta = static_cast<float>(default_double(
        kDefaultsOneEuroBetaKey, settings.oneEuroParameters.beta));
    settings.oneEuroParameters.derivative_cutoff = static_cast<float>(
        default_double(kDefaultsOneEuroDerivativeCutoffKey,
                       settings.oneEuroParameters.derivative_cutoff));
    settings.oneEuroParameters =
        AppleCVAOneEuroParametersSanitize(settings.oneEuroParameters);

    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        d->host = settings.host;
        d->port = settings.port;
        d->backendMode = settings.backendMode;
        d->enableFilter = settings.enableFilter;
        d->includeCustomParameters = settings.includeCustomParameters;
        d->includeARKitAliases = settings.includeARKitAliases;
        d->includeACVABlendshapeParameters =
            settings.includeACVABlendshapeParameters;
        d->mirrorPreview = settings.mirrorPreview;
        d->showCameraPreview = settings.showCameraPreview;
        d->flipLandmarkY = settings.flipLandmarkY;
        d->topLeftOrigin = settings.topLeftOrigin;
        d->selectedCameraUniqueID = settings.selectedCameraUniqueID;
        d->oneEuroParameters = settings.oneEuroParameters;
    }
}

void VTSController::saveSettings() {
    const SettingsSnapshot settings = snapshotSettings(d.get());
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:nsStringFromQString(settings.host)
                 forKey:kDefaultsHostKey];
    [defaults setInteger:settings.port forKey:kDefaultsPortKey];
    [defaults setInteger:settings.backendMode forKey:kDefaultsBackendModeKey];
    [defaults setBool:settings.enableFilter forKey:kDefaultsEnableFilterKey];
    [defaults setBool:settings.includeCustomParameters
               forKey:kDefaultsIncludeCustomKey];
    [defaults setBool:settings.includeARKitAliases
               forKey:kDefaultsIncludeARKitAliasesKey];
    [defaults setBool:settings.includeACVABlendshapeParameters
               forKey:kDefaultsIncludeACVABlendshapesKey];
    [defaults setBool:settings.mirrorPreview forKey:kDefaultsMirrorPreviewKey];
    [defaults setBool:settings.showCameraPreview
               forKey:kDefaultsShowCameraPreviewKey];
    [defaults setBool:settings.flipLandmarkY forKey:kDefaultsFlipLandmarkYKey];
    [defaults setBool:settings.topLeftOrigin forKey:kDefaultsTopLeftOriginKey];
    if (!settings.selectedCameraUniqueID.isEmpty()) {
        [defaults setObject:nsStringFromQString(settings.selectedCameraUniqueID)
                     forKey:kDefaultsCameraUniqueIDKey];
    } else {
        [defaults removeObjectForKey:kDefaultsCameraUniqueIDKey];
    }
    [defaults setDouble:settings.oneEuroParameters.min_cutoff
                 forKey:kDefaultsOneEuroMinCutoffKey];
    [defaults setDouble:settings.oneEuroParameters.beta
                 forKey:kDefaultsOneEuroBetaKey];
    [defaults setDouble:settings.oneEuroParameters.derivative_cutoff
                 forKey:kDefaultsOneEuroDerivativeCutoffKey];
}

void VTSController::installCameraObservers() {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    QPointer<VTSController> weakSelf(this);
    d->cameraConnectedObserver =
        [center addObserverForName:AVCaptureDeviceWasConnectedNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *notification) {
                          (void)notification;
                          if (weakSelf == nullptr) {
                              return;
                          }
                          weakSelf->refreshCameras();
                          if (!snapshotSettings(weakSelf->d.get())
                                   .selectedCameraUniqueID.isEmpty()) {
                              weakSelf->restartTrackingPipeline(true);
                          }
                        }];
    d->cameraDisconnectedObserver =
        [center addObserverForName:AVCaptureDeviceWasDisconnectedNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *notification) {
                          (void)notification;
                          if (weakSelf == nullptr) {
                              return;
                          }
                          weakSelf->refreshCameras();
                          if (!snapshotSettings(weakSelf->d.get())
                                   .selectedCameraUniqueID.isEmpty()) {
                              weakSelf->restartTrackingPipeline(true);
                          }
                        }];
}

void VTSController::removeCameraObservers() {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (d->cameraConnectedObserver != nil) {
        [center removeObserver:d->cameraConnectedObserver];
        d->cameraConnectedObserver = nil;
    }
    if (d->cameraDisconnectedObserver != nil) {
        [center removeObserver:d->cameraDisconnectedObserver];
        d->cameraDisconnectedObserver = nil;
    }
}

void VTSController::reloadCameraDevices() {
    d->cameraDevices = [available_video_capture_devices() copy];

    QStringList names;
    names << QStringLiteral("System default");
    AVCaptureDevice *defaultDevice =
        [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSString *defaultUniqueID = defaultDevice.uniqueID ?: @"";
    for (AVCaptureDevice *device in d->cameraDevices) {
        names << qStringFromNSString(camera_title(device, defaultUniqueID));
    }

    int newCameraIndex = 0;
    const QString selectedUniqueID =
        snapshotSettings(d.get()).selectedCameraUniqueID;
    if (!selectedUniqueID.isEmpty()) {
        for (NSUInteger i = 0; i < d->cameraDevices.count; ++i) {
            AVCaptureDevice *device = d->cameraDevices[i];
            if (qStringFromNSString(device.uniqueID) == selectedUniqueID) {
                newCameraIndex = static_cast<int>(i + 1);
                break;
            }
        }
    }

    const bool namesChanged = d->cameraNames != names;
    const bool indexChanged = d->cameraIndex != newCameraIndex;
    d->cameraNames = names;
    d->cameraIndex = newCameraIndex;
    if (namesChanged) {
        emit cameraNamesChanged();
    }
    if (indexChanged) {
        emit cameraIndexChanged();
    }
}

void VTSController::restartTrackingPipeline(bool resetCalibration) {
    stopVTSClient();
    [d->pipeline stop];
    d->pipeline = nil;
    if (resetCalibration) {
        d->calibration = [[VTSCalibrationController alloc] init];
        emit calibrationStateChanged();
    }

    const SettingsSnapshot settings = snapshotSettings(d.get());
    AVCaptureDevice *device = selectedCameraDevice(d.get());
    AppleCVATrackingPipeline *pipeline = [[AppleCVATrackingPipeline alloc]
        initWithBackendMode:static_cast<AppleCVABackendMode>(
                                settings.backendMode)
              captureDevice:device
          captureQueueLabel:@"local.applecva.vts-source.capture"];
    pipeline.useOneEuroFilter = settings.enableFilter;
    pipeline.oneEuroParameters = settings.oneEuroParameters;

    QPointer<VTSController> weakSelf(this);
    pipeline.statusHandler = ^(NSString *statusMessage, int32_t status) {
      if (weakSelf == nullptr) {
          return;
      }
      const QString message = qStringFromNSString(statusMessage);
      QMetaObject::invokeMethod(
          weakSelf.data(),
          [weakSelf, message, status]() {
              if (weakSelf != nullptr) {
                  weakSelf->handlePipelineStatus(message, status);
              }
          },
          Qt::QueuedConnection);
    };

    pipeline.frameHandler = ^(CVPixelBufferRef pixelBuffer,
                              const AppleCVATrackedFace *face, BOOL hasFace,
                              size_t detectedFaceCount, size_t trackedFaceCount,
                              int32_t status, double timestamp, double fps) {
      (void)timestamp;
      if (weakSelf == nullptr) {
          return;
      }
      VTSController *controller = weakSelf.data();
      VTSController::Impl *impl = controller->d.get();
      const SettingsSnapshot frameSettings = snapshotSettings(impl);

      const BOOL calibrationCompleted =
          [impl->calibration collectSampleFromFace:face hasFace:hasFace];

      VTSClient *client = nil;
      NSArray<NSDictionary *> *parameterValues = nil;
      VTSAppleCVACalibration calibrationSnapshot =
          impl->calibration.calibration;
      const BOOL calibrated = impl->calibration.calibrated;
      if (calibrated) {
          client = ensureVTSClientStartedIfNeeded(impl, frameSettings);
          NSSet<NSString *> *defaultParameterNames =
              [client defaultParameterNamesSnapshot];
          parameterValues = VTSAppleCVAParameterValues(
              face, hasFace, defaultParameterNames, &calibrationSnapshot,
              frameSettings.includeCustomParameters,
              frameSettings.includeARKitAliases,
              frameSettings.includeACVABlendshapeParameters);
          [client injectParameterValues:parameterValues faceFound:hasFace];
      }

      const QString displayMessage = displayMessageForFaceFound(impl, hasFace);
      const QString extraStatusLine = currentExtraStatusLineWithParameterValues(
          impl, frameSettings, parameterValues);
      AppleCVATrackedFace faceSnapshot = {};
      if (face != nullptr) {
          faceSnapshot = *face;
      }
      const QImage image = imageFromPixelBuffer(pixelBuffer);
      const double confidence =
          hasFace ? static_cast<double>(faceSnapshot.confidence) : 0.0;

      QMetaObject::invokeMethod(
          controller,
          [weakSelf, image, faceSnapshot, hasFace, detectedFaceCount,
           trackedFaceCount, status, fps, confidence, displayMessage,
           extraStatusLine, calibrationCompleted]() {
              if (weakSelf == nullptr) {
                  return;
              }
              VTSController *controller = weakSelf.data();
              controller->d->message = displayMessage;
              controller->d->extraStatusLine = extraStatusLine;
              controller->d->fps = fps;
              controller->d->detectedFaceCount =
                  static_cast<int>(detectedFaceCount);
              controller->d->trackedFaceCount =
                  static_cast<int>(trackedFaceCount);
              controller->d->hasFace = hasFace;
              controller->d->confidence = confidence;
              controller->d->lastStatus = status;
              if (controller->d->previewItem != nullptr) {
                  controller->d->previewItem->setFrame(
                      image, hasFace ? &faceSnapshot : nullptr, hasFace,
                      detectedFaceCount, trackedFaceCount, status, fps);
              }
              emit controller->statusChanged();
              emit controller->trackingStatsChanged();
              if (calibrationCompleted ||
                  controller->d->calibration.inProgress) {
                  emit controller->calibrationStateChanged();
              }
          },
          Qt::QueuedConnection);
    };

    d->pipeline = pipeline;
    d->message = QStringLiteral("Starting camera...");
    d->extraStatusLine =
        currentExtraStatusLineWithParameterValues(d.get(), settings, nil);
    emit statusChanged();
    [d->pipeline start];
}

void VTSController::applyOneEuroParameters(double minCutoff, double beta,
                                           double derivativeCutoff) {
    AppleCVAOneEuroParameters parameters;
    parameters.min_cutoff = static_cast<float>(clamp_double(
        minCutoff, kOneEuroMinCutoffMinimum, kOneEuroMinCutoffMaximum));
    parameters.beta = static_cast<float>(
        clamp_double(beta, kOneEuroBetaMinimum, kOneEuroBetaMaximum));
    parameters.derivative_cutoff = static_cast<float>(
        clamp_double(derivativeCutoff, kOneEuroDerivativeCutoffMinimum,
                     kOneEuroDerivativeCutoffMaximum));
    parameters = AppleCVAOneEuroParametersSanitize(parameters);

    {
        std::lock_guard<std::mutex> lock(d->settingsMutex);
        if (std::memcmp(&d->oneEuroParameters, &parameters,
                        sizeof(parameters)) == 0) {
            return;
        }
        d->oneEuroParameters = parameters;
    }
    const SettingsSnapshot settings = snapshotSettings(d.get());
    if (d->pipeline != nil) {
        d->pipeline.oneEuroParameters = settings.oneEuroParameters;
    }
    saveSettings();
    emit oneEuroParametersChanged();
}

void VTSController::stopVTSClient() { ::stopVTSClient(d.get()); }

void VTSController::handlePipelineStatus(const QString &message, int status) {
    d->message = message;
    d->lastStatus = status;
    d->fps = 0.0;
    d->detectedFaceCount = 0;
    d->trackedFaceCount = 0;
    d->hasFace = false;
    d->confidence = 0.0;
    d->extraStatusLine = currentExtraStatusLineWithParameterValues(
        d.get(), snapshotSettings(d.get()), nil);
    if (d->previewItem != nullptr) {
        d->previewItem->setFrame(QImage(), nullptr, false, 0, 0, status, 0.0);
    }
    emit statusChanged();
    emit trackingStatsChanged();
}
