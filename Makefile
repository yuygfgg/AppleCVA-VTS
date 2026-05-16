CC := clang
BUILD_DIR := build
COMMON_WARNINGS := -Wall -Wextra
OBJC_ARC := -fobjc-arc
INCLUDES := -Iinclude
APPLECVA_FRAMEWORKS := -framework Foundation -framework Vision -framework CoreFoundation -framework CoreGraphics -framework CoreVideo -framework ImageIO
CAMERA_VIEWER_FRAMEWORKS := $(APPLECVA_FRAMEWORKS) -framework AppKit -framework AVFoundation -framework CoreMedia -framework CoreImage -framework QuartzCore

LIB_TARGET := $(BUILD_DIR)/libapplecva.dylib
SEMANTICS_PROBE_TARGET := $(BUILD_DIR)/semantics_probe
CAMERA_VIEWER_TARGET := $(BUILD_DIR)/camera_viewer

.PHONY: all clean

all: $(LIB_TARGET) $(SEMANTICS_PROBE_TARGET) $(CAMERA_VIEWER_TARGET)

$(BUILD_DIR):
	mkdir -p $@

$(LIB_TARGET): lib/applecva.m include/applecva.h | $(BUILD_DIR)
	$(CC) $(COMMON_WARNINGS) $(OBJC_ARC) $(INCLUDES) -dynamiclib lib/applecva.m $(APPLECVA_FRAMEWORKS) -o $@

$(SEMANTICS_PROBE_TARGET): tools/semantics_probe.m | $(BUILD_DIR)
	$(CC) $(COMMON_WARNINGS) $(OBJC_ARC) tools/semantics_probe.m -framework Foundation -framework CoreFoundation -o $@

$(CAMERA_VIEWER_TARGET): lib/applecva.m include/applecva.h example/camera_viewer.m example/CameraViewerInfo.plist | $(BUILD_DIR)
	$(CC) $(COMMON_WARNINGS) $(OBJC_ARC) $(INCLUDES) lib/applecva.m example/camera_viewer.m $(CAMERA_VIEWER_FRAMEWORKS) -sectcreate __TEXT __info_plist example/CameraViewerInfo.plist -o $@

clean:
	rm -rf $(BUILD_DIR)
