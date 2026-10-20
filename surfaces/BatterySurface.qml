pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Батарея: крупный процент, состояние, время до конца зарядки/разряда,
 * текущая мощность и ёмкость.
 */
PillSurface {
    id: root

    w: 310
    h: 356

    onOpenChanged: if (open) Battery.refreshProfile()

    Column {
        anchors.fill: parent
        anchors.margins: 16 * root.s
        spacing: 12 * root.s

        Text {
            text: "Питание"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.fsTitle * root.s
            font.weight: Font.DemiBold
        }

        Row {
            spacing: 14 * root.s
            visible: Battery.present

            Item {
                width: 92 * root.s
                height: 92 * root.s

                Canvas {
                    id: ring
                    anchors.fill: parent
                    rotation: -90
                    antialiasing: true

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var cx = width / 2, cy = height / 2;
                        var r = Math.min(width, height) / 2 - 3 * root.s;
                        var frac = Math.max(0, Math.min(1, Battery.pct / 100));

                        ctx.lineCap = "round";
                        ctx.lineWidth = 4 * root.s;

                        // трек
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                        ctx.strokeStyle = String(Theme.veilHover);
                        ctx.stroke();

                        // дуга текущего заряда
                        if (frac > 0.005) {
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, 0, 2 * Math.PI * frac);
                            ctx.strokeStyle = String(Battery.low ? Theme.danger
                                                     : (Battery.charging ? Theme.ok : Theme.accent));
                            ctx.stroke();
                        }
                    }

                    Component.onCompleted: ring.requestPaint()

                    Connections {
                        target: Battery
                        function onPctChanged() { ring.requestPaint(); }
                        function onChargingChanged() { ring.requestPaint(); }
                        function onLowChanged() { ring.requestPaint(); }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: Battery.pct + "%"
                    color: Battery.low ? Theme.danger : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 22 * root.s
                    font.weight: Font.DemiBold
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4 * root.s

                Text {
                    text: Battery.stateLabel() + (Battery.charging ? " \u26A1" : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Battery.hasTime ? Battery.timeStr : "—"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
                Text {
                    visible: Math.abs(Battery.rateW) > 0.5
                    text: (Battery.rateW > 0 ? "+" : "") + Battery.rateW.toFixed(1) + " Вт"
                    color: Battery.charging ? Theme.ok : Theme.warn
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
            }
        }

        Text {
            visible: !Battery.present
            text: "Батарея не обнаружена"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 12 * root.s
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
            visible: Battery.present
        }

        GlassCard {
            width: parent.width
            height: statsCol.implicitHeight + 2 * 12 * root.s
            visible: Battery.present
            s: root.s

            Column {
                id: statsCol
                anchors.fill: parent
                anchors.margins: 12 * root.s
                spacing: 7 * root.s

            Item {
                width: parent.width
                height: Math.max(stL.implicitHeight, stR.implicitHeight)

                Text {
                    id: stL
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Состояние"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }
                Text {
                    id: stR
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.full ? "полная" : (Battery.charging ? "зарядка" : "разрядка")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }
            }

            Item {
                width: parent.width
                height: Math.max(capL.implicitHeight, capR.implicitHeight)

                Text {
                    id: capL
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Ёмкость"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }
                Text {
                    id: capR
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.capacityWh > 0 ? Battery.capacityWh.toFixed(1) + " Вт·ч" : "—"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }
            }

            Item {
                width: parent.width
                height: Math.max(hltL.implicitHeight, hltR.implicitHeight)

                Text {
                    id: hltL
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Здоровье"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }
                Text {
                    id: hltR
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Battery.pct >= 95 && !Battery.discharging ? "отличное" : "норма"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                }
            }
        }
        }

        // ── профиль энергопотребления ──
        Column {
            width: parent.width
            spacing: 7 * root.s
            visible: Battery.hasProfiles

            SectionLabel { s: root.s; text: "ПРОФИЛЬ ПИТАНИЯ" }

            Row {
                width: parent.width
                spacing: 6 * root.s

                Repeater {
                    model: [
                        { key: "performance", label: "Максимум" },
                        { key: "balanced", label: "Баланс" },
                        { key: "power-saver", label: "Экономия" }
                    ]

                    delegate: Rectangle {
                        id: profChip

                        required property var modelData

                        property bool on: Battery.profile === profChip.modelData.key

                        width: (parent.width - 2 * 6 * root.s) / 3
                        height: 30 * root.s
                        radius: Theme.radiusS * root.s
                        color: profChip.on ? Theme.accent : Theme.veil
                        border.width: 1
                        border.color: profChip.on ? Theme.accent : Theme.border
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Text {
                            anchors.centerIn: parent
                            text: profChip.modelData.label
                            color: profChip.on ? "#111318" : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: profChip.on ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            width: parent.width - 8 * root.s
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Battery.setProfile(profChip.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
