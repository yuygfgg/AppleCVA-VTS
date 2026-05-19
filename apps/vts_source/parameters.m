#import "parameters.h"

#include <math.h>
#include <string.h>

static const size_t kVTSMaxCustomParameters = 100;
static const float kVTSSensitivityDefault = 50.0f;

// Currently not default parameter, but a lot of models use it.
// Will be default parameter in the future?
static const char *const kSpecialVTSParameterNames[] = {
    "EyeSmileLeft",
    "EyeSmileRight",
    "BlushWhenSmiling",
};

static const char *const kCustomBlendshapeNames[APPLECVA_MAX_BLENDSHAPES] = {
    "ACVAEyeBlinkLeft",       "ACVAEyeBlinkRight",
    "ACVAEyeSquintLeft",      "ACVAEyeSquintRight",
    "ACVAEyeLookDownLeft",    "ACVAEyeLookDownRight",
    "ACVAEyeLookInLeft",      "ACVAEyeLookInRight",
    "ACVAEyeWideLeft",        "ACVAEyeWideRight",
    "ACVAEyeLookOutLeft",     "ACVAEyeLookOutRight",
    "ACVAEyeLookUpLeft",      "ACVAEyeLookUpRight",
    "ACVABrowDownLeft",       "ACVABrowDownRight",
    "ACVABrowInnerUp",        "ACVABrowOuterUpLeft",
    "ACVABrowOuterUpRight",   "ACVAJawOpen",
    "ACVAMouthClose",         "ACVAJawLeft",
    "ACVAJawRight",           "ACVAJawForward",
    "ACVAMouthUpperUpLeft",   "ACVAMouthUpperUpRight",
    "ACVAMouthLowerDownLeft", "ACVAMouthLowerDownRight",
    "ACVAMouthRollUpper",     "ACVAMouthRollLower",
    "ACVAMouthSmileLeft",     "ACVAMouthSmileRight",
    "ACVAMouthDimpleLeft",    "ACVAMouthDimpleRight",
    "ACVAMouthStretchLeft",   "ACVAMouthStretchRight",
    "ACVAMouthFrownLeft",     "ACVAMouthFrownRight",
    "ACVAMouthPressLeft",     "ACVAMouthPressRight",
    "ACVAMouthPucker",        "ACVAMouthFunnel",
    "ACVAMouthLeft",          "ACVAMouthRight",
    "ACVAMouthShrugLower",    "ACVAMouthShrugUpper",
    "ACVANoseSneerLeft",      "ACVANoseSneerRight",
    "ACVACheekPuff",          "ACVACheekSquintLeft",
    "ACVACheekSquintRight",
};

typedef struct {
    size_t blendshapeIndex;
    const char *name;
} VTSAppleCVAIndexedParameterName;

static const VTSAppleCVAIndexedParameterName kARKitAliasParameters[] = {
    {0, "EyeBlinkLeft"},        {1, "EyeBlinkRight"},
    {2, "EyeSquintLeft"},       {3, "EyeSquintRight"},
    {4, "EyeLookDownLeft"},     {5, "EyeLookDownRight"},
    {6, "EyeLookInLeft"},       {7, "EyeLookInRight"},
    {8, "EyeWideLeft"},         {9, "EyeWideRight"},
    {10, "EyeLookOutLeft"},     {11, "EyeLookOutRight"},
    {12, "EyeLookUpLeft"},      {13, "EyeLookUpRight"},
    {14, "BrowDownLeft"},       {15, "BrowDownRight"},
    {16, "BrowInnerUp"},        {17, "BrowOuterUpLeft"},
    {18, "BrowOuterUpRight"},   {19, "JawOpen"},
    {20, "MouthClose"},         {21, "JawLeft"},
    {22, "JawRight"},           {23, "JawForward"},
    {24, "MouthUpperUpLeft"},   {25, "MouthUpperUpRight"},
    {26, "MouthLowerDownLeft"}, {27, "MouthLowerDownRight"},
    {28, "MouthRollUpper"},     {29, "MouthRollLower"},
    {30, "MouthSmileLeft"},     {31, "MouthSmileRight"},
    {32, "MouthDimpleLeft"},    {33, "MouthDimpleRight"},
    {34, "MouthStretchLeft"},   {35, "MouthStretchRight"},
    {36, "MouthFrownLeft"},     {37, "MouthFrownRight"},
    {38, "MouthPressLeft"},     {39, "MouthPressRight"},
    {40, "MouthPucker"},        {41, "MouthFunnel"},
    {42, "MouthLeft"},          {43, "MouthRight"},
    {44, "MouthShrugLower"},    {45, "MouthShrugUpper"},
    {46, "NoseSneerLeft"},      {47, "NoseSneerRight"},
    {48, "CheekPuff"},          {49, "CheekSquintLeft"},
    {50, "CheekSquintRight"},
};

#define ARRAY_COUNT(values) (sizeof(values) / sizeof((values)[0]))

static BOOL parameter_name_is_default(NSString *name,
                                      NSSet<NSString *> *availableDefaults) {
    return name != nil && [availableDefaults containsObject:name];
}

static size_t
arkit_alias_custom_parameter_count(BOOL includeARKitAliases,
                                   NSSet<NSString *> *availableDefaults) {
    if (!includeARKitAliases) {
        return 0;
    }
    size_t count = 0;
    for (size_t i = 0; i < ARRAY_COUNT(kARKitAliasParameters); ++i) {
        NSString *name =
            [NSString stringWithUTF8String:kARKitAliasParameters[i].name];
        if (!parameter_name_is_default(name, availableDefaults)) {
            ++count;
        }
    }
    return count;
}

static size_t
acva_blendshape_parameter_count(BOOL includeARKitAliases,
                                BOOL includeACVABlendshapeParameters,
                                NSSet<NSString *> *availableDefaults) {
    if (!includeACVABlendshapeParameters) {
        return 0;
    }
    const size_t derivedACVAParameterCount = 17;
    size_t specialCustomCount = 0;
    for (size_t i = 0; i < ARRAY_COUNT(kSpecialVTSParameterNames); ++i) {
        NSString *name =
            [NSString stringWithUTF8String:kSpecialVTSParameterNames[i]];
        if (!parameter_name_is_default(name, availableDefaults)) {
            ++specialCustomCount;
        }
    }
    const size_t aliasCustomCount = arkit_alias_custom_parameter_count(
        includeARKitAliases, availableDefaults);
    const size_t reserved =
        derivedACVAParameterCount + specialCustomCount + aliasCustomCount;
    if (reserved >= kVTSMaxCustomParameters) {
        return 0;
    }
    const size_t available = kVTSMaxCustomParameters - reserved;
    return APPLECVA_MAX_BLENDSHAPES < available ? APPLECVA_MAX_BLENDSHAPES
                                                : available;
}

