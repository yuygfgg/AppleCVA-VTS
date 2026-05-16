#import "applecva.h"

#import <Foundation/Foundation.h>
#import <Vision/Vision.h>

#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <math.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

typedef const struct __CVAFaceTrackingLite *CVAFaceTrackingLiteRef;

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

struct AppleCVATracker {
    AppleCVALiteAPI api;
    AppleCVAConfig config;
    CVAFaceTrackingLiteRef tracker;
    CVPixelBufferRef scratch_buffer;
    size_t scratch_width;
    size_t scratch_height;
    OSType scratch_format;
};

static bool bind_symbol(void *handle, const char *name, void **out) {
    *out = dlsym(handle, name);
    return (*out != NULL);
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
    api->handle = dlopen("/System/Library/PrivateFrameworks/AppleCVA.framework/"
                         "Versions/A/AppleCVA",
                         RTLD_NOW);
    if (api->handle == NULL) {
        return false;
    }
    return bind_symbol(api->handle, "CVAFaceTrackingLiteGetAPIVersion",
                       (void **)&api->get_api_version) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteGetTypeID",
                       (void **)&api->get_type_id) &&
           bind_symbol(api->handle,
                       "CVAFaceTrackingLiteGetDefaultCreateOptions",
                       (void **)&api->get_default_create_options) &&
           bind_symbol(api->handle,
                       "CVAFaceTrackingLiteGetCreateOptionsForFeatures",
                       (void **)&api->get_create_options_for_features) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteCreate",
                       (void **)&api->create) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteSetTimestamp",
                       (void **)&api->set_timestamp) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteSetLuxLevel",
                       (void **)&api->set_lux_level) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteSetColorImage",
                       (void **)&api->set_color_image) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteSetDetectedFaces",
                       (void **)&api->set_detected_faces) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteProcess",
                       (void **)&api->process) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteGetOutput",
                       (void **)&api->get_output) &&
           bind_symbol(api->handle, "CVAFaceTrackingLiteCopyDecodedOutput",
                       (void **)&api->copy_decoded_output) &&
           bind_symbol(api->handle, "CVAFaceTrackingCopySemantics",
                       (void **)&api->copy_semantics) &&
           bind_symbol(api->handle,
                       "CVAFaceTrackingMaximumNumberOfTrackedFaces",
                       (void **)&api->maximum_number_of_tracked_faces);
}

