#ifndef APPLECVA_H
#define APPLECVA_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/** Status codes returned by the AppleCVA wrapper API. */
enum {
    APPLECVA_OK = 0,
    APPLECVA_ERR_INVALID_ARGUMENT = 1,
    APPLECVA_ERR_SYMBOL_BIND = 2,
    APPLECVA_ERR_CREATE_TRACKER = 3,
    APPLECVA_ERR_UNSUPPORTED_PIXEL_FORMAT = 4,
    APPLECVA_ERR_DECODE_FAILED = 6,
    APPLECVA_ERR_VISION_FAILED = 7,
    APPLECVA_ERR_BUFFER_TOO_SMALL = 8,
    APPLECVA_ERR_SEMANTICS_FAILED = 9,
};

#define APPLECVA_MAX_BLENDSHAPES 51
#define APPLECVA_MAX_LANDMARKS 66
#define APPLECVA_MAX_LANDMARK_FLOATS (APPLECVA_MAX_LANDMARKS * 2)
#define APPLECVA_FACE_ID_CAPACITY 64
#define APPLECVA_MAX_SEMANTIC_NAME_LENGTH 64
#define APPLECVA_MAX_MESH_VERTEX_FLOATS 3660
#define APPLECVA_MAX_MESH_TEXCOORD_FLOATS 2440
#define APPLECVA_MAX_MESH_QUAD_INDICES 4608

/** Current blendshape channel names exposed by AppleCVA semantics. */
static const char* const AppleCVABlendshapeNames[APPLECVA_MAX_BLENDSHAPES] = {
    "eyeBlink_L",       "eyeBlink_R",     "eyeSquint_L",
    "eyeSquint_R",      "eyeLookDown_L",  "eyeLookDown_R",
    "eyeLookIn_L",      "eyeLookIn_R",    "eyeWide_L",
    "eyeWide_R",        "eyeLookOut_L",   "eyeLookOut_R",
    "eyeLookUp_L",      "eyeLookUp_R",    "browDown_L",
    "browDown_R",       "browInnerUp",    "browOuterUp_L",
    "browOuterUp_R",    "jawOpen",        "mouthClose",
    "jawLeft",          "jawRight",       "jawForward",
    "mouthUpperUp_L",   "mouthUpperUp_R", "mouthLowerDown_L",
    "mouthLowerDown_R", "mouthRollUpper", "mouthRollLower",
    "mouthSmile_L",     "mouthSmile_R",   "mouthDimple_L",
    "mouthDimple_R",    "mouthStretch_L", "mouthStretch_R",
    "mouthFrown_L",     "mouthFrown_R",   "mouthPress_L",
    "mouthPress_R",     "mouthPucker",    "mouthFunnel",
    "mouthLeft",        "mouthRight",     "mouthShrugLower",
    "mouthShrugUpper",  "noseSneer_L",    "noseSneer_R",
    "cheekPuff",        "cheekSquint_L",  "cheekSquint_R",
};

/** Additional scalar animation channel emitted outside the 51 blendshape array. */
static const char* const AppleCVATongueOutName = "tongue_out";

/** Current 2D landmark names exposed by AppleCVA semantics. */
static const char* const AppleCVALandmarkNames[APPLECVA_MAX_LANDMARKS] = {
    "RightEyeOuterCorner", "RightEyeInnerCorner", "RightEyeLowerOuter",
    "RightEyeLowerInner",  "RightEyeUpperOuter",  "RightEyeUpperInner",
    "RightEyePupil",       "LeftEyeOuterCorner",  "LeftEyeInnerCorner",
    "LeftEyeLowerOuter",   "LeftEyeLowerInner",   "LeftEyeUpperOuter",
    "LeftEyeUpperInner",   "LeftEyePupil",        "RightBrowOuter",
    "RightBrowMiddle",     "RightBrowInner",      "LeftBrowOuter",
    "LeftBrowMiddle",      "LeftBrowInner",       "MouthRightCorner",
    "MouthRightUp1",       "MouthRightUp2",       "MouthRightPhiltrum",
    "MouthCenterPhiltrum", "MouthLeftPhiltrum",   "MouthLeftUp2",
    "MouthLeftUp1",        "MouthLeftCorner",     "MouthLeftDown1",
    "MouthLeftDown2",      "MouthCenterLower",    "MouthRightDown2",
    "MouthRightDown1",     "MouthInnerUp",        "MouthInnerDown",
    "MouthInnerUpRight",   "MouthInnerUpLeft",    "MouthInnerDownRight",
    "MouthInnerDownLeft",  "NoseRidgeRoot",       "NoseRidge1",
    "NoseRidge2",          "NoseRidgeTip",        "NoseBaseLeft",
    "NoseBaseCenterLeft",  "NoseBaseCenter",      "NoseBaseCenterRight",
    "NoseBaseRight",       "NoseAlaLeft1",        "NoseAlaRight1",
    "NoseAlaLeft2",        "NoseAlaRight2",       "CheekRight0",
    "CheekRight1",         "CheekRight2",         "CheekRight3",
    "CheekRight4",         "CheekRight5",         "ChinCenter",
    "CheekLeft0",          "CheekLeft1",          "CheekLeft2",
    "CheekLeft3",          "CheekLeft4",          "CheekLeft5",
};