static void log_dropped_acva_blendshape_parameters(size_t includedCount) {
    if (includedCount >= APPLECVA_MAX_BLENDSHAPES) {
        return;
    }

    NSMutableArray<NSString *> *dropped = [NSMutableArray array];
    for (size_t i = includedCount; i < APPLECVA_MAX_BLENDSHAPES; ++i) {
        [dropped addObject:[NSString
                               stringWithUTF8String:kCustomBlendshapeNames[i]]];
    }
    NSLog(@"WARNING: VTS custom parameter slots exhausted; skipped %lu raw "
          @"ACVA blendshape parameters: %@",
          (unsigned long)dropped.count,
          [dropped componentsJoinedByString:@", "]);
}

typedef struct {
    float x;
    float y;
} AppleCVALandmarkPoint;

typedef enum {
    VTSAppleCVABlendshapeEyeBlinkLeft = 0,
    VTSAppleCVABlendshapeEyeBlinkRight = 1,
    VTSAppleCVABlendshapeEyeSquintLeft = 2,
    VTSAppleCVABlendshapeEyeSquintRight = 3,
    VTSAppleCVABlendshapeEyeWideLeft = 8,
    VTSAppleCVABlendshapeEyeWideRight = 9,
    VTSAppleCVABlendshapeBrowDownLeft = 14,
    VTSAppleCVABlendshapeBrowDownRight = 15,
    VTSAppleCVABlendshapeBrowInnerUp = 16,
    VTSAppleCVABlendshapeBrowOuterUpLeft = 17,
    VTSAppleCVABlendshapeBrowOuterUpRight = 18,
    VTSAppleCVABlendshapeJawOpen = 19,
    VTSAppleCVABlendshapeMouthClose = 20,
    VTSAppleCVABlendshapeMouthSmileLeft = 30,
    VTSAppleCVABlendshapeMouthSmileRight = 31,
    VTSAppleCVABlendshapeMouthFrownLeft = 36,
    VTSAppleCVABlendshapeMouthFrownRight = 37,
    VTSAppleCVABlendshapeMouthLeft = 42,
    VTSAppleCVABlendshapeMouthRight = 43,
    VTSAppleCVABlendshapeCheekPuff = 48,
    VTSAppleCVABlendshapeCheekSquintLeft = 49,
    VTSAppleCVABlendshapeCheekSquintRight = 50,
} VTSAppleCVABlendshapeIndex;

typedef enum {
    VTSAppleCVALandmarkRightEyeOuterCorner = 0,
    VTSAppleCVALandmarkRightEyeInnerCorner = 1,
    VTSAppleCVALandmarkRightEyeLowerOuter = 2,
    VTSAppleCVALandmarkRightEyeLowerInner = 3,
    VTSAppleCVALandmarkRightEyeUpperOuter = 4,
    VTSAppleCVALandmarkRightEyeUpperInner = 5,
    VTSAppleCVALandmarkLeftEyeOuterCorner = 7,
    VTSAppleCVALandmarkLeftEyeInnerCorner = 8,
    VTSAppleCVALandmarkLeftEyeLowerOuter = 9,
    VTSAppleCVALandmarkLeftEyeLowerInner = 10,
    VTSAppleCVALandmarkLeftEyeUpperOuter = 11,
    VTSAppleCVALandmarkLeftEyeUpperInner = 12,
    VTSAppleCVALandmarkNoseRidgeTip = 43,
    VTSAppleCVALandmarkChinCenter = 59,
} VTSAppleCVALandmarkIndex;

