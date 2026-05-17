#import "applecva.h"

#import <Foundation/Foundation.h>
#import <Vision/Vision.h>

#include <CoreGraphics/CoreGraphics.h>
#include <CoreMedia/CoreMedia.h>
#include <dlfcn.h>
#include <math.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#define APPLECVA_FRAMEWORK_PATH                                                \
    "/System/Library/PrivateFrameworks/AppleCVA.framework/Versions/A/AppleCVA"

#define APPLECVA_ARRAY_COUNT(array) (sizeof(array) / sizeof((array)[0]))
#define APPLECVA_LITE_STACK_FACE_CAPACITY 8
#define APPLECVA_FULL_MAX_INPUT_FACES 8
#define APPLECVA_FULL_CALLBACK_TIMEOUT_NS NSEC_PER_SEC
#define APPLECVA_FULL_FACE_DEFAULT_SMOOTHING 0.25f
#define APPLECVA_FULL_FACE_DEFAULT_HOLD_FRAMES 15
#define APPLECVA_FULL_FACE_MATCH_DISTANCE2 0.08f

static const float kAppleCVAFaceTrackingIntrinsicsWidth = 1440.0f;
static const float kAppleCVAFaceTrackingIntrinsicsHeight = 1080.0f;
static const float kAppleCVAFaceTrackingIntrinsicsFx = 970.1375f;
static const float kAppleCVAFaceTrackingIntrinsicsFy = 970.1375f;
static const float kAppleCVAFaceTrackingIntrinsicsCx = 715.9445f;
static const float kAppleCVAFaceTrackingIntrinsicsCy = 538.6998f;

typedef const struct __CVAFaceTrackingLite *CVAFaceTrackingLiteRef;
typedef const struct __CVAFaceTracking *CVAFaceTrackingRef;

typedef struct {
    uint8_t bytes[24];
} CVAFaceTrackingLiteCreateOptions;

typedef struct {
    float values[21];
} CVAFaceTrackingLiteCameraParams;

typedef struct {
    float x;
    float y;
    float width;
    float height;
    float roll;
} CVAFaceTrackingLiteDetectedFace;

typedef uint32_t (*CVAFaceTrackingLiteGetAPIVersionFn)(void);
typedef CFTypeID (*CVAFaceTrackingLiteGetTypeIDFn)(void);
typedef CVAFaceTrackingLiteCreateOptions (
    *CVAFaceTrackingLiteGetDefaultCreateOptionsFn)(void);
typedef CVAFaceTrackingLiteCreateOptions (
    *CVAFaceTrackingLiteGetCreateOptionsForFeaturesFn)(bool, bool);
typedef int32_t (*CVAFaceTrackingLiteCreateFn)(
    CFAllocatorRef, const CVAFaceTrackingLiteCreateOptions *,
    CVAFaceTrackingLiteRef *);
typedef int32_t (*CVAFaceTrackingLiteSetTimestampFn)(CVAFaceTrackingLiteRef,
                                                     double);
typedef int32_t (*CVAFaceTrackingLiteSetLuxLevelFn)(CVAFaceTrackingLiteRef,
                                                    uint32_t);
typedef int32_t (*CVAFaceTrackingLiteSetColorImageFn)(
    CVAFaceTrackingLiteRef, CVPixelBufferRef,
    const CVAFaceTrackingLiteCameraParams *);
typedef int32_t (*CVAFaceTrackingLiteSetDetectedFacesFn)(
    CVAFaceTrackingLiteRef, uint32_t, const CVAFaceTrackingLiteDetectedFace *);
typedef int32_t (*CVAFaceTrackingLiteProcessFn)(CVAFaceTrackingLiteRef);
typedef const void *(*CVAFaceTrackingLiteGetOutputFn)(CVAFaceTrackingLiteRef);
typedef int32_t (*CVAFaceTrackingLiteCopyDecodedOutputFn)(const void *,
                                                          CFDictionaryRef *,
                                                          Boolean *);
typedef int32_t (*CVAFaceTrackingCopySemanticsFn)(CFDictionaryRef,
                                                  CFDictionaryRef *);
typedef uint32_t (*CVAFaceTrackingMaximumNumberOfTrackedFacesFn)(void);
typedef uint32_t (*CVAFaceTrackingGetAPIVersionFn)(void);
typedef int32_t (*CVAFaceTrackingCreateFn)(CFAllocatorRef, CFDictionaryRef,
                                           CVAFaceTrackingRef *);
typedef int32_t (*CVAFaceTrackingProcessFn)(CVAFaceTrackingRef,
                                            CFDictionaryRef);

typedef struct {
    void *handle;
    CVAFaceTrackingLiteGetAPIVersionFn get_api_version;
    CVAFaceTrackingLiteGetTypeIDFn get_type_id;
    CVAFaceTrackingLiteGetDefaultCreateOptionsFn get_default_create_options;
    CVAFaceTrackingLiteGetCreateOptionsForFeaturesFn
        get_create_options_for_features;
    CVAFaceTrackingLiteCreateFn create;
    CVAFaceTrackingLiteSetTimestampFn set_timestamp;
    CVAFaceTrackingLiteSetLuxLevelFn set_lux_level;
    CVAFaceTrackingLiteSetColorImageFn set_color_image;
    CVAFaceTrackingLiteSetDetectedFacesFn set_detected_faces;
    CVAFaceTrackingLiteProcessFn process;
    CVAFaceTrackingLiteGetOutputFn get_output;
    CVAFaceTrackingLiteCopyDecodedOutputFn copy_decoded_output;
    CVAFaceTrackingCopySemanticsFn copy_semantics;
    CVAFaceTrackingMaximumNumberOfTrackedFacesFn
        maximum_number_of_tracked_faces;
} AppleCVALiteAPI;

typedef struct {
    CFStringRef add_keypoints;
    CFStringRef add_mesh;
    CFStringRef callback;
    CFStringRef color;
    CFStringRef color_meta_data;
    CFStringRef color_only;
    CFStringRef camera_color;
    CFStringRef detected_face_angle_pitch;
    CFStringRef detected_face_angle_roll;
    CFStringRef detected_face_angle_yaw;
    CFStringRef detected_face_face_id;
    CFStringRef detected_face_rect;
    CFStringRef detected_faces_array;
    CFStringRef extrinsics;
    CFStringRef failure_fov_modifier;
    CFStringRef fitting_enabled;
    CFStringRef force_cpu;
    CFStringRef intrinsics;
    CFStringRef lux_level;
    CFStringRef meta;
    CFStringRef meta_version;
    CFStringRef network_failure_threshold_multiplier;
    CFStringRef num_tracked_faces;
    CFStringRef robust_tongue;
    CFStringRef rgb_only;
    CFStringRef rotation;
    CFStringRef timestamp;
    CFStringRef translation;
    CFStringRef use_face_detector;
    CFStringRef use_tongue;
} AppleCVAFullKeys;

typedef struct {
    void *handle;
    CVAFaceTrackingGetAPIVersionFn get_api_version;
    CVAFaceTrackingCreateFn create;
    CVAFaceTrackingProcessFn process;
    AppleCVAFullKeys keys;
} AppleCVAFullAPI;

typedef struct {
    const char *name;
    void **slot;
} AppleCVASymbolSpec;

typedef struct {
    const char *name;
    CFStringRef *slot;
    bool required;
} AppleCVAKeySpec;

struct AppleCVATracker {
    AppleCVALiteAPI api;
    AppleCVAFullAPI full_api;
    AppleCVAConfig config;
    CVAFaceTrackingLiteRef tracker;
    CVAFaceTrackingRef full_tracker;
    CFDictionaryRef full_last_output;
    AppleCVADetectedFace full_input_faces[APPLECVA_FULL_MAX_INPUT_FACES];
    size_t full_input_face_count;
    size_t full_missing_detection_frames;
    CVPixelBufferRef scratch_buffer;
    size_t scratch_width;
    size_t scratch_height;
    OSType scratch_format;
};

static CFStringRef key_from_symbol(void *handle, const char *name) {
    CFStringRef *slot = (CFStringRef *)dlsym(handle, name);
    if (slot != NULL && *slot != NULL &&
        CFGetTypeID(*slot) == CFStringGetTypeID()) {
        return *slot;
    }
    return NULL;
}

static NSString *ns_key(CFStringRef key) { return (__bridge NSString *)key; }

static NSString *ns_key_or_literal(CFStringRef key, CFStringRef literal) {
    return (__bridge NSString *)(key != NULL ? key : literal);
}

static void *open_applecva_framework(void) {
    return dlopen(APPLECVA_FRAMEWORK_PATH, RTLD_NOW);
}

static void close_framework_handle(void **handle) {
    if (handle != NULL && *handle != NULL) {
        dlclose(*handle);
        *handle = NULL;
    }
}

static bool bind_symbols(void *handle, const AppleCVASymbolSpec *symbols,
                         size_t symbol_count) {
    for (size_t i = 0; i < symbol_count; ++i) {
        *symbols[i].slot = dlsym(handle, symbols[i].name);
        if (*symbols[i].slot == NULL) {
            return false;
        }
    }
    return true;
}

static bool bind_cfstring_keys(void *handle, const AppleCVAKeySpec *keys,
                               size_t key_count) {
    bool ok = true;
    for (size_t i = 0; i < key_count; ++i) {
        *keys[i].slot = key_from_symbol(handle, keys[i].name);
        if (keys[i].required && *keys[i].slot == NULL) {
            ok = false;
        }
    }
    return ok;
}

static bool trace_enabled(void) {
    static int cached = -1;
    if (cached == -1) {
        cached = (getenv("APPLECVA_TRACE") != NULL) ? 1 : 0;
    }
    return cached == 1;
}

