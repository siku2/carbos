import QtQuick
import Quickshell

// Follows io.siku2.VoiceCall, which the VoiceCallBridge Vencord plugin serves
// while Vesktop runs.
Item {
    id: root

    readonly property string path: Quickshell.env("XDG_RUNTIME_DIR") + "/io.siku2.VoiceCall"
    // The State type of the interface. Null while the bridge is not running.
    property var state: null
    readonly property var call: state?.call ?? null

    function setMute(muted) {
        command("SetMute", {
            muted: muted
        });
    }

    function setDeafen(deafened) {
        command("SetDeafen", {
            deafened: deafened
        });
    }

    // With the id, a click on a stale widget cannot leave a newer call.
    function leaveCall() {
        if (call)
            command("LeaveCall", {
                id: call.id
            });
    }

    function command(method, parameters) {
        const request = {
            method: "io.siku2.VoiceCall." + method,
            parameters: parameters
        };
        if (!commands.send(request))
            console.warn("VoiceCall: not connected, dropped", method);
    }

    function logError(message) {
        if (message.error)
            console.warn("VoiceCall:", message.error, JSON.stringify(message.parameters));
    }

    VarlinkSocket {
        path: root.path
        onConnectedChanged: {
            if (connected)
                send({
                    method: "io.siku2.VoiceCall.Watch",
                    more: true
                });
            else
                root.state = null;
        }
        onReply: message => {
            if (message.error)
                root.logError(message);
            else
                root.state = message.parameters.state;
        }
    }

    // Varlink answers one request at a time per connection, and Watch never
    // ends, so commands need a connection of their own.
    VarlinkSocket {
        id: commands
        path: root.path
        onReply: message => root.logError(message)
    }
}
