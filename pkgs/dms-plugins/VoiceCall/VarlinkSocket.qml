import QtQuick
import Quickshell.Io

// A varlink connection that keeps retrying. Quickshell's Socket never retries
// after a failed attempt, so every attempt gets a new one. Each failure logs a
// warning, so the retries slow down while the server is away.
Loader {
    id: root

    required property string path
    property int minRetryInterval: 1000
    property int maxRetryInterval: 15000
    readonly property bool connected: item?.connected ?? false

    signal reply(var message)

    function send(request) {
        if (!connected)
            return false;
        item.write(JSON.stringify(request) + "\0");
        item.flush();
        return true;
    }

    sourceComponent: Socket {
        path: root.path
        connected: true
        parser: SplitParser {
            splitMarker: "\0"
            onRead: data => root.reply(JSON.parse(data))
        }
    }

    onConnectedChanged: {
        if (connected)
            retry.interval = minRetryInterval;
    }

    Timer {
        id: retry
        interval: root.minRetryInterval
        repeat: true
        running: !root.connected
        onTriggered: {
            interval = Math.min(interval * 2, root.maxRetryInterval);
            root.active = false;
            root.active = true;
        }
    }
}