static void trace_log(const char *format, ...) {
    if (!trace_enabled()) {
        return;
    }
    va_list args;
    va_start(args, format);
    fprintf(stderr, "[applecva] ");
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    va_end(args);
}

static bool load_api(AppleCVALiteAPI *api) {
    memset(api, 0, sizeof(*api));
    api->handle = open_applecva_framework();
    if (api->handle == NULL) {
        return false;
    }

#define APPLECVA_LITE_SYMBOL(field, symbol_name)                               \
    {                                                                          \
        symbol_name, (void **)&api->field                                      \
    }

    const AppleCVASymbolSpec symbols[] = {
        APPLECVA_LITE_SYMBOL(get_api_version,
                             "CVAFaceTrackingLiteGetAPIVersion"),
        APPLECVA_LITE_SYMBOL(get_type_id, "CVAFaceTrackingLiteGetTypeID"),
        APPLECVA_LITE_SYMBOL(get_default_create_options,
                             "CVAFaceTrackingLiteGetDefaultCreateOptions"),
        APPLECVA_LITE_SYMBOL(get_create_options_for_features,
                             "CVAFaceTrackingLiteGetCreateOptionsForFeatures"),
        APPLECVA_LITE_SYMBOL(create, "CVAFaceTrackingLiteCreate"),
        APPLECVA_LITE_SYMBOL(set_timestamp, "CVAFaceTrackingLiteSetTimestamp"),
        APPLECVA_LITE_SYMBOL(set_lux_level, "CVAFaceTrackingLiteSetLuxLevel"),
        APPLECVA_LITE_SYMBOL(set_color_image,
                             "CVAFaceTrackingLiteSetColorImage"),
        APPLECVA_LITE_SYMBOL(set_detected_faces,
                             "CVAFaceTrackingLiteSetDetectedFaces"),
        APPLECVA_LITE_SYMBOL(process, "CVAFaceTrackingLiteProcess"),
        APPLECVA_LITE_SYMBOL(get_output, "CVAFaceTrackingLiteGetOutput"),
        APPLECVA_LITE_SYMBOL(copy_decoded_output,
                             "CVAFaceTrackingLiteCopyDecodedOutput"),
        APPLECVA_LITE_SYMBOL(copy_semantics, "CVAFaceTrackingCopySemantics"),
        APPLECVA_LITE_SYMBOL(maximum_number_of_tracked_faces,
                             "CVAFaceTrackingMaximumNumberOfTrackedFaces"),
    };
#undef APPLECVA_LITE_SYMBOL

    if (!bind_symbols(api->handle, symbols, APPLECVA_ARRAY_COUNT(symbols))) {
        close_framework_handle(&api->handle);
        memset(api, 0, sizeof(*api));
        return false;
    }
    return true;
}

static void unload_api(AppleCVALiteAPI *api) {
    close_framework_handle(&api->handle);
    memset(api, 0, sizeof(*api));
}

static bool load_full_keys(AppleCVAFullAPI *api) {
    AppleCVAFullKeys *keys = &api->keys;
    memset(keys, 0, sizeof(*keys));

#define APPLECVA_REQUIRED_FULL_KEY(field, symbol_name)                         \
    {symbol_name, &keys->field, true}
#define APPLECVA_OPTIONAL_FULL_KEY(field, symbol_name)                         \
    {                                                                          \
        symbol_name, &keys->field, false                                       \
    }

    const AppleCVAKeySpec key_specs[] = {
        APPLECVA_REQUIRED_FULL_KEY(add_keypoints,
                                   "kCVAFaceTracking_AddKeyPoints"),
        APPLECVA_REQUIRED_FULL_KEY(add_mesh, "kCVAFaceTracking_AddMesh"),
        APPLECVA_REQUIRED_FULL_KEY(callback, "kCVAFaceTracking_Callback"),
        APPLECVA_REQUIRED_FULL_KEY(color, "kCVAFaceTracking_Color"),
        APPLECVA_REQUIRED_FULL_KEY(color_meta_data,
                                   "kCVAFaceTracking_ColorMetaData"),
        APPLECVA_REQUIRED_FULL_KEY(color_only, "kCVAFaceTracking_ColorOnly"),
        APPLECVA_REQUIRED_FULL_KEY(camera_color,
                                   "kCVAFaceTracking_CameraColor"),
        APPLECVA_OPTIONAL_FULL_KEY(
            detected_face_angle_pitch,
            "kCVAFaceTracking_DetectedFaceAngleInfoPitch"),
        APPLECVA_REQUIRED_FULL_KEY(
            detected_face_angle_roll,
            "kCVAFaceTracking_DetectedFaceAngleInfoRoll"),
        APPLECVA_OPTIONAL_FULL_KEY(detected_face_angle_yaw,
                                   "kCVAFaceTracking_DetectedFaceAngleInfoYaw"),
        APPLECVA_REQUIRED_FULL_KEY(detected_face_face_id,
                                   "kCVAFaceTracking_DetectedFaceFaceID"),
        APPLECVA_REQUIRED_FULL_KEY(detected_face_rect,
                                   "kCVAFaceTracking_DetectedFaceRect"),
        APPLECVA_REQUIRED_FULL_KEY(detected_faces_array,
                                   "kCVAFaceTracking_DetectedFacesArray"),
        APPLECVA_REQUIRED_FULL_KEY(extrinsics, "kCVAFaceTracking_Extrinsics"),
        APPLECVA_OPTIONAL_FULL_KEY(failure_fov_modifier,
                                   "kCVAFaceTracking_FailureFOVModifier"),
        APPLECVA_REQUIRED_FULL_KEY(fitting_enabled,
                                   "kCVAFaceTracking_FittingEnabled"),
        APPLECVA_REQUIRED_FULL_KEY(force_cpu, "kCVAFaceTracking_ForceCPU"),
        APPLECVA_REQUIRED_FULL_KEY(intrinsics, "kCVAFaceTracking_Intrinsics"),
        APPLECVA_REQUIRED_FULL_KEY(lux_level, "kCVAFaceTracking_LuxLevel"),
        APPLECVA_REQUIRED_FULL_KEY(meta, "kCVAFaceTracking_Meta"),
        APPLECVA_REQUIRED_FULL_KEY(meta_version,
                                   "kCVAFaceTracking_MetaVersion"),
        APPLECVA_REQUIRED_FULL_KEY(
            network_failure_threshold_multiplier,
            "kCVAFaceTracking_NetworkFailureThresholdMultiplier"),
        APPLECVA_REQUIRED_FULL_KEY(num_tracked_faces,
                                   "kCVAFaceTracking_NumTrackedFaces"),
        APPLECVA_REQUIRED_FULL_KEY(rotation, "kCVAFaceTracking_Rotation"),
        APPLECVA_REQUIRED_FULL_KEY(timestamp, "kCVAFaceTracking_Timestamp"),
        APPLECVA_REQUIRED_FULL_KEY(translation, "kCVAFaceTracking_Translation"),
        APPLECVA_REQUIRED_FULL_KEY(use_face_detector,
                                   "kCVAFaceTracking_UseFaceDetector"),
        APPLECVA_OPTIONAL_FULL_KEY(robust_tongue,
                                   "kCVAFaceTracking_RobustTongue"),
        APPLECVA_OPTIONAL_FULL_KEY(rgb_only, "kCVAFaceTracking_RGBOnly"),
        APPLECVA_OPTIONAL_FULL_KEY(use_tongue, "kCVAFaceTracking_UseTongue"),
    };
#undef APPLECVA_OPTIONAL_FULL_KEY
#undef APPLECVA_REQUIRED_FULL_KEY

    return bind_cfstring_keys(api->handle, key_specs,
                              APPLECVA_ARRAY_COUNT(key_specs));
}

static bool load_full_api(AppleCVAFullAPI *api) {
    memset(api, 0, sizeof(*api));
    api->handle = open_applecva_framework();
    if (api->handle == NULL) {
        return false;
    }

#define APPLECVA_FULL_SYMBOL(field, symbol_name)                               \
    {                                                                          \
        symbol_name, (void **)&api->field                                      \
    }

    const AppleCVASymbolSpec symbols[] = {
        APPLECVA_FULL_SYMBOL(get_api_version, "CVAFaceTrackingGetAPIVersion"),
        APPLECVA_FULL_SYMBOL(create, "CVAFaceTrackingCreate"),
        APPLECVA_FULL_SYMBOL(process, "CVAFaceTrackingProcess"),
    };
#undef APPLECVA_FULL_SYMBOL

    if (!bind_symbols(api->handle, symbols, APPLECVA_ARRAY_COUNT(symbols)) ||
        !load_full_keys(api)) {
        close_framework_handle(&api->handle);
        memset(api, 0, sizeof(*api));
        return false;
    }
    return true;
}

static void unload_full_api(AppleCVAFullAPI *api) {
    close_framework_handle(&api->handle);
    memset(api, 0, sizeof(*api));
}

static uint8_t clamp_u8(float value) {
    if (value < 0.0f) {
        return 0;
    }
    if (value > 255.0f) {
        return 255;
    }
    return (uint8_t)(value + 0.5f);
}

typedef struct {
    float r;
    float g;
    float b;
} AppleCVARGB;

typedef struct {
    CVPixelBufferRef buffer;
    CVPixelBufferLockFlags flags;
    bool locked;
} AppleCVAPixelBufferLock;

static bool pixel_buffer_lock(AppleCVAPixelBufferLock *lock,
                              CVPixelBufferRef buffer,
                              CVPixelBufferLockFlags flags) {
    lock->buffer = buffer;
    lock->flags = flags;
    lock->locked =
        (CVPixelBufferLockBaseAddress(buffer, flags) == kCVReturnSuccess);
    return lock->locked;
}

