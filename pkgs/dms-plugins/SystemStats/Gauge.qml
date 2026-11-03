import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Widgets

Item {
    id: root

    property real value: 0
    property string label: ""
    property color color: Theme.primary

    readonly property real thickness: Math.max(4, width / 14)
    readonly property real radius: (width - thickness) / 2
    property real sweep: 360 * Math.min(1, Math.max(0, value / 100))

    implicitWidth: Math.round(Theme.fontSizeMedium * 5.5)
    implicitHeight: implicitWidth

    Behavior on sweep {
        NumberAnimation {
            duration: Theme.mediumDuration
            easing.type: Easing.OutCubic
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.15)
            strokeWidth: root.thickness

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: -90
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: -90
                sweepAngle: root.sweep
            }
        }
    }

    Column {
        anchors.centerIn: parent

        StyledText {
            text: Math.round(root.value) + "%"
            font.pixelSize: Math.round(root.width * 0.2)
            font.family: SettingsData.monoFontFamily
            font.weight: Font.Bold
            color: Theme.surfaceText
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: root.label
            font.pixelSize: Math.round(root.width * 0.14)
            font.weight: Font.Medium
            color: root.color
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
