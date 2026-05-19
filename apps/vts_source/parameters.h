#ifndef VTS_SOURCE_PARAMETERS_H
#define VTS_SOURCE_PARAMETERS_H

#include "applecva.h"

#import <Foundation/Foundation.h>

typedef struct {
    bool valid;
    float faceAngleX;
    float faceAngleY;
    float faceAngleZ;
    float facePositionX;
    float facePositionY;
    float facePositionZ;
    float jawOpen;
    float mouthOpen;
    float eyeOpenLeft;
    float eyeOpenRight;
    float browLeftY;
    float browRightY;
} VTSAppleCVAObservedValues;

typedef struct {
    bool valid;
    float faceAngleXZero;
    float faceAngleYZero;
    float faceAngleZZero;
    float facePositionXZero;
    float facePositionYZero;
    float facePositionZNeutral;
    float jawOpenNeutral;
    float eyeOpenLeftNeutral;
    float eyeOpenRightNeutral;
    float browLeftYNeutral;
    float browRightYNeutral;
} VTSAppleCVACalibration;

typedef struct {
    float blink;
    float eyeOpen;
    float mouthOpen;
    float mouthSmile;
    float brow;
} VTSAppleCVASensitivityParameters;

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

VTSAppleCVASensitivityParameters VTSAppleCVASensitivityParametersDefault(void);
VTSAppleCVASensitivityParameters VTSAppleCVASensitivityParametersSanitize(
    VTSAppleCVASensitivityParameters parameters);

void VTSAppleCVACalibrationInit(VTSAppleCVACalibration *calibration);
BOOL VTSAppleCVAObservedValuesFromFace(const AppleCVATrackedFace *face,
                                       BOOL faceFound,
                                       VTSAppleCVAObservedValues *outValues);
void VTSAppleCVACalibrationFromObservedSamples(
    const VTSAppleCVAObservedValues *samples, size_t sampleCount,
    VTSAppleCVACalibration *outCalibration);

NSArray<NSDictionary *> *
VTSAppleCVACustomParameterDefinitions(BOOL includeARKitAliases,
                                      BOOL includeACVABlendshapeParameters,
                                      NSSet<NSString *> *availableDefaults);

NSArray<NSDictionary *> *VTSAppleCVAParameterValues(
    const AppleCVATrackedFace *face, BOOL faceFound,
    NSSet<NSString *> *availableDefaultParameters,
    const VTSAppleCVACalibration *calibration,
    const VTSAppleCVASensitivityParameters *sensitivityParameters,
    BOOL includeCustomParameters, BOOL includeARKitAliases,
    BOOL includeACVABlendshapeParameters);

#ifdef __cplusplus
}
#endif // __cplusplus

#endif // VTS_SOURCE_PARAMETERS_H