/** Opaque stateful AppleCVA tracker wrapper. */
typedef struct AppleCVATracker AppleCVATracker;

/** AppleCVA processing backend selection. */
typedef enum {
    APPLECVA_BACKEND_MODE_LITE = 0,
    APPLECVA_BACKEND_MODE_FULL = 1,
    APPLECVA_BACKEND_MODE_AUTO = 2,
} AppleCVABackendMode;

/** Tracker configuration used at creation time. */
typedef struct {
    /** Processing backend mode. */
    AppleCVABackendMode backend_mode;
} AppleCVAConfig;

/** Input face rectangle for AppleCVATrackerProcessFrame. */
typedef struct {
    /** Normalized bottom-left X. */
    float x;
    /** Normalized bottom-left Y. */
    float y;
    /** Normalized width. */
    float width;
    /** Normalized height. */
    float height;
    /** Roll angle in radians. */
    float roll;
} AppleCVADetectedFace;

/** Camera calibration block passed to AppleCVA. */
typedef struct {
    /** Row-major 3x3 camera rotation. */
    float rotation[9];
    /** Camera translation vector. */
    float translation[3];
    /** Row-major 3x3 intrinsics matrix. */
    float intrinsics[9];
} AppleCVACameraParameters;

/** Decoded data for one tracked face. */
typedef struct {
    bool valid;
    char face_id[APPLECVA_FACE_ID_CAPACITY];
    float confidence;
    int32_t confidence_level;
    int32_t failure_type;
    /** Normalized tracked rectangle: x, y, width, height. */
    float rect[4];
    float angle_roll;
    /** Preferred gaze vector, using smoothed data when available. */
    float gaze[3];
    float raw_gaze[3];
    float smooth_gaze[3];
    float left_eye[3];
    float right_eye[3];
    float left_eye_pitch;
    float left_eye_yaw;
    float right_eye_pitch;
    float right_eye_yaw;
    /** Extra tongue channel emitted outside the 51 blendshape array. */
    float tongue_out;
    float raw_rotation[9];
    float raw_translation[3];
    float smooth_rotation[9];
    float smooth_translation[3];
    float raw_blendshapes[APPLECVA_MAX_BLENDSHAPES];
    size_t raw_blendshape_count;
    /** Preferred blendshape stream, using smoothed data when available. */
    float blendshapes[APPLECVA_MAX_BLENDSHAPES];
    size_t blendshape_count;
    float smooth_blendshapes[APPLECVA_MAX_BLENDSHAPES];
    size_t smooth_blendshape_count;
    /** Pixel-space landmark pairs packed as x0, y0, x1, y1, ... */
    float landmarks[APPLECVA_MAX_LANDMARK_FLOATS];
    size_t landmark_float_count;
    size_t landmark_pair_count;
} AppleCVATrackedFace;

/** Caller-owned output storage for one processed frame. */
typedef struct {
    size_t tracked_face_capacity;
    AppleCVATrackedFace* tracked_faces;
    size_t detected_face_count;
    size_t tracked_face_count;
    size_t tracked_faces_written;
    bool tracked_faces_truncated;
    bool secondary_processing_requested;
    double timestamp_seconds;
} AppleCVAFrameResult;