static void unload_api(AppleCVALiteAPI *api) {
    if (api->handle != NULL) {
        dlclose(api->handle);
        api->handle = NULL;
    }
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
    params->intrinsics[0] = (float)width * focal_scale;
    params->intrinsics[4] = (float)height * focal_scale;
    params->intrinsics[2] = ((float)width - 1.0f) * 0.5f;
    params->intrinsics[5] = ((float)height - 1.0f) * 0.5f;
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

static bool ensure_scratch_buffer(AppleCVATracker *tracker, size_t width,
                                  size_t height) {
    const OSType format = preferred_nv12_format(&tracker->config);
    if (tracker->scratch_buffer != NULL && tracker->scratch_width == width &&
        tracker->scratch_height == height &&
        tracker->scratch_format == format) {
        return true;
    }

    if (tracker->scratch_buffer != NULL) {
        CVPixelBufferRelease(tracker->scratch_buffer);
        tracker->scratch_buffer = NULL;
        tracker->scratch_width = 0;
        tracker->scratch_height = 0;
        tracker->scratch_format = 0;
    }

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

static void read_rgb_from_packed_pixel(const uint8_t *pixel, OSType format,
                                       float *r, float *g, float *b) {
    switch (format) {
    case kCVPixelFormatType_32BGRA:
        *b = (float)pixel[0];
        *g = (float)pixel[1];
        *r = (float)pixel[2];
        break;
    case kCVPixelFormatType_32ARGB:
        *r = (float)pixel[1];
        *g = (float)pixel[2];
        *b = (float)pixel[3];
        break;
    case kCVPixelFormatType_32RGBA:
        *r = (float)pixel[0];
        *g = (float)pixel[1];
        *b = (float)pixel[2];
        break;
    default:
        *r = 0.0f;
        *g = 0.0f;
        *b = 0.0f;
        break;
    }
}

static bool convert_packed_to_nv12(AppleCVATracker *tracker,
                                   CVPixelBufferRef source_buffer,
                                   CVPixelBufferRef destination_buffer) {
    const OSType source_format = CVPixelBufferGetPixelFormatType(source_buffer);
    CVReturn cv = CVPixelBufferLockBaseAddress(source_buffer,
                                               kCVPixelBufferLock_ReadOnly);
    if (cv != kCVReturnSuccess) {
        return false;
    }
    cv = CVPixelBufferLockBaseAddress(destination_buffer, 0);
    if (cv != kCVReturnSuccess) {
        CVPixelBufferUnlockBaseAddress(source_buffer,
                                       kCVPixelBufferLock_ReadOnly);
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
            float r = 0.0f;
            float g = 0.0f;
            float b = 0.0f;
            read_rgb_from_packed_pixel(src_row + (x * 4), source_format, &r, &g,
                                       &b);
            const float y_value =
                full_range ? ((0.2990f * r) + (0.5870f * g) + (0.1140f * b))
                           : (16.0f +
                              ((65.481f * r) + (128.553f * g) + (24.966f * b)) /
                                  255.0f);
            dst_y[x] = clamp_u8(y_value);
        }
    }

    for (size_t y = 0; y < height; y += 2) {
        const size_t next_y = (y + 1 < height) ? (y + 1) : y;
        const uint8_t *src_row0 = src_base + (y * src_stride);
        const uint8_t *src_row1 = src_base + (next_y * src_stride);
        uint8_t *dst_uv = uv_plane + ((y / 2) * uv_stride);
        for (size_t x = 0; x < width; x += 2) {
            const size_t next_x = (x + 1 < width) ? (x + 1) : x;
            float r_values[4] = {0.0f, 0.0f, 0.0f, 0.0f};
            float g_values[4] = {0.0f, 0.0f, 0.0f, 0.0f};
            float b_values[4] = {0.0f, 0.0f, 0.0f, 0.0f};

            read_rgb_from_packed_pixel(src_row0 + (x * 4), source_format,
                                       &r_values[0], &g_values[0],
                                       &b_values[0]);
            read_rgb_from_packed_pixel(src_row0 + (next_x * 4), source_format,
                                       &r_values[1], &g_values[1],
                                       &b_values[1]);
            read_rgb_from_packed_pixel(src_row1 + (x * 4), source_format,
                                       &r_values[2], &g_values[2],
                                       &b_values[2]);
            read_rgb_from_packed_pixel(src_row1 + (next_x * 4), source_format,
                                       &r_values[3], &g_values[3],
                                       &b_values[3]);

            const float r =
                (r_values[0] + r_values[1] + r_values[2] + r_values[3]) * 0.25f;
            const float g =
                (g_values[0] + g_values[1] + g_values[2] + g_values[3]) * 0.25f;
            const float b =
                (b_values[0] + b_values[1] + b_values[2] + b_values[3]) * 0.25f;

            const float cb = full_range
                                 ? ((-0.168736f * r) - (0.331264f * g) +
                                    (0.500000f * b) + 128.0f)
                                 : (128.0f + ((-37.797f * r) - (74.203f * g) +
                                              (112.000f * b)) /
                                                 255.0f);
            const float cr =
                full_range ? ((0.500000f * r) - (0.418688f * g) -
                              (0.081312f * b) + 128.0f)
                           : (128.0f +
                              ((112.000f * r) - (93.786f * g) - (18.214f * b)) /
                                  255.0f);
            dst_uv[x] = clamp_u8(cb);
            dst_uv[x + 1] = clamp_u8(cr);
        }
    }

    CVPixelBufferUnlockBaseAddress(destination_buffer, 0);
    CVPixelBufferUnlockBaseAddress(source_buffer, kCVPixelBufferLock_ReadOnly);
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

static CFArrayRef dictionary_get_array(CFDictionaryRef dictionary,
                                       CFStringRef key) {
    if (dictionary == NULL) {
        return NULL;
    }
    const void *value = CFDictionaryGetValue(dictionary, key);
    if (value == NULL || CFGetTypeID(value) != CFArrayGetTypeID()) {
        return NULL;
    }
    return (CFArrayRef)value;
}

static CFDictionaryRef dictionary_get_dictionary(CFDictionaryRef dictionary,
                                                 CFStringRef key) {
    if (dictionary == NULL) {
        return NULL;
    }
    const void *value = CFDictionaryGetValue(dictionary, key);
    if (value == NULL || CFGetTypeID(value) != CFDictionaryGetTypeID()) {
        return NULL;
    }
    return (CFDictionaryRef)value;
}

static CFDataRef dictionary_get_data(CFDictionaryRef dictionary,
                                     CFStringRef key) {
    if (dictionary == NULL) {
        return NULL;
    }
    const void *value = CFDictionaryGetValue(dictionary, key);
    if (value == NULL || CFGetTypeID(value) != CFDataGetTypeID()) {
        return NULL;
    }
    return (CFDataRef)value;
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

static bool dictionary_get_int64(CFDictionaryRef dictionary, CFStringRef key,
                                 int64_t *out_value) {
    if (dictionary == NULL || out_value == NULL) {
        return false;
    }
    const void *value = CFDictionaryGetValue(dictionary, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return false;
    }
    return CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, out_value);
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

static void fill_cfdata_floats(CFDataRef data, float *out_values,
                               size_t max_values, size_t *out_count) {
    *out_count = 0;
    if (data == NULL || out_values == NULL || max_values == 0) {
        return;
    }
    const size_t value_count = (size_t)CFDataGetLength(data) / sizeof(float);
    const size_t copy_count =
        (value_count < max_values) ? value_count : max_values;
    memcpy(out_values, CFDataGetBytePtr(data), copy_count * sizeof(float));
    *out_count = copy_count;
}

static void fill_cfdata_u32s(CFDataRef data, uint32_t *out_values,
                             size_t max_values, size_t *out_count) {
    *out_count = 0;
    if (data == NULL || out_values == NULL || max_values == 0) {
        return;
    }
    const size_t value_count = (size_t)CFDataGetLength(data) / sizeof(uint32_t);
    const size_t copy_count =
        (value_count < max_values) ? value_count : max_values;
    memcpy(out_values, CFDataGetBytePtr(data), copy_count * sizeof(uint32_t));
    *out_count = copy_count;
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

static void fill_tracked_face_from_dictionary(CFDictionaryRef dictionary,
                                              AppleCVATrackedFace *face) {
    memset(face, 0, sizeof(*face));
    if (dictionary == NULL) {
        return;
    }
    face->valid = true;

    CFStringRef face_id =
        (CFStringRef)CFDictionaryGetValue(dictionary, CFSTR("face_id"));
    if (face_id != NULL && CFGetTypeID(face_id) == CFStringGetTypeID()) {
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

    CFDictionaryRef raw_data =
        dictionary_get_dictionary(dictionary, CFSTR("raw_data"));
    CFDictionaryRef raw_animation =
        dictionary_get_dictionary(raw_data, CFSTR("animation"));
    CFDictionaryRef raw_pose =
        dictionary_get_dictionary(raw_data, CFSTR("pose"));
    CFDictionaryRef smooth_data =
        dictionary_get_dictionary(dictionary, CFSTR("smooth_data"));
    CFDictionaryRef smooth_animation =
        dictionary_get_dictionary(smooth_data, CFSTR("animation"));
    CFDictionaryRef smooth_geometry =
        dictionary_get_dictionary(smooth_data, CFSTR("geometry"));
    CFDictionaryRef smooth_pose =
        dictionary_get_dictionary(smooth_data, CFSTR("pose"));

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
    fill_float_array_from_cfarray(
        dictionary_get_array(smooth_geometry, CFSTR("left_eye")),
        face->left_eye, 3);
    fill_float_array_from_cfarray(
        dictionary_get_array(smooth_geometry, CFSTR("right_eye")),
        face->right_eye, 3);

    double scalar = 0.0;
    if (dictionary_get_double(smooth_animation, CFSTR("left_eye_pitch"),
                              &scalar) ||
        dictionary_get_double(raw_animation, CFSTR("left_eye_pitch"),
                              &scalar)) {
        face->left_eye_pitch = (float)scalar;
    }
    if (dictionary_get_double(smooth_animation, CFSTR("left_eye_yaw"),
                              &scalar) ||
        dictionary_get_double(raw_animation, CFSTR("left_eye_yaw"), &scalar)) {
        face->left_eye_yaw = (float)scalar;
    }
    if (dictionary_get_double(smooth_animation, CFSTR("right_eye_pitch"),
                              &scalar) ||
        dictionary_get_double(raw_animation, CFSTR("right_eye_pitch"),
                              &scalar)) {
        face->right_eye_pitch = (float)scalar;
    }
    if (dictionary_get_double(smooth_animation, CFSTR("right_eye_yaw"),
                              &scalar) ||
        dictionary_get_double(raw_animation, CFSTR("right_eye_yaw"), &scalar)) {
        face->right_eye_yaw = (float)scalar;
    }
    if (dictionary_get_double(smooth_animation, CFSTR("tongue_out"), &scalar) ||
        dictionary_get_double(raw_animation, CFSTR("tongue_out"), &scalar)) {
        face->tongue_out = (float)scalar;
    }

    fill_pose_from_dictionary(raw_pose, face->raw_rotation,
                              face->raw_translation);
    fill_pose_from_dictionary(smooth_pose, face->smooth_rotation,
                              face->smooth_translation);
    fill_cfdata_floats(dictionary_get_data(raw_animation, CFSTR("blendshapes")),
                       face->raw_blendshapes, APPLECVA_MAX_BLENDSHAPES,
                       &face->raw_blendshape_count);
    fill_cfdata_floats(
        dictionary_get_data(smooth_animation, CFSTR("blendshapes")),
        face->smooth_blendshapes, APPLECVA_MAX_BLENDSHAPES,
        &face->smooth_blendshape_count);
    if (face->smooth_blendshape_count != 0) {
        memcpy(face->blendshapes, face->smooth_blendshapes,
               face->smooth_blendshape_count * sizeof(float));
        face->blendshape_count = face->smooth_blendshape_count;
    } else {
        memcpy(face->blendshapes, face->raw_blendshapes,
               face->raw_blendshape_count * sizeof(float));
        face->blendshape_count = face->raw_blendshape_count;
    }
    fill_cfdata_floats(dictionary_get_data(smooth_geometry, CFSTR("landmarks")),
                       face->landmarks, APPLECVA_MAX_LANDMARK_FLOATS,
                       &face->landmark_float_count);
    face->landmark_pair_count = face->landmark_float_count / 2;
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

    AppleCVAConfigInit(&tracker->config);
    if (config != NULL) {
        tracker->config = *config;
    }
    if (tracker->config.focal_scale <= 0.0f) {
        tracker->config.focal_scale = 1.0f;
    }

    if (!load_api(&tracker->api)) {
        free(tracker);
        return APPLECVA_ERR_SYMBOL_BIND;
    }

    const CVAFaceTrackingLiteCreateOptions options =
        tracker->config.use_feature_options
            ? tracker->api.get_create_options_for_features(true, true)
            : tracker->api.get_default_create_options();
    int32_t status =
        tracker->api.create(kCFAllocatorDefault, &options, &tracker->tracker);
    if (status != 0 || tracker->tracker == NULL) {
        unload_api(&tracker->api);
        free(tracker);
        return APPLECVA_ERR_CREATE_TRACKER;
    }

    *out_tracker = tracker;
    return APPLECVA_OK;
}

void AppleCVATrackerDestroy(AppleCVATracker *tracker) {
    if (tracker == NULL) {
        return;
    }
    if (tracker->scratch_buffer != NULL) {
        CVPixelBufferRelease(tracker->scratch_buffer);
    }
    if (tracker->tracker != NULL) {
        CFRelease((CFTypeRef)tracker->tracker);
    }
    unload_api(&tracker->api);
    free(tracker);
}

static int32_t
copy_raw_decoded_output_internal(AppleCVATracker *tracker,
                                 CFDictionaryRef *out_decoded_output,
                                 bool *out_aux_flag) {
    if (tracker == NULL || out_decoded_output == NULL) {
        return APPLECVA_ERR_INVALID_ARGUMENT;
    }
    *out_decoded_output = NULL;
    if (out_aux_flag != NULL) {
        *out_aux_flag = false;
    }

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
    const int32_t status = api.copy_semantics(NULL, &semantics);
    if (status != 0 || semantics == NULL) {
        if (semantics != NULL) {
            CFRelease(semantics);
        }
        unload_api(&api);
        return (status != 0) ? status : APPLECVA_ERR_SEMANTICS_FAILED;
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

    CFRelease(semantics);
    unload_api(&api);
    return out_semantics->valid ? APPLECVA_OK : APPLECVA_ERR_SEMANTICS_FAILED;
}

int32_t AppleCVATrackerCopyRawDecodedOutput(AppleCVATracker *tracker,
                                            CFDictionaryRef *out_decoded_output,
                                            bool *out_aux_flag) {
    return copy_raw_decoded_output_internal(tracker, out_decoded_output,
                                            out_aux_flag);
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
    int32_t wrapper_status =
        prepare_input_buffer(tracker, pixel_buffer, &input_buffer);
    if (wrapper_status != APPLECVA_OK) {
        trace_log("prepare_input_buffer failed: %d", wrapper_status);
        return wrapper_status;
    }
    trace_log("input prepared: format=0x%08x",
              (unsigned int)CVPixelBufferGetPixelFormatType(input_buffer));

    CVAFaceTrackingLiteCameraParams internal_camera_params;
    make_internal_camera_params(camera_parameters, &internal_camera_params);
    CVAFaceTrackingLiteDetectedFace internal_faces_stack[8];
    CVAFaceTrackingLiteDetectedFace *internal_faces_heap = NULL;
    CVAFaceTrackingLiteDetectedFace *internal_faces = internal_faces_stack;
    if (detected_face_count >
        (sizeof(internal_faces_stack) / sizeof(internal_faces_stack[0]))) {
        internal_faces_heap =
            calloc(detected_face_count, sizeof(*internal_faces_heap));
        if (internal_faces_heap == NULL) {
            return APPLECVA_ERR_INVALID_ARGUMENT;
        }
        internal_faces = internal_faces_heap;
    }

    for (size_t i = 0; i < detected_face_count; ++i) {
        internal_faces[i].x = detected_faces[i].x;
        internal_faces[i].y = detected_faces[i].y;
        internal_faces[i].width = detected_faces[i].width;
        internal_faces[i].height = detected_faces[i].height;
        internal_faces[i].roll = detected_faces[i].roll;
    }

    int32_t status =
        tracker->api.set_timestamp(tracker->tracker, timestamp_seconds);
    trace_log("set_timestamp => %d", status);
    if (status == 0) {
        const uint32_t effective_lux =
            (lux_level != 0) ? lux_level : tracker->config.default_lux_level;
        status = tracker->api.set_lux_level(tracker->tracker, effective_lux);
        trace_log("set_lux_level(%u) => %d", effective_lux, status);
    }
    if (status == 0) {
        status = tracker->api.set_color_image(tracker->tracker, input_buffer,
                                              &internal_camera_params);
        trace_log("set_color_image => %d", status);
    }
    if (status == 0) {
        status = tracker->api.set_detected_faces(
            tracker->tracker, (uint32_t)detected_face_count, internal_faces);
        trace_log("set_detected_faces => %d", status);
    }
    if (status == 0) {
        status = tracker->api.process(tracker->tracker);
        trace_log("process => %d", status);
    }

    if (internal_faces_heap != NULL) {
        free(internal_faces_heap);
    }
    if (status != 0) {
        return status;
    }

    CFDictionaryRef decoded_output = NULL;
    status = copy_raw_decoded_output_internal(tracker, &decoded_output,
                                              &out_result->aux_flag);
    if (status != APPLECVA_OK) {
        return status;
    }

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
    if (tracked_array != NULL) {
        out_result->tracked_face_count = (size_t)CFArrayGetCount(tracked_array);
        out_result->tracked_faces_written =
            (out_result->tracked_face_count < out_result->tracked_face_capacity)
                ? out_result->tracked_face_count
                : out_result->tracked_face_capacity;
        out_result->tracked_faces_truncated =
            (out_result->tracked_face_count >
             out_result->tracked_face_capacity);

        for (size_t i = 0; i < out_result->tracked_faces_written; ++i) {
            const void *item =
                CFArrayGetValueAtIndex(tracked_array, (CFIndex)i);
            if (item != NULL && CFGetTypeID(item) == CFDictionaryGetTypeID()) {
                fill_tracked_face_from_dictionary(
                    (CFDictionaryRef)item, &out_result->tracked_faces[i]);
            }
        }
    }

    CFRelease(decoded_output);
    return APPLECVA_OK;
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