static void pixel_buffer_unlock(AppleCVAPixelBufferLock *lock) {
    if (lock->locked) {
        CVPixelBufferUnlockBaseAddress(lock->buffer, lock->flags);
        lock->locked = false;
    }
}

static AppleCVARGB make_rgb(float r, float g, float b) {
    AppleCVARGB rgb = {r, g, b};
    return rgb;
}

static AppleCVARGB rgb_from_packed_pixel(const uint8_t *pixel, OSType format) {
    switch (format) {
    case kCVPixelFormatType_32BGRA:
        return make_rgb((float)pixel[2], (float)pixel[1], (float)pixel[0]);
    case kCVPixelFormatType_32ARGB:
        return make_rgb((float)pixel[1], (float)pixel[2], (float)pixel[3]);
    case kCVPixelFormatType_32RGBA:
        return make_rgb((float)pixel[0], (float)pixel[1], (float)pixel[2]);
    default:
        return make_rgb(0.0f, 0.0f, 0.0f);
    }
}

static AppleCVARGB average_rgb4(AppleCVARGB a, AppleCVARGB b, AppleCVARGB c,
                                AppleCVARGB d) {
    return make_rgb((a.r + b.r + c.r + d.r) * 0.25f,
                    (a.g + b.g + c.g + d.g) * 0.25f,
                    (a.b + b.b + c.b + d.b) * 0.25f);
}

static float rgb_to_luma(AppleCVARGB rgb, bool full_range) {
    if (full_range) {
        return (0.2990f * rgb.r) + (0.5870f * rgb.g) + (0.1140f * rgb.b);
    }
    return 16.0f +
           ((65.481f * rgb.r) + (128.553f * rgb.g) + (24.966f * rgb.b)) /
               255.0f;
}

static void rgb_to_chroma(AppleCVARGB rgb, bool full_range, float *out_cb,
                          float *out_cr) {
    if (full_range) {
        *out_cb = (-0.168736f * rgb.r) - (0.331264f * rgb.g) +
                  (0.500000f * rgb.b) + 128.0f;
        *out_cr = (0.500000f * rgb.r) - (0.418688f * rgb.g) -
                  (0.081312f * rgb.b) + 128.0f;
        return;
    }
    *out_cb =
        128.0f +
        ((-37.797f * rgb.r) - (74.203f * rgb.g) + (112.000f * rgb.b)) / 255.0f;
    *out_cr =
        128.0f +
        ((112.000f * rgb.r) - (93.786f * rgb.g) - (18.214f * rgb.b)) / 255.0f;
}

void AppleCVAConfigInit(AppleCVAConfig *config) {
    if (config == NULL) {
        return;
    }
    memset(config, 0, sizeof(*config));
    config->use_feature_options = false;
    config->enable_rgb_fallback_conversion = true;
    config->prefer_full_range_nv12 = true;
    config->focal_scale = 1.0f;
    config->default_lux_level = 150;
    config->use_full_api = false;
}

void AppleCVAMakeDefaultCameraParameters(size_t width, size_t height,
                                         float focal_scale,
                                         AppleCVACameraParameters *params) {
    if (params == NULL) {
        return;
    }
    memset(params, 0, sizeof(*params));
    params->rotation[0] = 1.0f;
    params->rotation[4] = 1.0f;
    params->rotation[8] = 1.0f;
    const float width_scale =
        (float)width / kAppleCVAFaceTrackingIntrinsicsWidth;
    const float height_scale =
        (float)height / kAppleCVAFaceTrackingIntrinsicsHeight;
    params->intrinsics[0] =
        kAppleCVAFaceTrackingIntrinsicsFx * width_scale * focal_scale;
    params->intrinsics[4] =
        kAppleCVAFaceTrackingIntrinsicsFy * height_scale * focal_scale;
    params->intrinsics[2] = kAppleCVAFaceTrackingIntrinsicsCx * width_scale;
    params->intrinsics[5] = kAppleCVAFaceTrackingIntrinsicsCy * height_scale;
    params->intrinsics[8] = 1.0f;
}

void AppleCVAFrameResultInit(AppleCVAFrameResult *result,
                             AppleCVATrackedFace *tracked_faces,
                             size_t tracked_face_capacity) {
    if (result == NULL) {
        return;
    }
    memset(result, 0, sizeof(*result));
    result->tracked_faces = tracked_faces;
    result->tracked_face_capacity = tracked_face_capacity;
}

void AppleCVAFrameResultClear(AppleCVAFrameResult *result) {
    if (result == NULL) {
        return;
    }
    const size_t tracked_face_capacity = result->tracked_face_capacity;
    AppleCVATrackedFace *tracked_faces = result->tracked_faces;
    memset(result, 0, sizeof(*result));
    result->tracked_faces = tracked_faces;
    result->tracked_face_capacity = tracked_face_capacity;
    if (tracked_faces != NULL && tracked_face_capacity != 0) {
        memset(tracked_faces, 0,
               tracked_face_capacity * sizeof(*tracked_faces));
    }
}

void AppleCVASemanticsInit(AppleCVASemantics *semantics) {
    if (semantics == NULL) {
        return;
    }
    memset(semantics, 0, sizeof(*semantics));
}

const char *AppleCVAStatusString(int32_t status) {
    switch (status) {
    case APPLECVA_OK:
        return "ok";
    case APPLECVA_ERR_INVALID_ARGUMENT:
        return "invalid argument";
    case APPLECVA_ERR_SYMBOL_BIND:
        return "symbol bind failed";
    case APPLECVA_ERR_CREATE_TRACKER:
        return "tracker creation failed";
    case APPLECVA_ERR_UNSUPPORTED_PIXEL_FORMAT:
        return "unsupported pixel format";
    case APPLECVA_ERR_CONVERSION_FAILED:
        return "pixel format conversion failed";
    case APPLECVA_ERR_DECODE_FAILED:
        return "decoded output unavailable";
    case APPLECVA_ERR_VISION_FAILED:
        return "vision face detection failed";
    case APPLECVA_ERR_BUFFER_TOO_SMALL:
        return "caller-provided buffer too small";
    case APPLECVA_ERR_SEMANTICS_FAILED:
        return "semantics unavailable";
    default:
        return (status < 0) ? "applecva runtime error" : "unknown error";
    }
}

static void
make_internal_camera_params(const AppleCVACameraParameters *source,
                            CVAFaceTrackingLiteCameraParams *destination) {
    memset(destination, 0, sizeof(*destination));
    memcpy(&destination->values[0], source->rotation, sizeof(float) * 9);
    memcpy(&destination->values[9], source->translation, sizeof(float) * 3);
    memcpy(&destination->values[12], source->intrinsics, sizeof(float) * 9);
}

static OSType preferred_nv12_format(const AppleCVAConfig *config) {
    return config->prefer_full_range_nv12
               ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
               : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
}

static void tracker_release_scratch_buffer(AppleCVATracker *tracker) {
    if (tracker->scratch_buffer != NULL) {
        CVPixelBufferRelease(tracker->scratch_buffer);
        tracker->scratch_buffer = NULL;
        tracker->scratch_width = 0;
        tracker->scratch_height = 0;
        tracker->scratch_format = 0;
    }
}

static bool ensure_scratch_buffer(AppleCVATracker *tracker, size_t width,
                                  size_t height) {
    const OSType format = preferred_nv12_format(&tracker->config);
    if (tracker->scratch_buffer != NULL && tracker->scratch_width == width &&
        tracker->scratch_height == height &&
        tracker->scratch_format == format) {
        return true;
    }

    tracker_release_scratch_buffer(tracker);

    NSDictionary *attrs =
        @{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVReturn cv = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                      format, (__bridge CFDictionaryRef)attrs,
                                      &tracker->scratch_buffer);
    if (cv != kCVReturnSuccess || tracker->scratch_buffer == NULL) {
        tracker->scratch_buffer = NULL;
        return false;
    }

    tracker->scratch_width = width;
    tracker->scratch_height = height;
    tracker->scratch_format = format;
    return true;
}

