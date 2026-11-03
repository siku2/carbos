import QtQuick
import Quickshell.Io

// Card numbers change between boots, so the card is looked up by its PCI ID.
// Without one, the first card that reports its load is used.
Item {
    id: root

    property string pciId: ""
    property string path: ""
    readonly property bool available: path !== ""
    property int usage: 0

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
            onStreamFinished: root.path = text.trim()
        }
    }

    FileView {
        id: busy
        path: root.path
        blockLoading: true
        onLoaded: root.usage = parseInt(text())
    }

    Timer {
        interval: 2000
        running: root.available
        repeat: true
        triggeredOnStart: true
        onTriggered: busy.reload()
    }
}
