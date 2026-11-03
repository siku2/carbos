import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Modules.ProcessList
import qs.Widgets

Item {
    id: root

    property var stats: []
    property string searchText: ""
    property string expandedPid: ""

    implicitHeight: Math.round(Theme.fontSizeMedium * 39)

    ProcessContextMenu {
        id: contextMenu
        parentFocusItem: root
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Repeater {
                model: root.stats.length

                Gauge {
                    required property int index
                    readonly property var stat: root.stats[index]
                    value: stat.value
                    label: stat.label
                    color: [Theme.primary, Theme.warning, Theme.error][stat.level]
                }
            }

            Item {
                Layout.fillWidth: true
            }

            DankTextField {
                Layout.preferredWidth: Theme.fontSizeMedium * 14
                Layout.preferredHeight: Theme.fontSizeMedium * 2.5
                placeholderText: "Search..."
                leftIconName: "search"
                showClearButton: true
                onTextChanged: root.searchText = text
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.cornerRadius
            color: Theme.nestedSurface
            clip: true

            ProcessesView {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                searchText: root.searchText
                expandedPid: root.expandedPid
                contextMenu: contextMenu
                onExpandedPidChanged: root.expandedPid = expandedPid
            }
        }
    }
}