static bool convert_packed_to_nv12(AppleCVATracker *tracker,
                                   CVPixelBufferRef source_buffer,
                                   CVPixelBufferRef destination_buffer) {
    const OSType source_format = CVPixelBufferGetPixelFormatType(source_buffer);
    AppleCVAPixelBufferLock source_lock = {0};
    AppleCVAPixelBufferLock destination_lock = {0};
    if (!pixel_buffer_lock(&source_lock, source_buffer,
                           kCVPixelBufferLock_ReadOnly)) {
        return false;
    }
    if (!pixel_buffer_lock(&destination_lock, destination_buffer, 0)) {
        pixel_buffer_unlock(&source_lock);
        return false;
    }

    const size_t width = CVPixelBufferGetWidth(source_buffer);
    const size_t height = CVPixelBufferGetHeight(source_buffer);
    const uint8_t *src_base = CVPixelBufferGetBaseAddress(source_buffer);
    const size_t src_stride = CVPixelBufferGetBytesPerRow(source_buffer);
    uint8_t *y_plane =
        CVPixelBufferGetBaseAddressOfPlane(destination_buffer, 0);
    uint8_t *uv_plane =
        CVPixelBufferGetBaseAddressOfPlane(destination_buffer, 1);
    const size_t y_stride =
        CVPixelBufferGetBytesPerRowOfPlane(destination_buffer, 0);
    const size_t uv_stride =
        CVPixelBufferGetBytesPerRowOfPlane(destination_buffer, 1);
    const bool full_range = (preferred_nv12_format(&tracker->config) ==
                             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);

    for (size_t y = 0; y < height; ++y) {
        const uint8_t *src_row = src_base + (y * src_stride);
        uint8_t *dst_y = y_plane + (y * y_stride);
        for (size_t x = 0; x < width; ++x) {
            const AppleCVARGB rgb =
                rgb_from_packed_pixel(src_row + (x * 4), source_format);
            dst_y[x] = clamp_u8(rgb_to_luma(rgb, full_range));
        }
    }

    for (size_t y = 0; y < height; y += 2) {
        const size_t next_y = (y + 1 < height) ? (y + 1) : y;
        const uint8_t *src_row0 = src_base + (y * src_stride);
        const uint8_t *src_row1 = src_base + (next_y * src_stride);
        uint8_t *dst_uv = uv_plane + ((y / 2) * uv_stride);
        for (size_t x = 0; x < width; x += 2) {
            const size_t next_x = (x + 1 < width) ? (x + 1) : x;
            const AppleCVARGB rgb = average_rgb4(
                rgb_from_packed_pixel(src_row0 + (x * 4), source_format),
                rgb_from_packed_pixel(src_row0 + (next_x * 4), source_format),
                rgb_from_packed_pixel(src_row1 + (x * 4), source_format),
                rgb_from_packed_pixel(src_row1 + (next_x * 4), source_format));
            float cb = 0.0f;
            float cr = 0.0f;
            rgb_to_chroma(rgb, full_range, &cb, &cr);
            dst_uv[x] = clamp_u8(cb);
            dst_uv[x + 1] = clamp_u8(cr);
        }
    }

    pixel_buffer_unlock(&destination_lock);
    pixel_buffer_unlock(&source_lock);
    return true;
}

static int32_t prepare_input_buffer(AppleCVATracker *tracker,
                                    CVPixelBufferRef input_buffer,
                                    CVPixelBufferRef *out_buffer) {
    const OSType input_format = CVPixelBufferGetPixelFormatType(input_buffer);
    if (input_format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
        input_format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        *out_buffer = input_buffer;
        return APPLECVA_OK;
    }

    if (!tracker->config.enable_rgb_fallback_conversion) {
        return APPLECVA_ERR_UNSUPPORTED_PIXEL_FORMAT;
    }
    if (input_format != kCVPixelFormatType_32BGRA &&
        input_format != kCVPixelFormatType_32ARGB &&
        input_format != kCVPixelFormatType_32RGBA) {
        return APPLECVA_ERR_UNSUPPORTED_PIXEL_FORMAT;
    }
    if (!ensure_scratch_buffer(tracker, CVPixelBufferGetWidth(input_buffer),
                               CVPixelBufferGetHeight(input_buffer))) {
        return APPLECVA_ERR_CONVERSION_FAILED;
    }
    if (!convert_packed_to_nv12(tracker, input_buffer,
                                tracker->scratch_buffer)) {
        return APPLECVA_ERR_CONVERSION_FAILED;
    }
    *out_buffer = tracker->scratch_buffer;
    return APPLECVA_OK;
}

static CFTypeRef dictionary_get_typed_value(CFDictionaryRef dictionary,
                                            CFStringRef key,
                                            CFTypeID expected_type) {
    if (dictionary == NULL || key == NULL) {
        return NULL;
    }
    CFTypeRef value = (CFTypeRef)CFDictionaryGetValue(dictionary, key);
    if (value == NULL || CFGetTypeID(value) != expected_type) {
        return NULL;
    }
    return value;
}

static CFArrayRef dictionary_get_array(CFDictionaryRef dictionary,
                                       CFStringRef key) {
    return (CFArrayRef)dictionary_get_typed_value(dictionary, key,
                                                  CFArrayGetTypeID());
}

static CFDictionaryRef dictionary_get_dictionary(CFDictionaryRef dictionary,
                                                 CFStringRef key) {
    return (CFDictionaryRef)dictionary_get_typed_value(dictionary, key,
                                                       CFDictionaryGetTypeID());
}

static CFDataRef dictionary_get_data(CFDictionaryRef dictionary,
                                     CFStringRef key) {
    return (CFDataRef)dictionary_get_typed_value(dictionary, key,
                                                 CFDataGetTypeID());
}

static CFStringRef dictionary_get_string(CFDictionaryRef dictionary,
                                         CFStringRef key) {
    return (CFStringRef)dictionary_get_typed_value(dictionary, key,
                                                   CFStringGetTypeID());
}

static bool cf_type_to_double(CFTypeRef value, double *out_value) {
    if (value == NULL || out_value == NULL ||
        CFGetTypeID(value) != CFNumberGetTypeID()) {
        return false;
    }
    return CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, out_value);
}

static bool dictionary_get_double(CFDictionaryRef dictionary, CFStringRef key,
                                  double *out_value) {
    if (dictionary == NULL) {
        return false;
    }
    return cf_type_to_double((CFTypeRef)CFDictionaryGetValue(dictionary, key),
                             out_value);
}

static bool cf_type_to_int64(CFTypeRef value, int64_t *out_value) {
    if (value == NULL || out_value == NULL ||
        CFGetTypeID(value) != CFNumberGetTypeID()) {
        return false;
    }
    return CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, out_value);
}

static bool dictionary_get_int64(CFDictionaryRef dictionary, CFStringRef key,
                                 int64_t *out_value) {
    if (dictionary == NULL) {
        return false;
    }
    return cf_type_to_int64((CFTypeRef)CFDictionaryGetValue(dictionary, key),
                            out_value);
}

static bool fill_float_array_from_cfarray(CFArrayRef array, float *out_values,
                                          size_t count) {
    if (array == NULL || out_values == NULL ||
        CFArrayGetCount(array) < (CFIndex)count) {
        return false;
    }
    for (size_t i = 0; i < count; ++i) {
        double value = 0.0;
        if (!cf_type_to_double(
                (CFTypeRef)CFArrayGetValueAtIndex(array, (CFIndex)i), &value) ||
            !isfinite(value)) {
            return false;
        }
        out_values[i] = (float)value;
    }
    return true;
}

static bool fill_matrix3x3_from_nested_array(CFArrayRef rows,
                                             float *out_values) {
    if (rows == NULL || out_values == NULL || CFArrayGetCount(rows) < 3) {
        return false;
    }
    for (CFIndex row = 0; row < 3; ++row) {
        const void *row_value = CFArrayGetValueAtIndex(rows, row);
        if (row_value == NULL || CFGetTypeID(row_value) != CFArrayGetTypeID()) {
            return false;
        }
        if (!fill_float_array_from_cfarray((CFArrayRef)row_value,
                                           &out_values[row * 3], 3)) {
            return false;
        }
    }
    return true;
}

static void fill_rect_from_dictionary(CFDictionaryRef dictionary,
                                      float *out_rect) {
    memset(out_rect, 0, sizeof(float) * 4);
    if (dictionary == NULL) {
        return;
    }
    double x = 0.0;
    double y = 0.0;
    double width = 0.0;
    double height = 0.0;
    if (dictionary_get_double(dictionary, CFSTR("X"), &x) &&
        dictionary_get_double(dictionary, CFSTR("Y"), &y) &&
        dictionary_get_double(dictionary, CFSTR("Width"), &width) &&
        dictionary_get_double(dictionary, CFSTR("Height"), &height)) {
        out_rect[0] = (float)x;
        out_rect[1] = (float)y;
        out_rect[2] = (float)width;
        out_rect[3] = (float)height;
    }
}

static void fill_pose_from_dictionary(CFDictionaryRef dictionary,
                                      float *out_rotation,
                                      float *out_translation) {
    memset(out_rotation, 0, sizeof(float) * 9);
    memset(out_translation, 0, sizeof(float) * 3);
    if (dictionary == NULL) {
        return;
    }
    fill_matrix3x3_from_nested_array(
        dictionary_get_array(dictionary, CFSTR("rotation")), out_rotation);
    fill_float_array_from_cfarray(
        dictionary_get_array(dictionary, CFSTR("translation")), out_translation,
        3);
}

static void copy_cfdata_values(CFDataRef data, void *out_values,
                               size_t value_size, size_t max_values,
                               size_t *out_count) {
    if (out_count != NULL) {
        *out_count = 0;
    }
    if (data == NULL || out_values == NULL || max_values == 0) {
        return;
    }
    const size_t value_count = (size_t)CFDataGetLength(data) / value_size;
    const size_t copy_count =
        (value_count < max_values) ? value_count : max_values;
    memcpy(out_values, CFDataGetBytePtr(data), copy_count * value_size);
    if (out_count != NULL) {
        *out_count = copy_count;
    }
}

static void fill_cfdata_floats(CFDataRef data, float *out_values,
                               size_t max_values, size_t *out_count) {
    copy_cfdata_values(data, out_values, sizeof(float), max_values, out_count);
}

static void fill_cfdata_u32s(CFDataRef data, uint32_t *out_values,
                             size_t max_values, size_t *out_count) {
    copy_cfdata_values(data, out_values, sizeof(uint32_t), max_values,
                       out_count);
}

static bool
copy_string_array(CFArrayRef array,
                  char out_values[][APPLECVA_MAX_SEMANTIC_NAME_LENGTH],
                  size_t max_values, size_t *out_count) {
    *out_count = 0;
    if (array == NULL) {
        return true;
    }
    const CFIndex count = CFArrayGetCount(array);
    if ((size_t)count > max_values) {
        return false;
    }
    for (CFIndex i = 0; i < count; ++i) {
        const void *item = CFArrayGetValueAtIndex(array, i);
        if (item == NULL || CFGetTypeID(item) != CFStringGetTypeID()) {
            return false;
        }
        if (!CFStringGetCString((CFStringRef)item, out_values[i],
                                APPLECVA_MAX_SEMANTIC_NAME_LENGTH,
                                kCFStringEncodingUTF8)) {
            return false;
        }
    }
    *out_count = (size_t)count;
    return true;
}