static float clampf(float value, float minimum, float maximum) {
    if (!isfinite(value)) {
        return 0.0f;
    }
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

static float clamp01(float value) { return clampf(value, 0.0f, 1.0f); }

static float clamp_sensitivity(float value) {
    if (!isfinite(value)) {
        return kVTSSensitivityDefault;
    }
    return clampf(value, 0.0f, 100.0f);
}

static float sensitivity_gain(float sensitivity) {
    return clamp_sensitivity(sensitivity) / kVTSSensitivityDefault;
}

VTSAppleCVASensitivityParameters VTSAppleCVASensitivityParametersDefault(void) {
    VTSAppleCVASensitivityParameters parameters = {
        kVTSSensitivityDefault, kVTSSensitivityDefault, kVTSSensitivityDefault,
        kVTSSensitivityDefault, kVTSSensitivityDefault,
    };
    return parameters;
}

VTSAppleCVASensitivityParameters VTSAppleCVASensitivityParametersSanitize(
    VTSAppleCVASensitivityParameters parameters) {
    parameters.blink = clamp_sensitivity(parameters.blink);
    parameters.eyeOpen = clamp_sensitivity(parameters.eyeOpen);
    parameters.mouthOpen = clamp_sensitivity(parameters.mouthOpen);
    parameters.mouthSmile = clamp_sensitivity(parameters.mouthSmile);
    parameters.brow = clamp_sensitivity(parameters.brow);
    return parameters;
}

static float apply_zero_based_sensitivity(float value, float sensitivity) {
    return clamp01(value * sensitivity_gain(sensitivity));
}

static float apply_centered_sensitivity(float value, float center,
                                        float sensitivity, float minimum,
                                        float maximum) {
    return clampf(center + ((value - center) * sensitivity_gain(sensitivity)),
                  minimum, maximum);
}

static float remap_clamped(float value, float inputMinimum, float inputMaximum,
                           float outputMinimum, float outputMaximum) {
    if (!isfinite(value) || inputMaximum == inputMinimum) {
        return outputMinimum;
    }
    const float t =
        clamp01((value - inputMinimum) / (inputMaximum - inputMinimum));
    return outputMinimum + ((outputMaximum - outputMinimum) * t);
}

static NSNumber *json_float(float value) {
    if (!isfinite(value)) {
        value = 0.0f;
    }
    return @(value);
}

static NSDictionary *parameter_definition(NSString *name, NSString *explanation,
                                          float minimum, float maximum,
                                          float defaultValue) {
    return @{
        @"parameterName" : name,
        @"explanation" : explanation,
        @"min" : @(minimum),
        @"max" : @(maximum),
        @"defaultValue" : @(defaultValue),
    };
}

static NSDictionary *parameter_value(NSString *id, float value) {
    return @{
        @"id" : id,
        @"value" : json_float(value),
        @"weight" : @1.0,
    };
}

static BOOL matrix_has_signal(const float values[9]) {
    for (size_t i = 0; i < 9; ++i) {
        if (isfinite(values[i]) && fabsf(values[i]) > 0.000001f) {
            return YES;
        }
    }
    return NO;
}

static void rotation_matrix_to_degrees(const float values[9], float *outPitch,
                                       float *outYaw, float *outRoll) {
    /*
     * AppleCVA's face pose matrix is emitted in the opposite convention from
     * the standard row-major ZYX extraction used by ARKit/VTS consumers.
     */
    const float sy = sqrtf((values[0] * values[0]) + (values[1] * values[1]));
    const BOOL singular = sy < 1e-6f;
    float pitch = 0.0f;
    float yaw = 0.0f;
    float roll = 0.0f;

    if (!singular) {
        pitch = atan2f(values[5], values[8]);
        yaw = atan2f(-values[2], sy);
        roll = atan2f(values[1], values[0]);
    } else {
        pitch = atan2f(-values[7], values[4]);
        yaw = atan2f(-values[2], sy);
        roll = 0.0f;
    }

    const float radiansToDegrees = 180.0f / (float)M_PI;
    *outPitch = pitch * radiansToDegrees;
    *outYaw = yaw * radiansToDegrees;
    *outRoll = roll * radiansToDegrees;
}

static BOOL landmark_point(const AppleCVATrackedFace *face, size_t index,
                           AppleCVALandmarkPoint *outPoint) {
    if (face == NULL || outPoint == NULL ||
        index >= face->landmark_pair_count || index >= APPLECVA_MAX_LANDMARKS) {
        return NO;
    }
    const size_t base = index * 2;
    if (base + 1 >= face->landmark_float_count ||
        base + 1 >= APPLECVA_MAX_LANDMARK_FLOATS) {
        return NO;
    }
    const float x = face->landmarks[base];
    const float y = face->landmarks[base + 1];
    if (!isfinite(x) || !isfinite(y)) {
        return NO;
    }
    outPoint->x = x;
    outPoint->y = y;
    return YES;
}

static AppleCVALandmarkPoint midpoint(AppleCVALandmarkPoint a,
                                      AppleCVALandmarkPoint b) {
    return (AppleCVALandmarkPoint){
        .x = (a.x + b.x) * 0.5f,
        .y = (a.y + b.y) * 0.5f,
    };
}

static float landmark_distance(AppleCVALandmarkPoint a,
                               AppleCVALandmarkPoint b) {
    const float dx = a.x - b.x;
    const float dy = a.y - b.y;
    return sqrtf((dx * dx) + (dy * dy));
}

static BOOL landmark_pair_midpoint(const AppleCVATrackedFace *face,
                                   size_t aIndex, size_t bIndex,
                                   AppleCVALandmarkPoint *outPoint) {
    AppleCVALandmarkPoint a;
    AppleCVALandmarkPoint b;
    if (!landmark_point(face, aIndex, &a) ||
        !landmark_point(face, bIndex, &b)) {
        return NO;
    }
    *outPoint = midpoint(a, b);
    return YES;
}

static float landmark_pitch_degrees(const AppleCVATrackedFace *face) {
    AppleCVALandmarkPoint rightEye;
    AppleCVALandmarkPoint leftEye;
    AppleCVALandmarkPoint noseTip;
    AppleCVALandmarkPoint chin;
    if (!landmark_pair_midpoint(face, VTSAppleCVALandmarkRightEyeOuterCorner,
                                VTSAppleCVALandmarkRightEyeInnerCorner,
                                &rightEye) ||
        !landmark_pair_midpoint(face, VTSAppleCVALandmarkLeftEyeOuterCorner,
                                VTSAppleCVALandmarkLeftEyeInnerCorner,
                                &leftEye) ||
        !landmark_point(face, VTSAppleCVALandmarkNoseRidgeTip, &noseTip) ||
        !landmark_point(face, VTSAppleCVALandmarkChinCenter, &chin)) {
        return NAN;
    }

    const AppleCVALandmarkPoint eyeCenter = midpoint(rightEye, leftEye);
    const float eyeToChin = chin.y - eyeCenter.y;
    const float eyeToNose = noseTip.y - eyeCenter.y;
    if (fabsf(eyeToChin) < 1.0f) {
        return NAN;
    }

    const float ratio = eyeToNose / eyeToChin;
    const float neutralRatio = 0.38f;
    float pitch = (neutralRatio - ratio) * 220.0f;
    if (fabsf(pitch) < 1.5f) {
        pitch = 0.0f;
    }
    return clampf(pitch, -45.0f, 45.0f);
}

static void face_rotation(const AppleCVATrackedFace *face, float *outPitch,
                          float *outYaw, float *outRoll) {
    *outPitch = 0.0f;
    *outYaw = 0.0f;
    *outRoll = 0.0f;
    if (face == NULL) {
        return;
    }

    const float *rotation = matrix_has_signal(face->smooth_rotation)
                                ? face->smooth_rotation
                                : face->raw_rotation;
    if (matrix_has_signal(rotation)) {
        rotation_matrix_to_degrees(rotation, outPitch, outYaw, outRoll);
    } else if (isfinite(face->angle_roll)) {
        *outRoll = face->angle_roll * (180.0f / (float)M_PI);
    }

    const float landmarkPitch = landmark_pitch_degrees(face);
    if (isfinite(landmarkPitch)) {
        *outPitch = landmarkPitch;
    }
}

static BOOL face_rect_values(const AppleCVATrackedFace *face, float *outCenterX,
                             float *outCenterY, float *outSize) {
    if (face == NULL) {
        return NO;
    }

    const float x = face->rect[0];
    const float y = face->rect[1];
    const float width = face->rect[2];
    const float height = face->rect[3];
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        width <= 0.0f || height <= 0.0f) {
        return NO;
    }

    if (outCenterX != NULL) {
        *outCenterX = x + (width * 0.5f);
    }
    if (outCenterY != NULL) {
        *outCenterY = y + (height * 0.5f);
    }
    if (outSize != NULL) {
        *outSize = sqrtf(width * height);
    }
    return YES;
}

static void
calibrated_face_position_values(const AppleCVATrackedFace *face,
                                const VTSAppleCVACalibration *calibration,
                                float *outX, float *outY, float *outZ) {
    if (outX != NULL) {
        *outX = 0.0f;
    }
    if (outY != NULL) {
        *outY = 0.0f;
    }
    if (outZ != NULL) {
        *outZ = 0.0f;
    }
    if (face == NULL || calibration == NULL || !calibration->valid) {
        return;
    }

    float centerX = 0.0f;
    float centerY = 0.0f;
    float size = 0.0f;
    if (!face_rect_values(face, &centerX, &centerY, &size)) {
        return;
    }

    if (outX != NULL) {
        *outX = clampf((centerX - calibration->facePositionXZero) * 20.0f,
                       -10.0f, 10.0f);
    }
    if (outY != NULL) {
        *outY = clampf((centerY - calibration->facePositionYZero) * 20.0f,
                       -10.0f, 10.0f);
    }
    if (outZ != NULL && calibration->facePositionZNeutral > 0.0001f) {
        *outZ =
            clampf((1.0f - (size / calibration->facePositionZNeutral)) * 10.0f,
                   -10.0f, 10.0f);
    }
}

