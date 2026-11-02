import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Card numbers change between boots, so the card is looked up by its PCI ID.
// Without one, the first card that reports its load is used.
PluginComponent {
    id: root

    readonly property string pciId: pluginData.pciId ?? ""
    property string busyPath: ""
    property int usage: -1

    readonly property color iconColor: usage > 80 ? Theme.tempDanger : usage > 60 ? Theme.tempWarning : Theme.widgetIconColor
    readonly property real textSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)

    onPciIdChanged: finder.running = true
    Component.onCompleted: finder.running = true

    Process {
        id: finder
        command: ["sh", "-c", `
            for d in /sys/class/drm/card*/device; do
                [ -r "$d/gpu_busy_percent" ] || continue
                id="$(sed s/^0x// "$d/vendor"):$(sed s/^0x// "$d/device")"
                if [ -z "$1" ] || [ "$id" = "$1" ]; then
                    echo "$d/gpu_busy_percent"
                    exit
                fi
            done`, "sh", root.pciId]
        stdout: StdioCollector {
            onStreamFinished: root.busyPath = text.trim()
        }
    }

    FileView {
        id: busy
        path: root.busyPath
        blockLoading: true
        onLoaded: root.usage = parseInt(text())
    }

    Timer {
        interval: 2000
        running: root.busyPath !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: busy.reload()
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "auto_awesome_mosaic"
                size: root.iconSizeLarge
                color: root.iconColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                // Keeps the pill from changing width with the value.
                width: Math.max(implicitWidth, baseline.width)
                text: root.usage < 0 ? "--%" : root.usage + "%"
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter

                StyledTextMetrics {
                    id: baseline
                    font.pixelSize: root.textSize
                    text: "88%"
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 1

            DankIcon {
                name: "auto_awesome_mosaic"
                size: root.iconSizeLarge
                color: root.iconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.usage < 0 ? "--" : root.usage
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