typedef struct {
    CFDictionaryRef root;
    CFDictionaryRef animation;
    CFDictionaryRef geometry;
    CFDictionaryRef pose;
} AppleCVAFacePayload;

static AppleCVAFacePayload face_payload_from_dictionary(CFDictionaryRef source,
                                                        CFStringRef key) {
    AppleCVAFacePayload payload = {0};
    payload.root = dictionary_get_dictionary(source, key);
    payload.animation =
        dictionary_get_dictionary(payload.root, CFSTR("animation"));
    payload.geometry =
        dictionary_get_dictionary(payload.root, CFSTR("geometry"));
    payload.pose = dictionary_get_dictionary(payload.root, CFSTR("pose"));
    return payload;
}

static bool dictionary_get_preferred_double(CFDictionaryRef preferred,
                                            CFDictionaryRef fallback,
                                            CFStringRef key,
                                            double *out_value) {
    return dictionary_get_double(preferred, key, out_value) ||
           dictionary_get_double(fallback, key, out_value);
}

static void fill_face_animation_scalar(CFDictionaryRef raw_animation,
                                       CFDictionaryRef smooth_animation,
                                       CFStringRef key, float *out_value) {
    double scalar = 0.0;
    if (dictionary_get_preferred_double(smooth_animation, raw_animation, key,
                                        &scalar)) {
        *out_value = (float)scalar;
    }
}

static void fill_face_gaze(CFDictionaryRef raw_animation,
                           CFDictionaryRef smooth_animation,
                           AppleCVATrackedFace *face) {
    const bool has_raw_gaze = fill_float_array_from_cfarray(
        dictionary_get_array(raw_animation, CFSTR("gaze")), face->raw_gaze, 3);
    const bool has_smooth_gaze = fill_float_array_from_cfarray(
        dictionary_get_array(smooth_animation, CFSTR("gaze")),
        face->smooth_gaze, 3);
    if (has_smooth_gaze) {
        memcpy(face->gaze, face->smooth_gaze, sizeof(face->gaze));
    } else if (has_raw_gaze) {
        memcpy(face->gaze, face->raw_gaze, sizeof(face->gaze));
    }
}

static void copy_preferred_float_values(const float *preferred,
                                        size_t preferred_count,
                                        const float *fallback,
                                        size_t fallback_count,
                                        float *out_values, size_t *out_count) {
    const float *source = preferred;
    size_t count = preferred_count;
    if (count == 0) {
        source = fallback;
        count = fallback_count;
    }
    if (count != 0) {
        memcpy(out_values, source, count * sizeof(float));
    }
    *out_count = count;
}

static void fill_face_blendshapes(CFDictionaryRef raw_animation,
                                  CFDictionaryRef smooth_animation,
                                  AppleCVATrackedFace *face) {
    fill_cfdata_floats(dictionary_get_data(raw_animation, CFSTR("blendshapes")),
                       face->raw_blendshapes, APPLECVA_MAX_BLENDSHAPES,
                       &face->raw_blendshape_count);
    fill_cfdata_floats(
        dictionary_get_data(smooth_animation, CFSTR("blendshapes")),
        face->smooth_blendshapes, APPLECVA_MAX_BLENDSHAPES,
        &face->smooth_blendshape_count);
    copy_preferred_float_values(
        face->smooth_blendshapes, face->smooth_blendshape_count,
        face->raw_blendshapes, face->raw_blendshape_count, face->blendshapes,
        &face->blendshape_count);
}

static void fill_tracked_face_from_dictionary(CFDictionaryRef dictionary,
                                              AppleCVATrackedFace *face) {
    memset(face, 0, sizeof(*face));
    if (dictionary == NULL) {
        return;
    }
    face->valid = true;

    CFStringRef face_id = dictionary_get_string(dictionary, CFSTR("face_id"));
    if (face_id != NULL) {
        CFStringGetCString(face_id, face->face_id, sizeof(face->face_id),
                           kCFStringEncodingUTF8);
    }

    double confidence = 0.0;
    double angle_roll = 0.0;
    int64_t confidence_level = 0;
    int64_t failure_type = 0;
    dictionary_get_double(dictionary, CFSTR("confidence"), &confidence);
    dictionary_get_double(dictionary, CFSTR("AngleInfoRoll"), &angle_roll);
    dictionary_get_int64(dictionary, CFSTR("confidence_level"),
                         &confidence_level);
    dictionary_get_int64(dictionary, CFSTR("failure_type"), &failure_type);
    face->confidence = (float)confidence;
    face->confidence_level = (int32_t)confidence_level;
    face->failure_type = (int32_t)failure_type;
    face->angle_roll = (float)angle_roll;
    fill_rect_from_dictionary(
        dictionary_get_dictionary(dictionary, CFSTR("Rect")), face->rect);

    const AppleCVAFacePayload raw =
        face_payload_from_dictionary(dictionary, CFSTR("raw_data"));
    const AppleCVAFacePayload smooth =
        face_payload_from_dictionary(dictionary, CFSTR("smooth_data"));

    fill_face_gaze(raw.animation, smooth.animation, face);
    fill_float_array_from_cfarray(
        dictionary_get_array(smooth.geometry, CFSTR("left_eye")),
        face->left_eye, 3);
    fill_float_array_from_cfarray(
        dictionary_get_array(smooth.geometry, CFSTR("right_eye")),
        face->right_eye, 3);

    fill_face_animation_scalar(raw.animation, smooth.animation,
                               CFSTR("left_eye_pitch"), &face->left_eye_pitch);
    fill_face_animation_scalar(raw.animation, smooth.animation,
                               CFSTR("left_eye_yaw"), &face->left_eye_yaw);
    fill_face_animation_scalar(raw.animation, smooth.animation,
                               CFSTR("right_eye_pitch"),
                               &face->right_eye_pitch);
    fill_face_animation_scalar(raw.animation, smooth.animation,
                               CFSTR("right_eye_yaw"), &face->right_eye_yaw);
    fill_face_animation_scalar(raw.animation, smooth.animation,
                               CFSTR("tongue_out"), &face->tongue_out);

    fill_pose_from_dictionary(raw.pose, face->raw_rotation,
                              face->raw_translation);
    fill_pose_from_dictionary(smooth.pose, face->smooth_rotation,
                              face->smooth_translation);
    fill_face_blendshapes(raw.animation, smooth.animation, face);
    fill_cfdata_floats(dictionary_get_data(smooth.geometry, CFSTR("landmarks")),
                       face->landmarks, APPLECVA_MAX_LANDMARK_FLOATS,
                       &face->landmark_float_count);
    face->landmark_pair_count = face->landmark_float_count / 2;
}

static NSNumber *full_api_number_from_env(const char *name) {
    const char *value = getenv(name);
    if (value == NULL || value[0] == '\0') {
        return nil;
    }
    char *end = NULL;
    const double parsed = strtod(value, &end);
    if (end == value || !isfinite(parsed)) {
        return nil;
    }
    return @(parsed);
}

static uint32_t effective_lux_level(const AppleCVATracker *tracker,
                                    uint32_t lux_level) {
    return (lux_level != 0) ? lux_level : tracker->config.default_lux_level;
}

static void tracker_apply_config(AppleCVATracker *tracker,
                                 const AppleCVAConfig *config) {
    AppleCVAConfigInit(&tracker->config);
    if (config != NULL) {
        tracker->config = *config;
    }
    if (tracker->config.focal_scale <= 0.0f) {
        tracker->config.focal_scale = 1.0f;
    }
}

static void tracker_release_runtime(AppleCVATracker *tracker) {
    tracker_release_scratch_buffer(tracker);
    if (tracker->tracker != NULL) {
        CFRelease((CFTypeRef)tracker->tracker);
        tracker->tracker = NULL;
    }
    if (tracker->full_tracker != NULL) {
        CFRelease((CFTypeRef)tracker->full_tracker);
        tracker->full_tracker = NULL;
    }
    if (tracker->full_last_output != NULL) {
        CFRelease(tracker->full_last_output);
        tracker->full_last_output = NULL;
    }
    unload_api(&tracker->api);
    unload_full_api(&tracker->full_api);
}

static void full_api_add_optional_tongue_options(NSMutableDictionary *options,
                                                 const AppleCVAFullKeys *keys) {
    options[ns_key_or_literal(keys->robust_tongue, CFSTR("robust_tongue"))] =
        @YES;
}

static void full_api_add_network_options(NSMutableDictionary *options,
                                         const AppleCVAFullKeys *keys) {
    NSNumber *network_failure_multiplier =
        full_api_number_from_env("APPLECVA_FULL_NETWORK_FAILURE_MULTIPLIER");
    if (network_failure_multiplier == nil) {
        network_failure_multiplier = @1.0;
    }
    if (network_failure_multiplier != nil) {
        options[ns_key(keys->network_failure_threshold_multiplier)] =
            network_failure_multiplier;
        trace_log("full network failure multiplier=%s",
                  network_failure_multiplier.description.UTF8String);
    }
}

static void full_api_add_failure_fov_options(NSMutableDictionary *options,
                                             const AppleCVAFullKeys *keys) {
    NSNumber *failure_fov_modifier =
        full_api_number_from_env("APPLECVA_FULL_FAILURE_FOV_MODIFIER");
    if (failure_fov_modifier == nil) {
        failure_fov_modifier = @0.5;
    }
    options[ns_key_or_literal(keys->failure_fov_modifier,
                              CFSTR("failure_fov_modifier"))] =
        failure_fov_modifier;
    trace_log("full failure fov modifier=%s",
              failure_fov_modifier.description.UTF8String);
}

