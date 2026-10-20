pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Bluetooth: тумблер питания, автопоиск при открытии и список устройств.
 * Клик: подключённое — панель отключить/забыть; сопряжённое — подключить;
 * найденное — сопряжение (pair → trust → connect).
 */
PillSurface {
    id: root

    w: 350
    h: 470

    property string expandedMac: ""

    onOpenChanged: {
        if (open) {
            expandedMac = "";
            BT.refresh();
            // поиск запускается автоматически при открытии
            if (BT.powered && !BT.scanning) BT.startScan();
        } else {
            BT.stopScan();
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16 * root.s
        spacing: 10 * root.s

        // ── заголовок с тумблером питания ──
        Row {
            width: parent.width
            spacing: 8 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Bluetooth"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fsTitle * root.s
                font.weight: Font.DemiBold
            }

            Item { width: parent.width - 160 * root.s; height: 1 }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: BT.powered ? "вкл" : "выкл"
                color: BT.powered ? Theme.ok : Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
            }

            ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                on: BT.powered
                onToggled: BT.togglePower()
            }
        }

        // ── строка сканирования ──
        Rectangle {
            width: parent.width
            height: 32 * root.s
            radius: Theme.radiusS * root.s
            color: scanArea.containsMouse ? Theme.veilHover : Theme.veil

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10 * root.s
                anchors.rightMargin: 10 * root.s
                spacing: 8 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14 * root.s
                    height: 14 * root.s
                    name: "search"
                    color: BT.scanning ? Theme.accent : Theme.dim

                    SequentialAnimation on opacity {
                        running: BT.scanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 22 * root.s
                    text: BT.scanning ? "Поиск устройств… (нажать — стоп)"
                                      : (BT.devices.length + " устройств(а) — найти новые")
                    color: BT.scanning ? Theme.accent : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: scanArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: BT.scanning ? BT.stopScan() : BT.startScan()
            }
        }

        // ── список устройств ──
        Item {
            width: parent.width
            height: parent.height - 17 * root.s - 30 * root.s - 2 * 10 * root.s
                    - (BT.busy ? 22 * root.s : 0)

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 6 * root.s
                model: BT.devices
                boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: dev

                required property var modelData
                required property int index

                width: list.width
                height: devCol.implicitHeight + 2 * 5 * root.s
                radius: Theme.radiusM * root.s
                color: devArea.containsMouse || root.expandedMac === dev.modelData.mac
                       ? Theme.veilHover : Theme.veil
                border.width: root.expandedMac === dev.modelData.mac ? 1 : 0
                border.color: Theme.accentDim

                // клик-зона объявлена ДО контента: кнопки панели действий
                // остаются поверх и получают свои клики
                MouseArea {
                    id: devArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (dev.modelData.connected) {
                            root.expandedMac = root.expandedMac === dev.modelData.mac
                                    ? "" : dev.modelData.mac;
                        } else if (dev.modelData.paired) {
                            BT.connect(dev.modelData.mac);
                        } else {
                            BT.pairAndConnect(dev.modelData.mac);
                        }
                    }
                }

                Column {
                    id: devCol
                    anchors.fill: parent
                    anchors.margins: 4 * root.s

                    Row {
                        width: parent.width
                        height: 26 * root.s
                        spacing: 9 * root.s

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 9 * root.s
                            height: 9 * root.s
                            radius: width / 2
                            color: dev.modelData.connected ? Theme.ok
                                 : dev.modelData.paired ? Theme.accent : "transparent"
                            border.width: 1
                            border.color: dev.modelData.connected ? Theme.ok
                                        : dev.modelData.paired ? Theme.accent : Theme.faint
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 92 * root.s
                            text: dev.modelData.name.length ? dev.modelData.name : dev.modelData.mac
                            color: dev.modelData.connected ? Theme.text : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64 * root.s
                            text: dev.modelData.connected ? "подключено"
                                 : dev.modelData.paired ? "сопряжено" : "найдено"
                            color: dev.modelData.connected ? Theme.ok : Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // ── панель действий подключённого/сопряжённого ──
                    Row {
                        visible: root.expandedMac === dev.modelData.mac
                        width: parent.width
                        height: visible ? 28 * root.s : 0
                        spacing: 6 * root.s

                        Rectangle {
                            width: parent.width / 2 - 3 * root.s
                            height: 28 * root.s
                            radius: 8 * root.s
                            color: discArea.containsMouse ? Theme.accentDim : Theme.veil

                            Text {
                                anchors.centerIn: parent
                                text: "Отключить"
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                            }

                            MouseArea {
                                id: discArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    BT.disconnect(dev.modelData.mac);
                                    root.expandedMac = "";
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width / 2 - 3 * root.s
                            height: 28 * root.s
                            radius: 8 * root.s
                            color: remArea.containsMouse ? Theme.danger : Theme.veil

                            Text {
                                anchors.centerIn: parent
                                text: "Забыть"
                                color: remArea.containsMouse ? "#111318" : Theme.danger
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                            }

                            MouseArea {
                                id: remArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    BT.remove(dev.modelData.mac);
                                    root.expandedMac = "";
                                }
                            }
                        }
                    }
                }
            }

            }

            SlimScroll {
                flick: list
                s: root.s
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }

            EmptyState {
                anchors.centerIn: parent
                visible: BT.devices.length === 0
                s: root.s
                icon: "bt"
                title: BT.powered ? "Нет устройств" : "Bluetooth выключен"
                hint: BT.powered ? "включи поиск или сопряги заново" : ""
            }
        }

        Text {
            visible: BT.busy
            text: "Подключение…"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }
    }
}
