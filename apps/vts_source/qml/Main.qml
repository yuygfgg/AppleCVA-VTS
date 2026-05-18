import AppleCVANative 1.0
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ApplicationWindow {
    id: root

    readonly property int sidePadding: 20
    readonly property bool previewShortcutsEnabled: !hostField.activeFocus && !portField.activeFocus

    function toggleMirrorPreview() {
        controller.mirrorPreview = !controller.mirrorPreview;
    }

    function toggleCameraPreview() {
        controller.showCameraPreview = !controller.showCameraPreview;
    }

    function toggleLandmarkYFlip() {
        controller.flipLandmarkY = !controller.flipLandmarkY;
    }

    function toggleSourceOrigin() {
        controller.topLeftOrigin = !controller.topLeftOrigin;
    }

    function toggleOneEuroFilter() {
        controller.enableFilter = !controller.enableFilter;
    }

    width: 1320
    height: 760
    minimumWidth: 1080
    minimumHeight: 620
    visible: true
    title: "AppleCVA VTS Source"
    color: "#ffe9f0"

    PreviewShortcut {
        sequence: "X"
        onActivated: root.toggleMirrorPreview()
    }

    PreviewShortcut {
        sequence: "P"
        onActivated: root.toggleCameraPreview()
    }

    PreviewShortcut {
        sequence: "Y"
        onActivated: root.toggleLandmarkYFlip()
    }

    PreviewShortcut {
        sequence: "B"
        onActivated: root.toggleSourceOrigin()
    }

    PreviewShortcut {
        sequence: "E"
        onActivated: root.toggleOneEuroFilter()
    }

    PreviewShortcut {
        sequence: "C"
        enabled: root.previewShortcutsEnabled && !controller.calibrationBusy
        onActivated: controller.startCalibration()
    }

    // Diagonal stripes background
    Canvas {
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.fillStyle = "#ffe9f0";
            ctx.fillRect(0, 0, width, height);
            ctx.strokeStyle = "#ffdbe6";
            ctx.lineWidth = 30;
            var step = 80;
            for (var i = -height; i < width + height; i += step) {
                ctx.beginPath();
                ctx.moveTo(i, 0);
                ctx.lineTo(i - height, height);
                ctx.stroke();
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: "#ffffff"
            border.color: "#f0f0f0"
            border.width: 2
            clip: true

            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.margins: -2
                anchors.rightMargin: -4
                anchors.bottomMargin: -4
                radius: 16
                color: "#15000000"
            }

            VTSPreview {
                id: preview

                anchors.fill: parent
                anchors.margins: 4
                mirrorPreview: controller.mirrorPreview
                showCameraPreview: controller.showCameraPreview
                flipLandmarkY: controller.flipLandmarkY
                topLeftOrigin: controller.topLeftOrigin
                Component.onCompleted: controller.setPreviewItem(preview)
            }

        }

        Rectangle {
            Layout.preferredWidth: 380
            Layout.fillHeight: true
            color: "transparent"

            ScrollView {
                id: sideScroll

                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    id: settingsColumn

                    width: sideScroll.availableWidth - 16
                    x: 8
                    spacing: 16

                    Item {
                        Layout.preferredHeight: 4
                    }

                    Card {
                        title: "AppleCVA VTS Source"

                        VTSButton {
                            text: controller.calibrationButtonText
                            enabled: !controller.calibrationBusy
                            Layout.fillWidth: true
                            onClicked: controller.startCalibration()
                        }

                        Label {
                            text: controller.message
                            wrapMode: Text.WordWrap
                            color: "#5c5c5c"
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }

                        Label {
                            text: controller.extraStatusLine
                            wrapMode: Text.WordWrap
                            color: "#999999"
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }

                    }

                    Card {
                        title: "VTS Connection"

                        GridLayout {
                            columns: 2
                            Layout.fillWidth: true
                            rowSpacing: 10
                            columnSpacing: 10

                            Label {
                                text: "Host"
                                color: "#5c5c5c"
                                font.bold: true
                            }

                            VTSTextField {
                                id: hostField

                                text: controller.host
                                Layout.fillWidth: true
                                onEditingFinished: controller.applyConnection(hostField.text, portField.text)
                            }

                            Label {
                                text: "Port"
                                color: "#5c5c5c"
                                font.bold: true
                            }

                            VTSTextField {
                                id: portField

                                text: String(controller.port)
                                inputMethodHints: Qt.ImhDigitsOnly
                                Layout.fillWidth: true
                                onEditingFinished: controller.applyConnection(hostField.text, portField.text)
                            }

                        }

                        VTSToggle {
                            text: "Inject custom parameters"
                            checked: controller.includeCustomParameters
                            onToggled: controller.includeCustomParameters = checked
                            Layout.topMargin: 8
                        }

                        VTSToggle {
                            text: "Include ARKit aliases"
                            enabled: controller.includeCustomParameters
                            checked: controller.includeARKitAliases
                            onToggled: controller.includeARKitAliases = checked
                        }

                        VTSToggle {
                            text: "Fill raw ACVA blendshapes"
                            enabled: controller.includeCustomParameters
                            checked: controller.includeACVABlendshapeParameters
                            onToggled: controller.includeACVABlendshapeParameters = checked
                        }

                    }

                    Card {
                        title: "Tracking Settings"

                        Label {
                            text: "Camera"
                            color: "#5c5c5c"
                            font.bold: true
                        }

                        VTSComboBox {
                            model: controller.cameraNames
                            currentIndex: controller.cameraIndex
                            Layout.fillWidth: true
                            onActivated: (index) => {
                                return controller.setCameraIndex(index);
                            }
                        }

                        Label {
                            text: "Backend"
                            color: "#5c5c5c"
                            font.bold: true
                            Layout.topMargin: 8
                        }

                        VTSComboBox {
                            model: ["Lite backend", "Full backend", "Auto backend"]
                            currentIndex: controller.backendMode
                            Layout.fillWidth: true
                            onActivated: (index) => {
                                return controller.backendMode = index;
                            }
                        }

                    }

                    Card {
                        id: oneEuroFilterCard

                        readonly property color parameterLabelColor: controller.enableFilter ? "#5c5c5c" : "#a8a8a8"

                        title: "One Euro Filter"

                        VTSToggle {
                            text: "Use One Euro filter"
                            checked: controller.enableFilter
                            onToggled: controller.enableFilter = checked
                            Layout.topMargin: 8
                        }

                        Label {
                            text: "Min cutoff: " + controller.oneEuroMinCutoff.toFixed(2)
                            color: oneEuroFilterCard.parameterLabelColor
                        }

                        VTSSlider {
                            enabled: controller.enableFilter
                            from: 0.01
                            to: 10
                            value: controller.oneEuroMinCutoff
                            Layout.fillWidth: true
                            onMoved: controller.oneEuroMinCutoff = value
                        }

                        Label {
                            text: "Beta: " + controller.oneEuroBeta.toFixed(4)
                            color: oneEuroFilterCard.parameterLabelColor
                            Layout.topMargin: 4
                        }

                        VTSSlider {
                            enabled: controller.enableFilter
                            from: 0
                            to: 0.05
                            value: controller.oneEuroBeta
                            Layout.fillWidth: true
                            onMoved: controller.oneEuroBeta = value
                        }

                        Label {
                            text: "Derivative: " + controller.oneEuroDerivativeCutoff.toFixed(2)
                            color: oneEuroFilterCard.parameterLabelColor
                            Layout.topMargin: 4
                        }

                        VTSSlider {
                            enabled: controller.enableFilter
                            from: 0.01
                            to: 10
                            value: controller.oneEuroDerivativeCutoff
                            Layout.fillWidth: true
                            onMoved: controller.oneEuroDerivativeCutoff = value
                        }

                    }

                    Card {
                        title: "Preview Options"

                        VTSToggle {
                            text: "Mirror preview"
                            checked: controller.mirrorPreview
                            onToggled: controller.mirrorPreview = checked
                        }

                        VTSToggle {
                            text: "Show camera preview"
                            checked: controller.showCameraPreview
                            onToggled: controller.showCameraPreview = checked
                        }

                        VTSToggle {
                            text: "Flip landmark Y"
                            checked: controller.flipLandmarkY
                            onToggled: controller.flipLandmarkY = checked
                        }

                        VTSToggle {
                            text: "Top-left source origin"
                            checked: controller.topLeftOrigin
                            onToggled: controller.topLeftOrigin = checked
                        }

                    }

                    Card {
                        title: "Status"

                        GridLayout {
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 8
                            Layout.fillWidth: true

                            Label {
                                text: "FPS"
                                color: "#999999"
                            }

                            Label {
                                text: controller.fps.toFixed(1)
                                color: "#5c5c5c"
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Label {
                                text: "Detected"
                                color: "#999999"
                            }

                            Label {
                                text: String(controller.detectedFaceCount)
                                color: "#5c5c5c"
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Label {
                                text: "Tracked"
                                color: "#999999"
                            }

                            Label {
                                text: String(controller.trackedFaceCount)
                                color: "#5c5c5c"
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Label {
                                text: "Confidence"
                                color: "#999999"
                            }

                            Label {
                                text: controller.hasFace ? controller.confidence.toFixed(3) : "-"
                                color: "#5c5c5c"
                                font.bold: true
                                Layout.fillWidth: true
                            }

                            Label {
                                text: "Calibration"
                                color: "#999999"
                            }

                            Label {
                                text: String(controller.calibrationSampleCount) + "/" + String(controller.calibrationSampleTarget)
                                color: "#5c5c5c"
                                font.bold: true
                                Layout.fillWidth: true
                            }

                        }

                    }

                    Item {
                        Layout.preferredHeight: 20
                    }

                }

            }

        }

    }

    component PreviewShortcut: Shortcut {
        context: Qt.WindowShortcut
        enabled: root.previewShortcutsEnabled
        autoRepeat: false
    }

    component Card: Rectangle {
        default property alias content: layout.data
        property string title: ""

        color: "#ffffff"
        radius: 14
        border.color: "#f0f0f0"
        border.width: 1
        Layout.fillWidth: true
        implicitHeight: layout.implicitHeight + 32

        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -1
            anchors.rightMargin: -3
            anchors.bottomMargin: -3
            radius: 14
            color: "#15000000"
        }

        ColumnLayout {
            id: layout

            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Label {
                text: parent.parent.title
                font.pixelSize: 18
                font.bold: true
                color: "#5c5c5c"
                visible: parent.parent.title !== ""
                Layout.fillWidth: true
                Layout.bottomMargin: 4
            }

        }

    }

    component VTSButton: Button {
        id: btn

        contentItem: Text {
            text: btn.text
            font.pixelSize: 15
            font.bold: true
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            implicitHeight: 40
            color: btn.down ? "#3A78C4" : btn.enabled ? "#4A90E2" : "#BBD4F5"
            radius: 20
        }

    }

    component VTSToggle: Switch {
        id: sw

        indicator: Rectangle {
            implicitWidth: 44
            implicitHeight: 24
            x: sw.leftPadding
            y: parent.height / 2 - height / 2
            radius: 12
            color: sw.checked ? "#4A90E2" : "#d5d5d5"

            Rectangle {
                x: sw.checked ? parent.width - width - 2 : 2
                y: 2
                width: 20
                height: 20
                radius: 10
                color: "white"

                Behavior on x {
                    NumberAnimation {
                        duration: 150
                    }

                }

            }

        }

        contentItem: Text {
            text: sw.text
            font.pixelSize: 14
            color: "#5c5c5c"
            verticalAlignment: Text.AlignVCenter
            leftPadding: sw.indicator.width + sw.spacing
        }

    }

    component VTSTextField: TextField {
        id: tf

        color: "#5c5c5c"

        background: Rectangle {
            implicitHeight: 36
            radius: 8
            color: "#f5f6fa"
            border.color: tf.activeFocus ? "#4A90E2" : "#e0e0e0"
            border.width: 1
        }

    }

    component VTSComboBox: ComboBox {
        id: cb

        background: Rectangle {
            implicitHeight: 36
            radius: 8
            color: "#f5f6fa"
            border.color: cb.activeFocus ? "#4A90E2" : "#e0e0e0"
            border.width: 1
        }

        contentItem: Text {
            leftPadding: 12
            rightPadding: cb.indicator.width + cb.spacing
            text: cb.displayText
            font.pixelSize: 14
            color: "#5c5c5c"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

    }

    component VTSSlider: Slider {
        id: sl

        background: Rectangle {
            x: sl.leftPadding
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            implicitWidth: 200
            implicitHeight: 6
            width: sl.availableWidth
            height: implicitHeight
            radius: 3
            color: sl.enabled ? "#e0e0e0" : "#eeeeee"

            Rectangle {
                width: sl.visualPosition * parent.width
                height: parent.height
                color: sl.enabled ? "#4A90E2" : "#BBD4F5"
                radius: 3
            }

        }

        handle: Rectangle {
            x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            implicitWidth: 20
            implicitHeight: 20
            radius: 10
            color: sl.enabled ? (sl.pressed ? "#f0f0f0" : "#ffffff") : "#f8fbff"
            border.color: sl.enabled ? "#4A90E2" : "#BBD4F5"
            border.width: 2
        }

    }

}