/** Static semantics returned by the AppleCVA framework. */
typedef struct {
    bool valid;
    uint32_t maximum_tracked_faces;
    size_t blendshape_name_count;
    char blendshape_names[APPLECVA_MAX_BLENDSHAPES]
                         [APPLECVA_MAX_SEMANTIC_NAME_LENGTH];
    size_t landmark_name_count;
    char landmark_names[APPLECVA_MAX_LANDMARKS]
                       [APPLECVA_MAX_SEMANTIC_NAME_LENGTH];
    size_t mesh_vertex_float_count;
    float mesh_vertices[APPLECVA_MAX_MESH_VERTEX_FLOATS];
    size_t mesh_texcoord_float_count;
    float mesh_texcoords[APPLECVA_MAX_MESH_TEXCOORD_FLOATS];
    size_t mesh_quad_index_count;
    uint32_t mesh_quad_indices[APPLECVA_MAX_MESH_QUAD_INDICES];
} AppleCVASemantics;

/** Fill a config with conservative defaults. */
void AppleCVAConfigInit(AppleCVAConfig* config);

/** Build identity extrinsics and ARKit FaceTracking RGB intrinsics scaled to the frame size. */
void AppleCVAMakeDefaultCameraParameters(size_t width, size_t height,
                                         AppleCVACameraParameters* params);

/** Attach caller-owned tracked-face storage to a frame result. */
void AppleCVAFrameResultInit(AppleCVAFrameResult* result,
                             AppleCVATrackedFace* tracked_faces,
                             size_t tracked_face_capacity);

/** Clear counts and tracked-face contents while preserving the attached storage pointer. */
void AppleCVAFrameResultClear(AppleCVAFrameResult* result);

/** Clear a semantics structure. */
void AppleCVASemanticsInit(AppleCVASemantics* semantics);

/** Return a stable English string for wrapper-defined status codes. */
const char* AppleCVAStatusString(int32_t status);

/** Query AppleCVA's current maximum tracked-face count. Returns zero on bind failure. */
uint32_t AppleCVAMaximumTrackedFaces(void);

/** Copy blendshape names, landmark names, and template mesh semantics from AppleCVA. */
int32_t AppleCVACopySemantics(AppleCVASemantics* out_semantics);

/** Create a stateful AppleCVA tracker using the configured backend. */
int32_t AppleCVATrackerCreate(const AppleCVAConfig* config,
                              AppleCVATracker** out_tracker);

/** Destroy a tracker created by AppleCVATrackerCreate. */
void AppleCVATrackerDestroy(AppleCVATracker* tracker);

/**
 * Copy the raw decoded AppleCVA dictionary from the latest processed frame.
 *
 * The caller owns `*out_decoded_output` and must release it with CFRelease.
 */
int32_t
AppleCVATrackerCopyRawDecodedOutput(AppleCVATracker* tracker,
                                    CFDictionaryRef* out_decoded_output,
                                    bool* out_secondary_processing_requested);

/**
 * Process one frame through AppleCVA.
 *
 * `pixel_buffer` must be NV12 (`420f` or `420v`).
 * `detected_faces` are normalized bottom-left rectangles; the full backend
 * converts them to its required input coordinate convention internally.
 */
int32_t AppleCVATrackerProcessFrame(
    AppleCVATracker* tracker, CVPixelBufferRef pixel_buffer,
    const AppleCVACameraParameters* camera_parameters,
    const AppleCVADetectedFace* detected_faces, size_t detected_face_count,
    double timestamp_seconds, uint32_t lux_level,
    AppleCVAFrameResult* out_result);

/** Detect normalized bottom-left face rectangles with Vision. */
int32_t AppleCVADetectFacesWithVision(CVPixelBufferRef pixel_buffer,
                                      AppleCVADetectedFace* out_faces,
                                      size_t face_capacity,
                                      size_t* out_face_count);

/** Detect normalized bottom-left face rectangles with Vision and explicit CGImagePropertyOrientation. */
int32_t AppleCVADetectFacesWithVisionOrientation(
    CVPixelBufferRef pixel_buffer, uint32_t cg_image_orientation,
    AppleCVADetectedFace* out_faces, size_t face_capacity,
    size_t* out_face_count);

#ifdef __cplusplus
}
#endif // __cplusplus

#endif // APPLECVA_H