static NSNumber *full_api_num_tracked_faces_option(void) {
    NSNumber *num_tracked_faces =
        full_api_number_from_env("APPLECVA_FULL_NUM_TRACKED_FACES");
    return num_tracked_faces != nil ? num_tracked_faces : @1;
}

static NSMutableDictionary *
full_api_create_options(const AppleCVAFullKeys *keys) {
    NSMutableDictionary *options = [@{
        ns_key_or_literal(keys->rgb_only, CFSTR("rgb_only")) : @YES,
        ns_key(keys->num_tracked_faces) : full_api_num_tracked_faces_option(),
    } mutableCopy];
    full_api_add_optional_tongue_options(options, keys);
    full_api_add_network_options(options, keys);
    full_api_add_failure_fov_options(options, keys);
    trace_log("full create options=%s", options.description.UTF8String);
    return options;
}

static int32_t tracker_create_full_backend(AppleCVATracker *tracker) {
    if (!load_full_api(&tracker->full_api)) {
        return APPLECVA_ERR_SYMBOL_BIND;
    }
    NSMutableDictionary *options =
        full_api_create_options(&tracker->full_api.keys);
    const int32_t status = tracker->full_api.create(
        kCFAllocatorDefault, (__bridge CFDictionaryRef)options,
        &tracker->full_tracker);
    if (status != 0 || tracker->full_tracker == NULL) {
        return APPLECVA_ERR_CREATE_TRACKER;
    }
    return APPLECVA_OK;
}

static int32_t tracker_create_lite_backend(AppleCVATracker *tracker) {
    if (!load_api(&tracker->api)) {
        return APPLECVA_ERR_SYMBOL_BIND;
    }

    const CVAFaceTrackingLiteCreateOptions options =
        tracker->config.use_feature_options
            ? tracker->api.get_create_options_for_features(true, true)
            : tracker->api.get_default_create_options();
    const int32_t status =
        tracker->api.create(kCFAllocatorDefault, &options, &tracker->tracker);
    if (status != 0 || tracker->tracker == NULL) {
        return APPLECVA_ERR_CREATE_TRACKER;
    }
    return APPLECVA_OK;
}

int32_t AppleCVATrackerCreate(const AppleCVAConfig *config,
                              AppleCVATracker **out_tracker) {
    if (out_tracker == NULL) {
        return APPLECVA_ERR_INVALID_ARGUMENT;
    }
    *out_tracker = NULL;

    AppleCVATracker *tracker = calloc(1, sizeof(*tracker));
    if (tracker == NULL) {
        return APPLECVA_ERR_CREATE_TRACKER;
    }

    tracker_apply_config(tracker, config);

    const int32_t status = tracker->config.use_full_api
                               ? tracker_create_full_backend(tracker)
                               : tracker_create_lite_backend(tracker);
    if (status != APPLECVA_OK) {
        tracker_release_runtime(tracker);
        free(tracker);
        return status;
    }

    *out_tracker = tracker;
    return APPLECVA_OK;
}

void AppleCVATrackerDestroy(AppleCVATracker *tracker) {
    if (tracker == NULL) {
        return;
    }
    tracker_release_runtime(tracker);
    free(tracker);
}

static void init_raw_output_result(CFDictionaryRef *out_decoded_output,
                                   bool *out_aux_flag) {
    *out_decoded_output = NULL;
    if (out_aux_flag != NULL) {
        *out_aux_flag = false;
    }
}

static int32_t
copy_raw_decoded_output_internal(AppleCVATracker *tracker,
                                 CFDictionaryRef *out_decoded_output,
                                 bool *out_aux_flag) {
    if (tracker == NULL || out_decoded_output == NULL) {
        return APPLECVA_ERR_INVALID_ARGUMENT;
    }
    init_raw_output_result(out_decoded_output, out_aux_flag);

    const void *output = tracker->api.get_output(tracker->tracker);
    if (output == NULL) {
        trace_log("get_output => NULL");
        return APPLECVA_ERR_DECODE_FAILED;
    }
    trace_log("get_output => %p", output);

    Boolean aux_flag = false;
    CFDictionaryRef decoded_output = NULL;
    const int32_t status =
        tracker->api.copy_decoded_output(output, &decoded_output, &aux_flag);
    if (out_aux_flag != NULL) {
        *out_aux_flag = (aux_flag != false);
    }
    trace_log("copy_decoded_output => %d aux=%d decoded=%p", status,
              (int)(aux_flag != false), decoded_output);
    if (status != 0 || decoded_output == NULL) {
        if (decoded_output != NULL) {
            CFRelease(decoded_output);
        }
        return (status != 0) ? status : APPLECVA_ERR_DECODE_FAILED;
    }

    *out_decoded_output = decoded_output;
    return APPLECVA_OK;
}

uint32_t AppleCVAMaximumTrackedFaces(void) {
    AppleCVALiteAPI api;
    if (!load_api(&api)) {
        return 0;
    }
    const uint32_t value = api.maximum_number_of_tracked_faces();
    unload_api(&api);
    return value;
}

int32_t AppleCVACopySemantics(AppleCVASemantics *out_semantics) {
    if (out_semantics == NULL) {
        return APPLECVA_ERR_INVALID_ARGUMENT;
    }
    AppleCVASemanticsInit(out_semantics);

    AppleCVALiteAPI api;
    if (!load_api(&api)) {
        return APPLECVA_ERR_SYMBOL_BIND;
    }
    out_semantics->maximum_tracked_faces =
        api.maximum_number_of_tracked_faces();

    CFDictionaryRef semantics = NULL;
    int32_t result = APPLECVA_OK;
    const int32_t status = api.copy_semantics(NULL, &semantics);
    if (status != 0 || semantics == NULL) {
        result = (status != 0) ? status : APPLECVA_ERR_SEMANTICS_FAILED;
        goto cleanup;
    }

    const bool ok =
        copy_string_array(
            dictionary_get_array(semantics, CFSTR("blendshape_names")),
            out_semantics->blendshape_names, APPLECVA_MAX_BLENDSHAPES,
            &out_semantics->blendshape_name_count) &&
        copy_string_array(
            dictionary_get_array(semantics, CFSTR("landmark_names")),
            out_semantics->landmark_names, APPLECVA_MAX_LANDMARKS,
            &out_semantics->landmark_name_count);

    const CFDictionaryRef mesh =
        dictionary_get_dictionary(semantics, CFSTR("mesh"));
    fill_cfdata_floats(dictionary_get_data(mesh, CFSTR("mesh_vertices")),
                       out_semantics->mesh_vertices,
                       APPLECVA_MAX_MESH_VERTEX_FLOATS,
                       &out_semantics->mesh_vertex_float_count);
    fill_cfdata_floats(dictionary_get_data(mesh, CFSTR("mesh_texcoords")),
                       out_semantics->mesh_texcoords,
                       APPLECVA_MAX_MESH_TEXCOORD_FLOATS,
                       &out_semantics->mesh_texcoord_float_count);
    fill_cfdata_u32s(dictionary_get_data(mesh, CFSTR("mesh_quad_indices")),
                     out_semantics->mesh_quad_indices,
                     APPLECVA_MAX_MESH_QUAD_INDICES,
                     &out_semantics->mesh_quad_index_count);

    out_semantics->valid = ok && out_semantics->blendshape_name_count != 0 &&
                           out_semantics->landmark_name_count != 0;
    result = out_semantics->valid ? APPLECVA_OK : APPLECVA_ERR_SEMANTICS_FAILED;

cleanup:
    if (semantics != NULL) {
        CFRelease(semantics);
    }
    unload_api(&api);
    return result;
}

int32_t AppleCVATrackerCopyRawDecodedOutput(AppleCVATracker *tracker,
                                            CFDictionaryRef *out_decoded_output,
                                            bool *out_aux_flag) {
    if (tracker != NULL && tracker->config.use_full_api) {
        if (out_decoded_output == NULL) {
            return APPLECVA_ERR_INVALID_ARGUMENT;
        }
        init_raw_output_result(out_decoded_output, out_aux_flag);
        if (tracker->full_last_output == NULL) {
            return APPLECVA_ERR_DECODE_FAILED;
        }
        *out_decoded_output =
            (CFDictionaryRef)CFRetain(tracker->full_last_output);
        return APPLECVA_OK;
    }
    return copy_raw_decoded_output_internal(tracker, out_decoded_output,
                                            out_aux_flag);
}

static void fill_frame_result_from_output(CFDictionaryRef decoded_output,
                                          AppleCVAFrameResult *out_result) {
    out_result->detected_face_count = 0;
    out_result->tracked_face_count = 0;
    const CFArrayRef detected_array =
        dictionary_get_array(decoded_output, CFSTR("DetectedFacesArray"));
    if (detected_array != NULL) {
        out_result->detected_face_count =
            (size_t)CFArrayGetCount(detected_array);
    }

    const CFArrayRef tracked_array =
        dictionary_get_array(decoded_output, CFSTR("tracked_faces"));
    if (tracked_array == NULL) {
        return;
    }

    out_result->tracked_face_count = (size_t)CFArrayGetCount(tracked_array);
    out_result->tracked_faces_written =
        (out_result->tracked_face_count < out_result->tracked_face_capacity)
            ? out_result->tracked_face_count
            : out_result->tracked_face_capacity;
    out_result->tracked_faces_truncated =
        (out_result->tracked_face_count > out_result->tracked_face_capacity);

    for (size_t i = 0; i < out_result->tracked_faces_written; ++i) {
        const void *item = CFArrayGetValueAtIndex(tracked_array, (CFIndex)i);
        if (item != NULL && CFGetTypeID(item) == CFDictionaryGetTypeID()) {
            fill_tracked_face_from_dictionary((CFDictionaryRef)item,
                                              &out_result->tracked_faces[i]);
        }
    }
}