static float blendshape_at(const AppleCVATrackedFace *face, size_t index) {
    if (face == NULL || index >= face->blendshape_count ||
        index >= APPLECVA_MAX_BLENDSHAPES) {
        return 0.0f;
    }
    return clamp01(face->blendshapes[index]);
}

static float
adjusted_blendshape_value(const AppleCVATrackedFace *face,
                          size_t blendshapeIndex,
                          const VTSAppleCVASensitivityParameters *sensitivity) {
    const float value = blendshape_at(face, blendshapeIndex);
    if (sensitivity == NULL) {
        return value;
    }
    switch (blendshapeIndex) {
    case VTSAppleCVABlendshapeEyeBlinkLeft:
    case VTSAppleCVABlendshapeEyeBlinkRight:
        return apply_zero_based_sensitivity(value, sensitivity->blink);
    case VTSAppleCVABlendshapeEyeWideLeft:
    case VTSAppleCVABlendshapeEyeWideRight:
        return apply_zero_based_sensitivity(value, sensitivity->eyeOpen);
    case VTSAppleCVABlendshapeBrowDownLeft:
    case VTSAppleCVABlendshapeBrowDownRight:
    case VTSAppleCVABlendshapeBrowInnerUp:
    case VTSAppleCVABlendshapeBrowOuterUpLeft:
    case VTSAppleCVABlendshapeBrowOuterUpRight:
        return apply_zero_based_sensitivity(value, sensitivity->brow);
    case VTSAppleCVABlendshapeJawOpen:
        return apply_zero_based_sensitivity(value, sensitivity->mouthOpen);
    case VTSAppleCVABlendshapeMouthSmileLeft:
    case VTSAppleCVABlendshapeMouthSmileRight:
        return apply_zero_based_sensitivity(value, sensitivity->mouthSmile);
    default:
        return value;
    }
}

static float eye_open_from_landmarks(const AppleCVATrackedFace *face,
                                     BOOL leftEye) {
    const size_t outerIndex = leftEye ? VTSAppleCVALandmarkLeftEyeOuterCorner
                                      : VTSAppleCVALandmarkRightEyeOuterCorner;
    const size_t innerIndex = leftEye ? VTSAppleCVALandmarkLeftEyeInnerCorner
                                      : VTSAppleCVALandmarkRightEyeInnerCorner;
    const size_t lowerOuterIndex = leftEye
                                       ? VTSAppleCVALandmarkLeftEyeLowerOuter
                                       : VTSAppleCVALandmarkRightEyeLowerOuter;
    const size_t lowerInnerIndex = leftEye
                                       ? VTSAppleCVALandmarkLeftEyeLowerInner
                                       : VTSAppleCVALandmarkRightEyeLowerInner;
    const size_t upperOuterIndex = leftEye
                                       ? VTSAppleCVALandmarkLeftEyeUpperOuter
                                       : VTSAppleCVALandmarkRightEyeUpperOuter;
    const size_t upperInnerIndex = leftEye
                                       ? VTSAppleCVALandmarkLeftEyeUpperInner
                                       : VTSAppleCVALandmarkRightEyeUpperInner;

    AppleCVALandmarkPoint outer;
    AppleCVALandmarkPoint inner;
    AppleCVALandmarkPoint lowerOuter;
    AppleCVALandmarkPoint lowerInner;
    AppleCVALandmarkPoint upperOuter;
    AppleCVALandmarkPoint upperInner;
    if (!landmark_point(face, outerIndex, &outer) ||
        !landmark_point(face, innerIndex, &inner) ||
        !landmark_point(face, lowerOuterIndex, &lowerOuter) ||
        !landmark_point(face, lowerInnerIndex, &lowerInner) ||
        !landmark_point(face, upperOuterIndex, &upperOuter) ||
        !landmark_point(face, upperInnerIndex, &upperInner)) {
        return NAN;
    }

    const float width = landmark_distance(outer, inner);
    if (width < 1.0f) {
        return NAN;
    }
    const float outerAperture = landmark_distance(upperOuter, lowerOuter);
    const float innerAperture = landmark_distance(upperInner, lowerInner);
    const float ratio = ((outerAperture + innerAperture) * 0.5f) / width;
    return remap_clamped(ratio, 0.03f, 0.19f, 0.0f, 1.0f);
}

static float eye_open_measurement(const AppleCVATrackedFace *face,
                                  BOOL leftEye) {
    if (face == NULL) {
        return 1.0f;
    }

    const size_t blinkIndex = leftEye ? VTSAppleCVABlendshapeEyeBlinkLeft
                                      : VTSAppleCVABlendshapeEyeBlinkRight;
    const size_t wideIndex = leftEye ? VTSAppleCVABlendshapeEyeWideLeft
                                     : VTSAppleCVABlendshapeEyeWideRight;
    const float blinkClosed = remap_clamped(blendshape_at(face, blinkIndex),
                                            0.06f, 0.45f, 0.0f, 1.0f);
    const float blendOpen = 1.0f - blinkClosed;
    const float landmarkOpen = eye_open_from_landmarks(face, leftEye);
    float value =
        isfinite(landmarkOpen) ? fminf(landmarkOpen, blendOpen) : blendOpen;
    if (blinkClosed < 0.2f) {
        value += blendshape_at(face, wideIndex) * 0.15f;
    }
    return clamp01(value);
}

static float
eye_open_value(const AppleCVATrackedFace *face, BOOL leftEye,
               const VTSAppleCVACalibration *calibration,
               const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 1.0f;
    }
    const float value = eye_open_measurement(face, leftEye);
    if (sensitivity == NULL) {
        return value;
    }

    float neutral = 1.0f;
    if (calibration != NULL && calibration->valid) {
        neutral = leftEye ? calibration->eyeOpenLeftNeutral
                          : calibration->eyeOpenRightNeutral;
        neutral = clampf(neutral, 0.05f, 1.0f);
    }
    if (value < neutral) {
        return apply_centered_sensitivity(value, neutral, sensitivity->blink,
                                          0.0f, 1.0f);
    }
    return apply_centered_sensitivity(value, neutral, sensitivity->eyeOpen,
                                      0.0f, 1.0f);
}

