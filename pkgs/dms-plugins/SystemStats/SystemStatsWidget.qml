import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Appears once a value goes above 80% and stays until all are below 50%, so
// it does not flicker while a value hovers around the threshold.
PluginComponent {
    id: root

    readonly property var stats: {
        const result = [stat("CPU", "memory", DgopService.cpuUsage), stat("RAM", "developer_board", DgopService.memoryUsage)];
        if (gpu.available)
            result.push(stat("GPU", "auto_awesome_mosaic", gpu.usage));
        return result;
    }
    readonly property real peak: Math.max(...stats.map(s => s.value))
    property bool active: false

    readonly property real textSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)

    function stat(label, icon, value) {
        return {
            label,
            icon,
            value,
            level: value > 80 ? 2 : value > 60 ? 1 : 0
        };
    }

    function iconColor(level) {
        return [Theme.widgetIconColor, Theme.tempWarning, Theme.tempDanger][level];
    }

    onPeakChanged: {
        if (peak > 80)
            active = true;
        else if (peak < 50)
            active = false;
    }
    onActiveChanged: setVisibilityOverride(active)

    Component.onCompleted: {
        DgopService.addRef(["cpu", "memory"]);
        setVisibilityOverride(active);
    }
    Component.onDestruction: DgopService.removeRef(["cpu", "memory"])

    GpuBusy {
        id: gpu
        pciId: root.pluginData.pciId ?? ""
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Repeater {
                model: root.stats.length

                Row {
                    required property int index
                    readonly property var stat: root.stats[index]
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter

                    DankIcon {
                        name: stat.icon
                        size: root.iconSizeLarge
                        color: root.iconColor(stat.level)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        // Keeps the pill from changing width with the values.
                        width: Math.max(implicitWidth, baseline.width)
                        text: Math.round(stat.value) + "%"
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
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingS

            Repeater {
                model: root.stats.length

                Column {
                    required property int index
                    readonly property var stat: root.stats[index]
                    spacing: 1
                    anchors.horizontalCenter: parent.horizontalCenter

                    DankIcon {
                        name: stat.icon
                        size: root.iconSizeLarge
                        color: root.iconColor(stat.level)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: Math.round(stat.value)
                        font.pixelSize: root.textSize
                        color: Theme.widgetTextColor
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    popoutWidth: Math.round(Theme.fontSizeMedium * 46)

    popoutContent: Component {
        StatsPopout {
            stats: root.stats
        }
    }
}