static void tracker_take_full_last_output(AppleCVATracker *tracker,
                                          CFDictionaryRef output) {
    if (tracker->full_last_output != NULL) {
        CFRelease(tracker->full_last_output);
    }
    tracker->full_last_output = output;
}

static void trace_full_output(CFDictionaryRef output) {
    CFArrayRef tracked_array =
        dictionary_get_array(output, CFSTR("tracked_faces"));
    CFArrayRef detected_array =
        dictionary_get_array(output, CFSTR("DetectedFacesArray"));
    CFStringRef facekit_error =
        dictionary_get_string(output, CFSTR("facekit error"));
    char error_buffer[128] = {0};
    if (facekit_error != NULL) {
        CFStringGetCString(facekit_error, error_buffer, sizeof(error_buffer),
                           kCFStringEncodingUTF8);
    }
    trace_log("full output detected=%ld tracked=%ld error=%s",
              detected_array != NULL ? CFArrayGetCount(detected_array) : -1,
              tracked_array != NULL ? CFArrayGetCount(tracked_array) : -1,
              error_buffer[0] != '\0' ? error_buffer : "-");
}

static NSArray *full_api_matrix3x3(const float values[9]) {
    return @[
        @[ @(values[0]), @(values[1]), @(values[2]) ],
        @[ @(values[3]), @(values[4]), @(values[5]) ],
        @[ @(values[6]), @(values[7]), @(values[8]) ],
    ];
}

static NSDictionary *
full_api_camera_dictionary(const AppleCVAFullKeys *keys,
                           const AppleCVACameraParameters *camera_parameters) {
    return @{
        ns_key(keys->intrinsics) :
            full_api_matrix3x3(camera_parameters->intrinsics),
        ns_key(keys->extrinsics) : @{
            ns_key(keys->rotation) :
                full_api_matrix3x3(camera_parameters->rotation),
            ns_key(keys->translation) : @[
                @(camera_parameters->translation[0]),
                @(camera_parameters->translation[1]),
                @(camera_parameters->translation[2]),
            ],
        },
    };
}

static NSDictionary *full_api_time_dictionary(double timestamp_seconds) {
    CMTime time = CMTimeMakeWithSeconds(timestamp_seconds, 600);
    return CFBridgingRelease(CMTimeCopyAsDictionary(time, kCFAllocatorDefault));
}

static float full_api_face_smoothing_alpha(void) {
    const char *value = getenv("APPLECVA_FULL_FACE_SMOOTHING");
    if (value == NULL || value[0] == '\0') {
        return APPLECVA_FULL_FACE_DEFAULT_SMOOTHING;
    }
    const float alpha = strtof(value, NULL);
    if (!(alpha >= 0.0f && alpha <= 1.0f)) {
        return APPLECVA_FULL_FACE_DEFAULT_SMOOTHING;
    }
    return alpha;
}

static size_t full_api_face_hold_frames(void) {
    const char *value = getenv("APPLECVA_FULL_FACE_HOLD");
    if (value == NULL || value[0] == '\0') {
        return APPLECVA_FULL_FACE_DEFAULT_HOLD_FRAMES;
    }
    char *end = NULL;
    const unsigned long frames = strtoul(value, &end, 10);
    if (end == value) {
        return APPLECVA_FULL_FACE_DEFAULT_HOLD_FRAMES;
    }
    return (size_t)frames;
}

static float blend_float(float previous, float current, float alpha) {
    return previous + ((current - previous) * alpha);
}

static bool detected_face_rect_is_plausible(const AppleCVADetectedFace *face) {
    return face != NULL && isfinite(face->x) && isfinite(face->y) &&
           isfinite(face->width) && isfinite(face->height) &&
           face->width > 0.0f && face->height > 0.0f;
}

static float detected_face_center_distance2(const AppleCVADetectedFace *a,
                                            const AppleCVADetectedFace *b) {
    const float ax = a->x + (a->width * 0.5f);
    const float ay = a->y + (a->height * 0.5f);
    const float bx = b->x + (b->width * 0.5f);
    const float by = b->y + (b->height * 0.5f);
    const float dx = ax - bx;
    const float dy = ay - by;
    return (dx * dx) + (dy * dy);
}

static void smooth_detected_face(AppleCVADetectedFace *destination,
                                 const AppleCVADetectedFace *source,
                                 float alpha) {
    destination->x = blend_float(destination->x, source->x, alpha);
    destination->y = blend_float(destination->y, source->y, alpha);
    destination->width = blend_float(destination->width, source->width, alpha);
    destination->height =
        blend_float(destination->height, source->height, alpha);
    destination->roll = blend_float(destination->roll, source->roll, alpha);
}

static size_t full_api_prepare_detected_faces(
    AppleCVATracker *tracker, const AppleCVADetectedFace *detected_faces,
    size_t detected_face_count, AppleCVADetectedFace *out_faces,
    size_t out_face_capacity) {
    const size_t hold_frames = full_api_face_hold_frames();
    const float alpha = full_api_face_smoothing_alpha();
    size_t valid_count = 0;
    const size_t input_limit = detected_face_count < out_face_capacity
                                   ? detected_face_count
                                   : out_face_capacity;

    for (size_t i = 0; i < input_limit; ++i) {
        if (!detected_face_rect_is_plausible(&detected_faces[i])) {
            continue;
        }
        AppleCVADetectedFace face = detected_faces[i];
        if (tracker->full_input_face_count != 0) {
            size_t best_index = 0;
            float best_distance = detected_face_center_distance2(
                &face, &tracker->full_input_faces[0]);
            for (size_t j = 1; j < tracker->full_input_face_count; ++j) {
                const float distance = detected_face_center_distance2(
                    &face, &tracker->full_input_faces[j]);
                if (distance < best_distance) {
                    best_distance = distance;
                    best_index = j;
                }
            }
            if (best_distance < APPLECVA_FULL_FACE_MATCH_DISTANCE2) {
                AppleCVADetectedFace smoothed =
                    tracker->full_input_faces[best_index];
                smooth_detected_face(&smoothed, &face, alpha);
                face = smoothed;
            }
        }
        out_faces[valid_count++] = face;
    }

    if (valid_count != 0) {
        memcpy(tracker->full_input_faces, out_faces,
               valid_count * sizeof(*out_faces));
        tracker->full_input_face_count = valid_count;
        tracker->full_missing_detection_frames = 0;
    } else if (tracker->full_input_face_count != 0 &&
               tracker->full_missing_detection_frames < hold_frames) {
        ++tracker->full_missing_detection_frames;
        valid_count = tracker->full_input_face_count;
        memcpy(out_faces, tracker->full_input_faces,
               valid_count * sizeof(*out_faces));
    } else {
        tracker->full_input_face_count = 0;
        tracker->full_missing_detection_frames = 0;
    }

    if (trace_enabled() && (detected_face_count != valid_count ||
                            tracker->full_missing_detection_frames != 0)) {
        trace_log("full faces raw=%zu used=%zu held=%zu", detected_face_count,
                  valid_count, tracker->full_missing_detection_frames);
    }
    return valid_count;
}

static NSArray *
full_api_detected_faces_array(const AppleCVAFullKeys *keys,
                              const AppleCVADetectedFace *detected_faces,
                              size_t detected_face_count) {
    NSMutableArray *array =
        [NSMutableArray arrayWithCapacity:detected_face_count];
    for (size_t i = 0; i < detected_face_count; ++i) {
        const AppleCVADetectedFace *face = &detected_faces[i];
        const CGFloat y = 1.0 - (CGFloat)face->y - (CGFloat)face->height;
        CGRect rect = CGRectMake((CGFloat)face->x, y, (CGFloat)face->width,
                                 (CGFloat)face->height);
        if (i == 0) {
            trace_log("full face rect=(%.4f %.4f %.4f %.4f)",
                      (double)rect.origin.x, (double)rect.origin.y,
                      (double)rect.size.width, (double)rect.size.height);
        }
        NSDictionary *rect_dictionary =
            CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect));
        [array addObject:@{
            ns_key(keys->detected_face_rect) : rect_dictionary,
            ns_key(keys->detected_face_angle_roll) : @(face->roll),
            ns_key(keys->detected_face_face_id) : @(i),
        }];
    }
    return array;
}

