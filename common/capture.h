#ifndef COMMON_CAPTURE_H
#define COMMON_CAPTURE_H

#include "applecva.h"

#include <CoreMedia/CoreMedia.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

bool AppleCVACaptureCopyCameraIntrinsicsFromSampleBuffer(
    CMSampleBufferRef sample_buffer, AppleCVACameraParameters* params);

void AppleCVACaptureUpdateCameraParametersFromSampleBuffer(
    CMSampleBufferRef sample_buffer, size_t width, size_t height,
    AppleCVACameraParameters* params);

#ifdef __cplusplus
}
#endif //__cplusplus

#endif // COMMON_CAPTURE_H
