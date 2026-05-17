import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import AppleCVANative 1.0

ApplicationWindow {
    id: root
    readonly property int sidePadding: 16

    width: 1320
    height: 760
    minimumWidth: 1080
    minimumHeight: 620
    visible: true
    title: "AppleCVA VTS Source"
    color: "#15161c"

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            VTSPreview {
                id: preview
                anchors.fill: parent
                mirrorPreview: controller.mirrorPreview
                showCameraPreview: controller.showCameraPreview
                flipLandmarkY: controller.flipLandmarkY
                topLeftOrigin: controller.topLeftOrigin

                Component.onCompleted: controller.setPreviewItem(preview)
            }
        }

        Rectangle {
            Layout.preferredWidth: 360
            Layout.fillHeight: true
            color: "#f5f6fa"

            ScrollView {
                id: sideScroll
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                contentHeight: settingsColumn.implicitHeight + (root.sidePadding * 2)

                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    id: settingsColumn
                    x: root.sidePadding
                    y: root.sidePadding
                    width: Math.max(0, sideScroll.availableWidth - (root.sidePadding * 2))
                    spacing: 12

                    Label {
                        text: "AppleCVA VTS Source"
                        font.pixelSize: 20
                        font.bold: true
                        color: "#2f3138"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }

                    Button {
                        text: controller.calibrationButtonText
                        enabled: !controller.calibrationBusy
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        onClicked: controller.startCalibration()
                    }

                    Label {
                        text: controller.message
                        wrapMode: Text.WordWrap
                        color: "#2f3138"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }

                    Label {
                        text: controller.extraStatusLine
                        wrapMode: Text.WordWrap
                        color: "#666a73"
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }

                    GroupBox {
                        title: "VTS"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        ColumnLayout {
                            width: parent.width

                            GridLayout {
                                columns: 2
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0

                                Label { text: "Host" }
                                TextField {
                                    id: hostField
                                    text: controller.host
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    onEditingFinished: controller.applyConnection(hostField.text, portField.text)
                                }

                                Label { text: "Port" }
                                TextField {
                                    id: portField
                                    text: String(controller.port)
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    onEditingFinished: controller.applyConnection(hostField.text, portField.text)
                                }
                            }

                            CheckBox {
                                text: "Inject custom parameters"
                                checked: controller.includeCustomParameters
                                onToggled: controller.includeCustomParameters = checked
                            }

                            CheckBox {
                                text: "Include ARKit aliases"
                                enabled: controller.includeCustomParameters
                                checked: controller.includeARKitAliases
                                onToggled: controller.includeARKitAliases = checked
                            }

                            CheckBox {
                                text: "Fill raw ACVA blendshapes"
                                enabled: controller.includeCustomParameters
                                checked: controller.includeACVABlendshapeParameters
                                onToggled: controller.includeACVABlendshapeParameters = checked
                            }
                        }
                    }

                    GroupBox {
                        title: "Tracking"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        ColumnLayout {
                            width: parent.width

                            Label { text: "Camera" }
                            ComboBox {
                                model: controller.cameraNames
                                currentIndex: controller.cameraIndex
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                onActivated: index => controller.setCameraIndex(index)
                            }

                            Label { text: "Backend" }
                            ComboBox {
                                model: ["Lite backend", "Full backend"]
                                currentIndex: controller.useFullBackend ? 1 : 0
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                onActivated: index => controller.useFullBackend = (index === 1)
                            }

                            CheckBox {
                                text: "Use One Euro filter"
                                checked: controller.enableFilter
                                onToggled: controller.enableFilter = checked
                            }
                        }
                    }

                    GroupBox {
                        title: "One Euro"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        ColumnLayout {
                            width: parent.width

                            Label { text: "Min cutoff " + controller.oneEuroMinCutoff.toFixed(2) }
                            Slider {
                                from: 0.01
                                to: 10.0
                                value: controller.oneEuroMinCutoff
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                onMoved: controller.oneEuroMinCutoff = value
                            }

                            Label { text: "Beta " + controller.oneEuroBeta.toFixed(4) }
                            Slider {
                                from: 0.0
                                to: 0.05
                                value: controller.oneEuroBeta
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                onMoved: controller.oneEuroBeta = value
                            }

                            Label { text: "Derivative " + controller.oneEuroDerivativeCutoff.toFixed(2) }
                            Slider {
                                from: 0.01
                                to: 10.0
                                value: controller.oneEuroDerivativeCutoff
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                onMoved: controller.oneEuroDerivativeCutoff = value
                            }
                        }
                    }

                    GroupBox {
                        title: "Preview"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        ColumnLayout {
                            width: parent.width

                            CheckBox {
                                text: "Mirror preview"
                                checked: controller.mirrorPreview
                                onToggled: controller.mirrorPreview = checked
                            }

                            CheckBox {
                                text: "Show camera preview"
                                checked: controller.showCameraPreview
                                onToggled: controller.showCameraPreview = checked
                            }

                            CheckBox {
                                text: "Flip landmark Y"
                                checked: controller.flipLandmarkY
                                onToggled: controller.flipLandmarkY = checked
                            }

                            CheckBox {
                                text: "Top-left source origin"
                                checked: controller.topLeftOrigin
                                onToggled: controller.topLeftOrigin = checked
                            }
                        }
                    }

                    GroupBox {
                        title: "Status"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        GridLayout {
                            width: parent.width
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 6

                            Label { text: "FPS" }
                            Label {
                                text: controller.fps.toFixed(1)
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }

                            Label { text: "Detected" }
                            Label {
                                text: String(controller.detectedFaceCount)
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }

                            Label { text: "Tracked" }
                            Label {
                                text: String(controller.trackedFaceCount)
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }

                            Label { text: "Confidence" }
                            Label {
                                text: controller.hasFace ? controller.confidence.toFixed(3) : "-"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }

                            Label { text: "Calibration" }
                            Label {
                                text: String(controller.calibrationSampleCount) + "/" + String(controller.calibrationSampleTarget)
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                            }
                        }
                    }
                }
            }
        }
    }
}
