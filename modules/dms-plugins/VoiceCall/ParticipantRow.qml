import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    required property var participant

    readonly property bool deafened: participant.selfDeafened || participant.serverDeafened
    readonly property bool muted: participant.selfMuted || participant.serverMuted
    readonly property bool byServer: participant.serverMuted || participant.serverDeafened

    height: 36

    Avatar {
        id: avatar
        participant: root.participant
        width: 32
        height: 32
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        anchors.left: avatar.right
        anchors.leftMargin: Theme.spacingS
        anchors.right: icons.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        text: root.participant.name
        font.weight: root.participant.self ? Font.Medium : Font.Normal
        color: Theme.surfaceText
        elide: Text.ElideRight
    }

    Row {
        id: icons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        DankIcon {
            visible: root.muted || root.deafened
            name: root.deafened ? "headset_off" : "mic_off"
            size: Theme.iconSizeSmall + 2
            color: root.byServer ? Theme.error : Theme.surfaceVariantText
        }

        // Muted for the local user only.
        DankIcon {
            visible: root.participant.locallyMuted
            name: "volume_off"
            size: Theme.iconSizeSmall + 2
            color: Theme.surfaceVariantText
        }
    }
}