static int32_t
process_frame_full_api(AppleCVATracker *tracker, CVPixelBufferRef input_buffer,
                       const AppleCVACameraParameters *camera_parameters,
                       const AppleCVADetectedFace *detected_faces,
                       size_t detected_face_count, double timestamp_seconds,
                       uint32_t lux_level, AppleCVAFrameResult *out_result) {
    const AppleCVAFullKeys *keys = &tracker->full_api.keys;
    NSDictionary *camera = full_api_camera_dictionary(keys, camera_parameters);
    AppleCVADetectedFace prepared_faces[APPLECVA_FULL_MAX_INPUT_FACES];
    const size_t prepared_face_count = full_api_prepare_detected_faces(
        tracker, detected_faces, detected_face_count, prepared_faces,
        sizeof(prepared_faces) / sizeof(prepared_faces[0]));
    NSArray *faces = full_api_detected_faces_array(keys, prepared_faces,
                                                   prepared_face_count);
    const uint32_t effective_lux = effective_lux_level(tracker, lux_level);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block CFDictionaryRef callback_output = NULL;
    void (^callback)(CFDictionaryRef output) = ^(CFDictionaryRef output) {
      if (output != NULL) {
          callback_output = (CFDictionaryRef)CFRetain(output);
      }
      dispatch_semaphore_signal(semaphore);
    };

    NSMutableDictionary *input = [@{
        ns_key(keys->color) : (__bridge id)input_buffer,
        ns_key(keys->camera_color) : camera,
        ns_key(keys->color_meta_data) : @{
            ns_key(keys->lux_level) : @(effective_lux),
        },
        ns_key(keys->meta) : @{
            ns_key(keys->meta_version) : @1,
        },
        ns_key(keys->timestamp) : full_api_time_dictionary(timestamp_seconds),
        ns_key(keys->detected_faces_array) : faces,
        ns_key(keys->callback) : [callback copy],
    } mutableCopy];

    const int32_t status = tracker->full_api.process(
        tracker->full_tracker, (__bridge CFDictionaryRef)input);
    trace_log("full process => %d", status);
    if (status != 0) {
        if (callback_output != NULL) {
            CFRelease(callback_output);
        }
        return status;
    }

    dispatch_time_t deadline =
        dispatch_time(DISPATCH_TIME_NOW, APPLECVA_FULL_CALLBACK_TIMEOUT_NS);
    (void)dispatch_semaphore_wait(semaphore, deadline);
    if (callback_output == NULL) {
        return APPLECVA_ERR_DECODE_FAILED;
    }

    tracker_take_full_last_output(tracker, callback_output);
    out_result->aux_flag = false;
    fill_frame_result_from_output(callback_output, out_result);
    trace_full_output(callback_output);
    return APPLECVA_OK;
}

typedef struct {
    CVAFaceTrackingLiteDetectedFace stack[APPLECVA_LITE_STACK_FACE_CAPACITY];
    CVAFaceTrackingLiteDetectedFace *faces;
    size_t count;
} AppleCVALiteFaceInput;

static int32_t lite_face_input_init(AppleCVALiteFaceInput *input,
                                    const AppleCVADetectedFace *detected_faces,
                                    size_t detected_face_count) {
    memset(input, 0, sizeof(*input));
    input->faces = input->stack;
    input->count = detected_face_count;
    if (detected_face_count > APPLECVA_ARRAY_COUNT(input->stack)) {
        input->faces = calloc(detected_face_count, sizeof(*input->faces));
        if (input->faces == NULL) {
            input->count = 0;
            return APPLECVA_ERR_INVALID_ARGUMENT;
        }
    }

    for (size_t i = 0; i < detected_face_count; ++i) {
        input->faces[i].x = detected_faces[i].x;
        input->faces[i].y = detected_faces[i].y;
        input->faces[i].width = detected_faces[i].width;
        input->faces[i].height = detected_faces[i].height;
        input->faces[i].roll = detected_faces[i].roll;
    }
    return APPLECVA_OK;
}

static void lite_face_input_destroy(AppleCVALiteFaceInput *input) {
    if (input->faces != NULL && input->faces != input->stack) {
        free(input->faces);
    }
    memset(input, 0, sizeof(*input));
}

static int32_t
submit_lite_frame(AppleCVATracker *tracker, CVPixelBufferRef input_buffer,
                  const CVAFaceTrackingLiteCameraParams *camera_parameters,
                  const AppleCVALiteFaceInput *face_input,
                  double timestamp_seconds, uint32_t lux_level) {
    int32_t status =
        tracker->api.set_timestamp(tracker->tracker, timestamp_seconds);
    trace_log("set_timestamp => %d", status);
    if (status == 0) {
        const uint32_t effective_lux = effective_lux_level(tracker, lux_level);
        status = tracker->api.set_lux_level(tracker->tracker, effective_lux);
        trace_log("set_lux_level(%u) => %d", effective_lux, status);
    }
    if (status == 0) {
        status = tracker->api.set_color_image(tracker->tracker, input_buffer,
                                              camera_parameters);
        trace_log("set_color_image => %d", status);
    }
    if (status == 0) {
        status = tracker->api.set_detected_faces(
            tracker->tracker, (uint32_t)face_input->count, face_input->faces);
        trace_log("set_detected_faces => %d", status);
    }
    if (status == 0) {
        status = tracker->api.process(tracker->tracker);
        trace_log("process => %d", status);
    }
    return status;
}

static int32_t
process_frame_lite_api(AppleCVATracker *tracker, CVPixelBufferRef input_buffer,
                       const AppleCVACameraParameters *camera_parameters,
                       const AppleCVADetectedFace *detected_faces,
                       size_t detected_face_count, double timestamp_seconds,
                       uint32_t lux_level, AppleCVAFrameResult *out_result) {
    CVAFaceTrackingLiteCameraParams internal_camera_params;
    make_internal_camera_params(camera_parameters, &internal_camera_params);

    AppleCVALiteFaceInput face_input;
    int32_t status =
        lite_face_input_init(&face_input, detected_faces, detected_face_count);
    if (status != APPLECVA_OK) {
        return status;
    }

    status = submit_lite_frame(tracker, input_buffer, &internal_camera_params,
                               &face_input, timestamp_seconds, lux_level);
    lite_face_input_destroy(&face_input);
    if (status != 0) {
        return status;
    }

    CFDictionaryRef decoded_output = NULL;
    status = copy_raw_decoded_output_internal(tracker, &decoded_output,
                                              &out_result->aux_flag);
    if (status != APPLECVA_OK) {
        return status;
    }

    fill_frame_result_from_output(decoded_output, out_result);

    CFRelease(decoded_output);
    return APPLECVA_OK;
}

int32_t AppleCVATrackerProcessFrame(
    AppleCVATracker *tracker, CVPixelBufferRef pixel_buffer,
    const AppleCVACameraParameters *camera_parameters,
    const AppleCVADetectedFace *detected_faces, size_t detected_face_count,
    double timestamp_seconds, uint32_t lux_level,
    AppleCVAFrameResult *out_result) {
    if (tracker == NULL || pixel_buffer == NULL || camera_parameters == NULL ||
        out_result == NULL) {
        return APPLECVA_ERR_INVALID_ARGUMENT;
    }
    if (detected_face_count != 0 && detected_faces == NULL) {
        return APPLECVA_ERR_INVALID_ARGUMENT;
    }

    AppleCVAFrameResultClear(out_result);
    out_result->timestamp_seconds = timestamp_seconds;
    trace_log("process begin: timestamp=%.6f detected_faces=%zu format=0x%08x",
              timestamp_seconds, detected_face_count,
              (unsigned int)CVPixelBufferGetPixelFormatType(pixel_buffer));

    CVPixelBufferRef input_buffer = NULL;
    const int32_t wrapper_status =
        prepare_input_buffer(tracker, pixel_buffer, &input_buffer);
    if (wrapper_status != APPLECVA_OK) {
        trace_log("prepare_input_buffer failed: %d", wrapper_status);
        return wrapper_status;
    }
    trace_log("input prepared: format=0x%08x",
              (unsigned int)CVPixelBufferGetPixelFormatType(input_buffer));

    if (tracker->config.use_full_api) {
        return process_frame_full_api(tracker, input_buffer, camera_parameters,
                                      detected_faces, detected_face_count,
                                      timestamp_seconds, lux_level, out_result);
    }
    return process_frame_lite_api(tracker, input_buffer, camera_parameters,
                                  detected_faces, detected_face_count,
                                  timestamp_seconds, lux_level, out_result);
}

int32_t AppleCVADetectFacesWithVisionOrientation(
    CVPixelBufferRef pixel_buffer, uint32_t cg_image_orientation,
    AppleCVADetectedFace *out_faces, size_t face_capacity,
    size_t *out_face_count) {
    if (pixel_buffer == NULL || out_face_count == NULL) {
        return APPLECVA_ERR_INVALID_ARGUMENT;
    }
    *out_face_count = 0;

    @autoreleasepool {
        NSError *error = nil;
        VNDetectFaceRectanglesRequest *request =
            [[VNDetectFaceRectanglesRequest alloc] init];
        const CGImagePropertyOrientation orientation =
            (CGImagePropertyOrientation)cg_image_orientation;
        VNImageRequestHandler *handler =
            [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixel_buffer
                                                     orientation:orientation
                                                         options:@{}];
        if (![handler performRequests:@[ request ] error:&error]) {
            return APPLECVA_ERR_VISION_FAILED;
        }

        NSArray<VNFaceObservation *> *observations = request.results ?: @[];
        *out_face_count = observations.count;
        if (observations.count > face_capacity) {
            return APPLECVA_ERR_BUFFER_TOO_SMALL;
        }
        if (observations.count != 0 && out_faces == NULL) {
            return APPLECVA_ERR_INVALID_ARGUMENT;
        }

        for (NSUInteger i = 0; i < observations.count; ++i) {
            const CGRect box = observations[i].boundingBox;
            out_faces[i].x = (float)box.origin.x;
            out_faces[i].y = (float)box.origin.y;
            out_faces[i].width = (float)box.size.width;
            out_faces[i].height = (float)box.size.height;
            out_faces[i].roll = 0.0f;
            if ([observations[i] respondsToSelector:@selector(roll)] &&
                observations[i].roll != nil) {
                out_faces[i].roll = observations[i].roll.floatValue;
            }
        }
    }

    return APPLECVA_OK;
}

int32_t AppleCVADetectFacesWithVision(CVPixelBufferRef pixel_buffer,
                                      AppleCVADetectedFace *out_faces,
                                      size_t face_capacity,
                                      size_t *out_face_count) {
    return AppleCVADetectFacesWithVisionOrientation(
        pixel_buffer, (uint32_t)kCGImagePropertyOrientationUp, out_faces,
        face_capacity, out_face_count);
}
