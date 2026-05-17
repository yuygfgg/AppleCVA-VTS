#ifndef COMMON_TRACKING_UTILS_H
#define COMMON_TRACKING_UTILS_H

#include "applecva.h"

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool initialized;
    float value;
    float derivative;
} AppleCVAOneEuroScalarFilter;

typedef struct {
    float min_cutoff;
    float beta;
    float derivative_cutoff;
} AppleCVAOneEuroParameters;

typedef struct {
    bool initialized;
    bool has_timestamp;
    double previous_timestamp;
    char face_id[APPLECVA_FACE_ID_CAPACITY];
    AppleCVAOneEuroScalarFilter rect[4];
    AppleCVAOneEuroScalarFilter angle_roll;
    AppleCVAOneEuroScalarFilter gaze[3];
    AppleCVAOneEuroScalarFilter raw_gaze[3];
    AppleCVAOneEuroScalarFilter smooth_gaze[3];
    AppleCVAOneEuroScalarFilter left_eye[3];
    AppleCVAOneEuroScalarFilter right_eye[3];
    AppleCVAOneEuroScalarFilter left_eye_pitch;
    AppleCVAOneEuroScalarFilter left_eye_yaw;
    AppleCVAOneEuroScalarFilter right_eye_pitch;
    AppleCVAOneEuroScalarFilter right_eye_yaw;
    AppleCVAOneEuroScalarFilter tongue_out;
    AppleCVAOneEuroScalarFilter raw_rotation[9];
    AppleCVAOneEuroScalarFilter raw_translation[3];
    AppleCVAOneEuroScalarFilter smooth_rotation[9];
    AppleCVAOneEuroScalarFilter smooth_translation[3];
    AppleCVAOneEuroScalarFilter raw_blendshapes[APPLECVA_MAX_BLENDSHAPES];
    AppleCVAOneEuroScalarFilter blendshapes[APPLECVA_MAX_BLENDSHAPES];
    AppleCVAOneEuroScalarFilter smooth_blendshapes[APPLECVA_MAX_BLENDSHAPES];
    AppleCVAOneEuroScalarFilter landmarks[APPLECVA_MAX_LANDMARK_FLOATS];
} AppleCVAFaceOneEuroFilter;

bool AppleCVATrackedFaceHasDrawableLandmarks(const AppleCVATrackedFace* face);

bool AppleCVASelectBestTrackedFace(const AppleCVAFrameResult* result,
                                   AppleCVATrackedFace* out_face);

AppleCVAOneEuroParameters AppleCVAOneEuroParametersDefault(void);
AppleCVAOneEuroParameters
AppleCVAOneEuroParametersSanitize(AppleCVAOneEuroParameters parameters);

void AppleCVAFaceOneEuroFilterReset(AppleCVAFaceOneEuroFilter* filter);

void AppleCVAFaceOneEuroFilterApply(AppleCVAFaceOneEuroFilter* filter,
                                    AppleCVATrackedFace* face,
                                    double timestamp);
void AppleCVAFaceOneEuroFilterApplyWithParameters(
    AppleCVAFaceOneEuroFilter* filter, AppleCVATrackedFace* face,
    double timestamp, const AppleCVAOneEuroParameters* parameters);

#ifdef __cplusplus
}
#endif

#endif