static float eye_narrowing_value(const AppleCVATrackedFace *face, BOOL leftEye,
                                 const VTSAppleCVACalibration *calibration) {
    if (face == NULL) {
        return 0.0f;
    }

    float neutral = 1.0f;
    if (calibration != NULL && calibration->valid) {
        neutral = leftEye ? calibration->eyeOpenLeftNeutral
                          : calibration->eyeOpenRightNeutral;
        neutral = clampf(neutral, 0.05f, 1.0f);
    }

    const float measurement = eye_open_measurement(face, leftEye);
    const float narrowing = clamp01(neutral - measurement);
    const float scale = fmaxf(0.12f, neutral * 0.35f);
    return remap_clamped(narrowing, 0.03f, scale, 0.0f, 1.0f);
}

static float mouth_open_value(const AppleCVATrackedFace *face) {
    if (face == NULL) {
        return 0.0f;
    }
    return blendshape_at(face, VTSAppleCVABlendshapeJawOpen);
}

static float calibrated_mouth_open_value(
    const AppleCVATrackedFace *face, const VTSAppleCVACalibration *calibration,
    const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }
    if (calibration == NULL || !calibration->valid) {
        return 0.0f;
    }
    const float openStart =
        clampf(calibration->jawOpenNeutral + 0.08f, 0.0f, 0.95f);
    float mouthOpen =
        remap_clamped(blendshape_at(face, VTSAppleCVABlendshapeJawOpen),
                      openStart, 1.0f, 0.0f, 1.0f);

    const float mouthClose =
        blendshape_at(face, VTSAppleCVABlendshapeMouthClose);
    if (mouthClose > 0.2f) {
        mouthOpen *= 1.0f - remap_clamped(mouthClose, 0.2f, 0.8f, 0.0f, 1.0f);
    }
    return apply_zero_based_sensitivity(
        mouthOpen,
        sensitivity != NULL ? sensitivity->mouthOpen : kVTSSensitivityDefault);
}

static float brow_y_value(const AppleCVATrackedFace *face, BOOL leftBrow,
                          const VTSAppleCVACalibration *calibration,
                          const VTSAppleCVASensitivityParameters *sensitivity);

void VTSAppleCVACalibrationInit(VTSAppleCVACalibration *calibration) {
    if (calibration != NULL) {
        memset(calibration, 0, sizeof(*calibration));
    }
}

BOOL VTSAppleCVAObservedValuesFromFace(const AppleCVATrackedFace *face,
                                       BOOL faceFound,
                                       VTSAppleCVAObservedValues *outValues) {
    if (outValues == NULL) {
        return NO;
    }
    memset(outValues, 0, sizeof(*outValues));
    if (!faceFound || face == NULL) {
        return NO;
    }

    float pitch = 0.0f;
    float yaw = 0.0f;
    float roll = 0.0f;
    face_rotation(face, &pitch, &yaw, &roll);

    outValues->valid = true;
    outValues->faceAngleX = clampf(-yaw, -45.0f, 45.0f);
    outValues->faceAngleY = clampf(pitch, -45.0f, 45.0f);
    outValues->faceAngleZ = clampf(roll, -45.0f, 45.0f);
    face_rect_values(face, &outValues->facePositionX, &outValues->facePositionY,
                     &outValues->facePositionZ);
    outValues->jawOpen = blendshape_at(face, VTSAppleCVABlendshapeJawOpen);
    outValues->mouthOpen = mouth_open_value(face);
    outValues->eyeOpenLeft = eye_open_value(face, YES, NULL, NULL);
    outValues->eyeOpenRight = eye_open_value(face, NO, NULL, NULL);
    outValues->browLeftY = brow_y_value(face, YES, NULL, NULL);
    outValues->browRightY = brow_y_value(face, NO, NULL, NULL);
    return YES;
}

void VTSAppleCVACalibrationFromObservedSamples(
    const VTSAppleCVAObservedValues *samples, size_t sampleCount,
    VTSAppleCVACalibration *outCalibration) {
    if (outCalibration == NULL) {
        return;
    }
    VTSAppleCVACalibrationInit(outCalibration);
    if (samples == NULL || sampleCount == 0) {
        return;
    }

    size_t count = 0;
    VTSAppleCVACalibration sum;
    VTSAppleCVACalibrationInit(&sum);
    for (size_t i = 0; i < sampleCount; ++i) {
        if (!samples[i].valid) {
            continue;
        }
        sum.faceAngleXZero += samples[i].faceAngleX;
        sum.faceAngleYZero += samples[i].faceAngleY;
        sum.faceAngleZZero += samples[i].faceAngleZ;
        sum.facePositionXZero += samples[i].facePositionX;
        sum.facePositionYZero += samples[i].facePositionY;
        sum.facePositionZNeutral += samples[i].facePositionZ;
        sum.jawOpenNeutral += samples[i].jawOpen;
        sum.eyeOpenLeftNeutral += samples[i].eyeOpenLeft;
        sum.eyeOpenRightNeutral += samples[i].eyeOpenRight;
        sum.browLeftYNeutral += samples[i].browLeftY;
        sum.browRightYNeutral += samples[i].browRightY;
        ++count;
    }
    if (count == 0) {
        return;
    }

    const float scale = 1.0f / (float)count;
    outCalibration->valid = true;
    outCalibration->faceAngleXZero = sum.faceAngleXZero * scale;
    outCalibration->faceAngleYZero = sum.faceAngleYZero * scale;
    outCalibration->faceAngleZZero = sum.faceAngleZZero * scale;
    outCalibration->facePositionXZero = sum.facePositionXZero * scale;
    outCalibration->facePositionYZero = sum.facePositionYZero * scale;
    outCalibration->facePositionZNeutral = sum.facePositionZNeutral * scale;
    outCalibration->jawOpenNeutral = sum.jawOpenNeutral * scale;
    outCalibration->eyeOpenLeftNeutral = sum.eyeOpenLeftNeutral * scale;
    outCalibration->eyeOpenRightNeutral = sum.eyeOpenRightNeutral * scale;
    outCalibration->browLeftYNeutral = sum.browLeftYNeutral * scale;
    outCalibration->browRightYNeutral = sum.browRightYNeutral * scale;
}

static float
mouth_smile_side_value(const AppleCVATrackedFace *face, BOOL leftSide,
                       const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }
    const size_t smileIndex = leftSide ? VTSAppleCVABlendshapeMouthSmileLeft
                                       : VTSAppleCVABlendshapeMouthSmileRight;
    const size_t frownIndex = leftSide ? VTSAppleCVABlendshapeMouthFrownLeft
                                       : VTSAppleCVABlendshapeMouthFrownRight;
    const float smile = blendshape_at(face, smileIndex);
    const float frown = blendshape_at(face, frownIndex);
    return apply_zero_based_sensitivity(
        smile - (frown * 0.35f),
        sensitivity != NULL ? sensitivity->mouthSmile : kVTSSensitivityDefault);
}

