import QtQuick
import qs.Common
import qs.Widgets

// The ring lights up while the participant speaks.
DankCircularImage {
    id: root

    required property var participant
    property bool showStatus: false

    readonly property bool deafened: participant.selfDeafened || participant.serverDeafened
    readonly property bool muted: participant.selfMuted || participant.serverMuted

    // The smallest rendition that is sharp at this size.
    function pick(images, pixels) {
        for (const image of images) {
            if (image.width >= pixels)
                return image.url;
        }
        return images.length > 0 ? images[images.length - 1].url : "";
    }

    imageSource: pick(participant.avatar, width * Screen.devicePixelRatio)
    fallbackIcon: "person"
    border.width: 2
    border.color: participant.speaking ? Theme.primary : "transparent"

    Rectangle {
        visible: root.showStatus && (root.muted || root.deafened)
        width: root.width * 0.5
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: -2
        color: Theme.surfaceContainer

        DankIcon {
            anchors.centerIn: parent
            name: root.deafened ? "headset_off" : "mic_off"
            size: parent.width * 0.8
            color: root.participant.serverMuted || root.participant.serverDeafened ? Theme.error : Theme.surfaceText
        }
    }
}
