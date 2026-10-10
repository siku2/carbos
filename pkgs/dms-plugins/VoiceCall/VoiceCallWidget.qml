import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Like the media widget, it only takes up room while there is a call.
PluginComponent {
    id: root

    readonly property int maxAvatars: 5
    readonly property var call: client.call
    readonly property var participants: call?.participants ?? []
    readonly property int shown: Math.min(participants.length, maxAvatars)
    readonly property int hidden: participants.length - shown
    // Bar icons are sized for glyphs, which looks small on photos.
    readonly property real avatarSize: widgetThickness - Theme.spacingXS

    VoiceCallClient {
        id: client
    }

    onCallChanged: {
        setVisibilityOverride(call !== null);
        if (call === null)
            closePopout();
    }
    Component.onCompleted: setVisibilityOverride(call !== null)

    // The models are counts, so delegates survive updates and avatars do not reload.
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Repeater {
                model: root.shown

                Avatar {
                    required property int index
                    participant: root.participants[index]
                    showStatus: participant.self
                    width: root.avatarSize
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                visible: root.hidden > 0
                text: "+" + root.hidden
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            Repeater {
                model: root.shown

                Avatar {
                    required property int index
                    participant: root.participants[index]
                    showStatus: participant.self
                    width: root.avatarSize
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            StyledText {
                visible: root.hidden > 0
                text: "+" + root.hidden
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 320
    popoutHeight: Math.min(600, 120 + participants.length * (36 + Theme.spacingS))

    popoutContent: Component {
        PopoutComponent {
            headerText: root.call?.server ? `${root.call.server} #${root.call.name}` : (root.call?.name ?? "")
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.participants.length

                    ParticipantRow {
                        required property int index
                        participant: root.participants[index]
                        width: parent.width
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingM
                    topPadding: Theme.spacingS

                    DankActionButton {
                        readonly property bool muted: client.state?.muted ?? false
                        iconName: muted ? "mic_off" : "mic"
                        iconColor: muted ? Theme.error : Theme.surfaceText
                        tooltipText: muted ? "Unmute" : "Mute"
                        buttonSize: 40
                        // Below the buttons, the window edge would push it onto the cursor.
                        tooltipSide: "top"
                        onClicked: client.setMute(!muted)
                    }

                    DankActionButton {
                        readonly property bool deafened: client.state?.deafened ?? false
                        iconName: deafened ? "headset_off" : "headset"
                        iconColor: deafened ? Theme.error : Theme.surfaceText
                        tooltipText: deafened ? "Undeafen" : "Deafen"
                        buttonSize: 40
                        tooltipSide: "top"
                        onClicked: client.setDeafen(!deafened)
                    }

                    DankActionButton {
                        iconName: "call_end"
                        iconColor: Theme.error
                        tooltipText: "Leave call"
                        buttonSize: 40
                        tooltipSide: "top"
                        onClicked: client.leaveCall()
                    }
                }
            }
        }
    }
}