static float
mouth_smile_value(const AppleCVATrackedFace *face,
                  const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }
    const float smile =
        (blendshape_at(face, VTSAppleCVABlendshapeMouthSmileLeft) +
         blendshape_at(face, VTSAppleCVABlendshapeMouthSmileRight)) *
        0.5f;
    const float frown =
        (blendshape_at(face, VTSAppleCVABlendshapeMouthFrownLeft) +
         blendshape_at(face, VTSAppleCVABlendshapeMouthFrownRight)) *
        0.5f;
    return apply_zero_based_sensitivity(
        smile - (frown * 0.35f),
        sensitivity != NULL ? sensitivity->mouthSmile : kVTSSensitivityDefault);
}

static float
eye_smile_value(const AppleCVATrackedFace *face, BOOL leftEye,
                const VTSAppleCVACalibration *calibration,
                const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }

    const size_t eyeSquintIndex = leftEye ? VTSAppleCVABlendshapeEyeSquintLeft
                                          : VTSAppleCVABlendshapeEyeSquintRight;
    const size_t cheekSquintIndex = leftEye
                                        ? VTSAppleCVABlendshapeCheekSquintLeft
                                        : VTSAppleCVABlendshapeCheekSquintRight;
    const size_t mouthFrownIndex = leftEye
                                       ? VTSAppleCVABlendshapeMouthFrownLeft
                                       : VTSAppleCVABlendshapeMouthFrownRight;
    const size_t browDownIndex = leftEye ? VTSAppleCVABlendshapeBrowDownLeft
                                         : VTSAppleCVABlendshapeBrowDownRight;
    const size_t blinkIndex = leftEye ? VTSAppleCVABlendshapeEyeBlinkLeft
                                      : VTSAppleCVABlendshapeEyeBlinkRight;
    const float mouthSmile = mouth_smile_side_value(face, leftEye, sensitivity);
    const float eyeSquint = blendshape_at(face, eyeSquintIndex);
    const float cheekSquint = blendshape_at(face, cheekSquintIndex);
    const float mouthFrown = blendshape_at(face, mouthFrownIndex);
    const float browDown = blendshape_at(face, browDownIndex);
    const float blink = blendshape_at(face, blinkIndex);
    const float narrowing = eye_narrowing_value(face, leftEye, calibration);
    const float smileGate = remap_clamped(mouthSmile, 0.08f, 0.62f, 0.0f, 1.0f);
    const float eyeGate = remap_clamped(
        (eyeSquint * 0.45f) + (cheekSquint * 0.35f) + (narrowing * 0.20f),
        0.10f, 0.55f, 0.0f, 1.0f);
    const float browPenalty =
        1.0f - remap_clamped(browDown, 0.15f, 0.65f, 0.0f, 0.90f);
    const float blinkPenalty =
        1.0f - remap_clamped(blink, 0.55f, 0.92f, 0.0f, 1.0f);
    const float frownPenalty =
        1.0f - remap_clamped(mouthFrown, 0.08f, 0.45f, 0.0f, 0.85f);
    return clamp01(smileGate * eyeGate * browPenalty * blinkPenalty *
                   frownPenalty);
}

static float blush_when_smiling_value(float mouthSmile) {
    return clamp01(mouthSmile);
}

static float mouth_x_value(const AppleCVATrackedFace *face) {
    if (face == NULL) {
        return 0.0f;
    }
    return clampf(blendshape_at(face, VTSAppleCVABlendshapeMouthRight) -
                      blendshape_at(face, VTSAppleCVABlendshapeMouthLeft),
                  -1.0f, 1.0f);
}

static float brow_y_value(const AppleCVATrackedFace *face, BOOL leftBrow,
                          const VTSAppleCVACalibration *calibration,
                          const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.5f;
    }
    const float browDown =
        blendshape_at(face, leftBrow ? VTSAppleCVABlendshapeBrowDownLeft
                                     : VTSAppleCVABlendshapeBrowDownRight);
    const float outerUp =
        blendshape_at(face, leftBrow ? VTSAppleCVABlendshapeBrowOuterUpLeft
                                     : VTSAppleCVABlendshapeBrowOuterUpRight);
    const float innerUp = blendshape_at(face, VTSAppleCVABlendshapeBrowInnerUp);
    const float value =
        clamp01(0.5f + (((outerUp + innerUp) * 0.5f - browDown) * 0.5f));
    float neutral = 0.5f;
    if (calibration != NULL && calibration->valid) {
        neutral = leftBrow ? calibration->browLeftYNeutral
                           : calibration->browRightYNeutral;
        neutral = clamp01(neutral);
    }
    return apply_centered_sensitivity(
        value, neutral,
        sensitivity != NULL ? sensitivity->brow : kVTSSensitivityDefault, 0.0f,
        1.0f);
}

static float eye_degrees_to_vts(float radians) {
    if (!isfinite(radians)) {
        return 0.0f;
    }
    return clampf(radians * (180.0f / (float)M_PI) / 30.0f, -1.0f, 1.0f);
}

static void add_default_parameter(NSMutableArray *values,
                                  NSSet<NSString *> *availableDefaults,
                                  NSString *name, float value) {
    if ([availableDefaults containsObject:name]) {
        [values addObject:parameter_value(name, value)];
    }
}

NSArray<NSDictionary *> *
VTSAppleCVACustomParameterDefinitions(BOOL includeARKitAliases,
                                      BOOL includeACVABlendshapeParameters,
                                      NSSet<NSString *> *availableDefaults) {
    NSMutableArray *definitions =
        [NSMutableArray arrayWithCapacity:kVTSMaxCustomParameters];
    [definitions addObject:parameter_definition(@"ACVATongueOut",
                                                @"AppleCVA tongue out channel",
                                                0.0f, 1.0f, 0.0f)];
    [definitions addObject:parameter_definition(@"ACVAFaceAngleX",
                                                @"AppleCVA face yaw in degrees",
                                                -45.0f, 45.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAFaceAngleY",
                                       @"AppleCVA face pitch in degrees",
                                       -45.0f, 45.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAFaceAngleZ",
                                       @"AppleCVA face roll in degrees", -45.0f,
                                       45.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAFacePositionX",
                                       @"AppleCVA calibrated face X position",
                                       -10.0f, 10.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAFacePositionY",
                                       @"AppleCVA calibrated face Y position",
                                       -10.0f, 10.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAFacePositionZ",
                                       @"AppleCVA calibrated face Z position",
                                       -10.0f, 10.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAEyeLeftX",
                                       @"AppleCVA left eye yaw in degrees",
                                       -45.0f, 45.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAEyeLeftY",
                                       @"AppleCVA left eye pitch in degrees",
                                       -45.0f, 45.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAEyeRightX",
                                       @"AppleCVA right eye yaw in degrees",
                                       -45.0f, 45.0f, 0.0f)];
    [definitions
        addObject:parameter_definition(@"ACVAEyeRightY",
                                       @"AppleCVA right eye pitch in degrees",
                                       -45.0f, 45.0f, 0.0f)];
    [definitions addObject:parameter_definition(
                               @"ACVAEyeOpenLeft",
                               @"AppleCVA landmark-derived left eye open", 0.0f,
                               1.0f, 1.0f)];
    [definitions addObject:parameter_definition(
                               @"ACVAEyeOpenRight",
                               @"AppleCVA landmark-derived right eye open",
                               0.0f, 1.0f, 1.0f)];
    [definitions addObject:parameter_definition(@"ACVAMouthSmile",
                                                @"AppleCVA mouth smile", 0.0f,
                                                1.0f, 0.0f)];
    [definitions addObject:parameter_definition(@"ACVAMouthX",
                                                @"AppleCVA mouth X offset",
                                                -1.0f, 1.0f, 0.0f)];
    [definitions addObject:parameter_definition(@"ACVABrowLeftY",
                                                @"AppleCVA left brow height",
                                                0.0f, 1.0f, 0.5f)];
    [definitions addObject:parameter_definition(@"ACVABrowRightY",
                                                @"AppleCVA right brow height",
                                                0.0f, 1.0f, 0.5f)];
    if (!parameter_name_is_default(@"EyeSmileLeft", availableDefaults)) {
        [definitions
            addObject:parameter_definition(@"EyeSmileLeft",
                                           @"AppleCVA derived left eye smile",
                                           0.0f, 1.0f, 0.0f)];
    }
    if (!parameter_name_is_default(@"EyeSmileRight", availableDefaults)) {
        [definitions
            addObject:parameter_definition(@"EyeSmileRight",
                                           @"AppleCVA derived right eye smile",
                                           0.0f, 1.0f, 0.0f)];
    }
    if (!parameter_name_is_default(@"BlushWhenSmiling", availableDefaults)) {
        [definitions addObject:parameter_definition(
                                   @"BlushWhenSmiling",
                                   @"AppleCVA smile-driven blush amount", 0.0f,
                                   1.0f, 0.0f)];
    }
    if (includeARKitAliases) {
        for (size_t i = 0; i < ARRAY_COUNT(kARKitAliasParameters); ++i) {
            const VTSAppleCVAIndexedParameterName alias =
                kARKitAliasParameters[i];
            NSString *name = [NSString stringWithUTF8String:alias.name];
            if (parameter_name_is_default(name, availableDefaults)) {
                continue;
            }
            NSString *explanation = [NSString
                stringWithFormat:@"AppleCVA ARKit alias for %s",
                                 AppleCVABlendshapeNames[alias
                                                             .blendshapeIndex]];
            [definitions addObject:parameter_definition(name, explanation, 0.0f,
                                                        1.0f, 0.0f)];
        }
    }
    const size_t acvaBlendshapeCount = acva_blendshape_parameter_count(
        includeARKitAliases, includeACVABlendshapeParameters,
        availableDefaults);
    if (includeACVABlendshapeParameters) {
        log_dropped_acva_blendshape_parameters(acvaBlendshapeCount);
    }
    for (size_t i = 0; i < acvaBlendshapeCount; ++i) {
        NSString *name =
            [NSString stringWithUTF8String:kCustomBlendshapeNames[i]];
        NSString *explanation =
            [NSString stringWithFormat:@"AppleCVA ARKit channel %s",
                                       AppleCVABlendshapeNames[i]];
        [definitions addObject:parameter_definition(name, explanation, 0.0f,
                                                    1.0f, 0.0f)];
    }
    return definitions;
}

NSArray<NSDictionary *> *VTSAppleCVAParameterValues(
    const AppleCVATrackedFace *face, BOOL faceFound,
    NSSet<NSString *> *availableDefaultParameters,
    const VTSAppleCVACalibration *calibration,
    const VTSAppleCVASensitivityParameters *sensitivityParameters,
    BOOL includeCustomParameters, BOOL includeARKitAliases,
    BOOL includeACVABlendshapeParameters) {
    if (!faceFound) {
        face = NULL;
    }

    VTSAppleCVASensitivityParameters sensitivity =
        VTSAppleCVASensitivityParametersDefault();
    if (sensitivityParameters != NULL) {
        sensitivity =
            VTSAppleCVASensitivityParametersSanitize(*sensitivityParameters);
    }

    NSMutableArray *values =
        [NSMutableArray arrayWithCapacity:APPLECVA_MAX_BLENDSHAPES + 64];

    VTSAppleCVAObservedValues observed;
    VTSAppleCVAObservedValuesFromFace(face, face != NULL, &observed);
    float yaw = observed.faceAngleX;
    float pitch = observed.faceAngleY;
    float roll = observed.faceAngleZ;
    if (calibration != NULL && calibration->valid) {
        yaw -= calibration->faceAngleXZero;
        pitch -= calibration->faceAngleYZero;
        roll -= calibration->faceAngleZZero;
    }
    yaw = clampf(yaw, -45.0f, 45.0f);
    pitch = clampf(pitch * 1.35f, -45.0f, 45.0f);
    roll = clampf(roll, -45.0f, 45.0f);
    float facePositionX = 0.0f;
    float facePositionY = 0.0f;
    float facePositionZ = 0.0f;
    calibrated_face_position_values(face, calibration, &facePositionX,
                                    &facePositionY, &facePositionZ);
    const float eyeOpenLeft =
        eye_open_value(face, YES, calibration, &sensitivity);
    const float eyeOpenRight =
        eye_open_value(face, NO, calibration, &sensitivity);
    const float mouthOpen =
        calibrated_mouth_open_value(face, calibration, &sensitivity);
    const float mouthSmile = mouth_smile_value(face, &sensitivity);
    const float eyeSmileLeft =
        eye_smile_value(face, YES, calibration, &sensitivity);
    const float eyeSmileRight =
        eye_smile_value(face, NO, calibration, &sensitivity);
    const float blushWhenSmiling = blush_when_smiling_value(mouthSmile);
    const float mouthX = mouth_x_value(face);
    const float browLeftY = brow_y_value(face, YES, calibration, &sensitivity);
    const float browRightY = brow_y_value(face, NO, calibration, &sensitivity);
    const float eyeLeftX =
        face != NULL ? eye_degrees_to_vts(face->left_eye_yaw) : 0.0f;
    const float eyeLeftY =
        face != NULL ? eye_degrees_to_vts(face->left_eye_pitch) : 0.0f;
    const float eyeRightX =
        face != NULL ? eye_degrees_to_vts(face->right_eye_yaw) : 0.0f;
    const float eyeRightY =
        face != NULL ? eye_degrees_to_vts(face->right_eye_pitch) : 0.0f;

    if (availableDefaultParameters != nil) {
        add_default_parameter(values, availableDefaultParameters, @"FaceAngleX",
                              yaw);
        add_default_parameter(values, availableDefaultParameters, @"FaceAngleY",
                              pitch);
        add_default_parameter(values, availableDefaultParameters, @"FaceAngleZ",
                              roll);
        add_default_parameter(values, availableDefaultParameters,
                              @"FacePositionX", facePositionX);
        add_default_parameter(values, availableDefaultParameters,
                              @"FacePositionY", facePositionY);
        add_default_parameter(values, availableDefaultParameters,
                              @"FacePositionZ", facePositionZ);
        add_default_parameter(values, availableDefaultParameters,
                              @"EyeOpenLeft", eyeOpenLeft);
        add_default_parameter(values, availableDefaultParameters,
                              @"EyeOpenRight", eyeOpenRight);
        add_default_parameter(values, availableDefaultParameters, @"EyeLeftX",
                              eyeLeftX);
        add_default_parameter(values, availableDefaultParameters, @"EyeLeftY",
                              eyeLeftY);
        add_default_parameter(values, availableDefaultParameters, @"EyeRightX",
                              eyeRightX);
        add_default_parameter(values, availableDefaultParameters, @"EyeRightY",
                              eyeRightY);
        add_default_parameter(values, availableDefaultParameters, @"MouthOpen",
                              mouthOpen);
        add_default_parameter(values, availableDefaultParameters, @"MouthSmile",
                              mouthSmile);
        add_default_parameter(values, availableDefaultParameters,
                              @"EyeSmileLeft", eyeSmileLeft);
        add_default_parameter(values, availableDefaultParameters,
                              @"EyeSmileRight", eyeSmileRight);
        add_default_parameter(values, availableDefaultParameters,
                              @"BlushWhenSmiling", blushWhenSmiling);
        add_default_parameter(values, availableDefaultParameters, @"MouthX",
                              mouthX);
        add_default_parameter(values, availableDefaultParameters, @"Brows",
                              (browLeftY + browRightY) * 0.5f);
        add_default_parameter(values, availableDefaultParameters, @"BrowLeftY",
                              browLeftY);
        add_default_parameter(values, availableDefaultParameters, @"BrowRightY",
                              browRightY);
        add_default_parameter(values, availableDefaultParameters, @"TongueOut",
                              face != NULL ? clamp01(face->tongue_out) : 0.0f);
        if (!includeCustomParameters || !includeARKitAliases) {
            add_default_parameter(
                values, availableDefaultParameters, @"CheekPuff",
                blendshape_at(face, VTSAppleCVABlendshapeCheekPuff));
        }
    }

    if (!includeCustomParameters) {
        return values;
    }

    if (!parameter_name_is_default(@"EyeSmileLeft",
                                   availableDefaultParameters)) {
        [values addObject:parameter_value(@"EyeSmileLeft", eyeSmileLeft)];
    }
    if (!parameter_name_is_default(@"EyeSmileRight",
                                   availableDefaultParameters)) {
        [values addObject:parameter_value(@"EyeSmileRight", eyeSmileRight)];
    }
    if (!parameter_name_is_default(@"BlushWhenSmiling",
                                   availableDefaultParameters)) {
        [values
            addObject:parameter_value(@"BlushWhenSmiling", blushWhenSmiling)];
    }

    if (includeARKitAliases) {
        for (size_t i = 0; i < ARRAY_COUNT(kARKitAliasParameters); ++i) {
            const VTSAppleCVAIndexedParameterName alias =
                kARKitAliasParameters[i];
            NSString *name = [NSString stringWithUTF8String:alias.name];
            [values
                addObject:parameter_value(name, adjusted_blendshape_value(
                                                    face, alias.blendshapeIndex,
                                                    &sensitivity))];
        }
    }

    const size_t acvaBlendshapeCount = acva_blendshape_parameter_count(
        includeARKitAliases, includeACVABlendshapeParameters,
        availableDefaultParameters);
    for (size_t i = 0; i < acvaBlendshapeCount; ++i) {
        NSString *name =
            [NSString stringWithUTF8String:kCustomBlendshapeNames[i]];
        [values addObject:parameter_value(name, blendshape_at(face, i))];
    }
    [values addObject:parameter_value(@"ACVATongueOut",
                                      face != NULL ? clamp01(face->tongue_out)
                                                   : 0.0f)];
    [values addObject:parameter_value(@"ACVAFaceAngleX", yaw)];
    [values addObject:parameter_value(@"ACVAFaceAngleY", pitch)];
    [values addObject:parameter_value(@"ACVAFaceAngleZ", roll)];
    [values addObject:parameter_value(@"ACVAFacePositionX", facePositionX)];
    [values addObject:parameter_value(@"ACVAFacePositionY", facePositionY)];
    [values addObject:parameter_value(@"ACVAFacePositionZ", facePositionZ)];
    [values addObject:parameter_value(@"ACVAEyeLeftX",
                                      face != NULL
                                          ? clampf(face->left_eye_yaw * 180.0f /
                                                       (float)M_PI,
                                                   -45.0f, 45.0f)
                                          : 0.0f)];
    [values addObject:parameter_value(@"ACVAEyeLeftY",
                                      face != NULL
                                          ? clampf(face->left_eye_pitch *
                                                       180.0f / (float)M_PI,
                                                   -45.0f, 45.0f)
                                          : 0.0f)];
    [values addObject:parameter_value(@"ACVAEyeRightX",
                                      face != NULL
                                          ? clampf(face->right_eye_yaw *
                                                       180.0f / (float)M_PI,
                                                   -45.0f, 45.0f)
                                          : 0.0f)];
    [values addObject:parameter_value(@"ACVAEyeRightY",
                                      face != NULL
                                          ? clampf(face->right_eye_pitch *
                                                       180.0f / (float)M_PI,
                                                   -45.0f, 45.0f)
                                          : 0.0f)];
    [values addObject:parameter_value(@"ACVAEyeOpenLeft", eyeOpenLeft)];
    [values addObject:parameter_value(@"ACVAEyeOpenRight", eyeOpenRight)];
    [values addObject:parameter_value(@"ACVAMouthSmile", mouthSmile)];
    [values addObject:parameter_value(@"ACVAMouthX", mouthX)];
    [values addObject:parameter_value(@"ACVABrowLeftY", browLeftY)];
    [values addObject:parameter_value(@"ACVABrowRightY", browRightY)];
    return values;
}
