pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Wi-Fi: тумблер радиомодуля, список сетей по уровню сигнала. Клик:
 * подключённая — панель отключить/забыть; сохранённая — прямое подключение;
 * защищённая неизвестная — строка пароля; открытая — прямое подключение.
 * Пароль и «забыть» — через nmcli.
 */
PillSurface {
    id: root

    w: 350
    h: 460

    property string expandedSsid: ""
    property string expandedMac: ""

    onOpenChanged: {
        if (open) {
            expandedSsid = "";
            expandedMac = "";
            Net.refreshMeta();
            rescan();
        }
    }

    readonly property var sorted: {
        var arr = [];
        var nets = Net.nets;
        for (var i = 0; i < nets.length; i++) {
            var n = nets[i];
            if (n && n.name && n.name.length)
                arr.push(n);
        }
        arr.sort(function (a, b) { return (b.signalStrength || 0) - (a.signalStrength || 0); });
        return arr;
    }

    function rescan() {
        Net.rescan();
        scanPulse.restart();
    }

    property bool scanning: false

    Timer {
        id: scanPulse
        interval: 2500
        onTriggered: root.scanning = false
    }

    Timer {
        interval: 15000
        running: root.open
        repeat: true
        onTriggered: root.rescan()
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16 * root.s
        spacing: 10 * root.s

        // ── заголовок с тумблером ──
        Item {
            width: parent.width
            height: 30 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * root.s
                    height: 17 * root.s
                    name: "wifi"
                    level: Net.wifiOn ? Math.max(0.4, Net.strength) : -1
                    color: Net.wifiOn ? Theme.accent : Theme.dim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wi-Fi"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.fsTitle * root.s
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors.right: toggle.left
                anchors.rightMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: !Net.wifiOn ? "выкл" : (Net.activeSsid.length ? Net.activeSsid : "нет подключения")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                elide: Text.ElideRight
                width: parent.width - 120 * root.s
                horizontalAlignment: Text.AlignRight
            }

            ToggleSwitch {
                id: toggle

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                on: Net.wifiOn
                onToggled: Net.toggleWifi()
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
            visible: Net.wifiOn
        }

        Text {
            width: parent.width
            visible: Net.connectFailed
            text: "Не удалось подключиться"
            color: Theme.danger
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }

        Text {
            width: parent.width
            visible: Net.wifiOn && root.sorted.length === 0
            text: root.scanning ? "Поиск сетей…" : "Сети не найдены"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            horizontalAlignment: Text.AlignHCenter
        }

        // ── список сетей ──
        Item {
            width: parent.width
            height: parent.height - 30 * root.s - 24 * root.s - (Net.connectFailed ? 16 * root.s : 0)
                    - (Net.wifiOn ? 2 * 10 * root.s : 0)
            visible: Net.wifiOn && root.sorted.length > 0

            ListView {
                id: netList
                anchors.fill: parent
                visible: Net.wifiOn && root.sorted.length > 0
                clip: true
                spacing: 2 * root.s
                model: root.sorted
                boundsBehavior: Flickable.StopAtBounds

            delegate: Column {
                id: entry

                required property var modelData

                readonly property string ssid: modelData.name || ""
                readonly property bool connected: modelData.connected
                readonly property bool known: Net.knownProfiles[ssid] === true
                readonly property bool secured: Net.isSecured(ssid)
                readonly property bool expanded: root.expandedSsid === ssid

                width: netList.width

                Rectangle {
                    width: parent.width
                    height: 36 * root.s
                    radius: Theme.radiusM * root.s
                    color: rowArea.containsMouse || entry.expanded ? Theme.veilHover : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10 * root.s
                        anchors.rightMargin: 10 * root.s
                        spacing: 9 * root.s

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * root.s
                            height: 16 * root.s
                            name: "wifi"
                            level: Math.max(0.12, (entry.modelData.signalStrength || 0) / 100)
                            color: entry.connected ? Theme.accent : Theme.dim
                        }

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.secured
                            width: 12 * root.s
                            height: 12 * root.s
                            name: "lock"
                            color: Theme.faint
                            stroke: 2.2
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 90 * root.s
                            text: entry.ssid
                            color: entry.connected ? Theme.text : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            elide: Text.ElideRight
                        }

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.connected
                            width: 13 * root.s
                            height: 13 * root.s
                            name: "check"
                            color: Theme.accent
                            stroke: 2.4
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (entry.connected || entry.known) {
                                if (!entry.expanded) Net.showPassword(entry.ssid);
                                root.expandedSsid = entry.expanded ? "" : entry.ssid;
                                pwInput.text = "";
                            } else if (entry.secured) {
                                root.expandedSsid = entry.expanded ? "" : entry.ssid;
                                pwInput.text = "";
                                pwInput.forceActiveFocus();
                            } else {
                                root.expandedSsid = "";
                                Net.connectSsid(entry.ssid);
                            }
                        }
                    }
                }

                // ── раскрытая панель ──
                Column {
                    width: parent.width
                    spacing: 6 * root.s
                    visible: entry.expanded

                    // пароль — для защищённой неизвестной сети
                    Row {
                        width: parent.width
                        spacing: 6 * root.s
                        visible: entry.secured && !entry.connected && !entry.known

                        Rectangle {
                            width: parent.width - 122 * root.s
                            height: 30 * root.s
                            radius: 9 * root.s
                            color: Theme.veil
                            border.width: 1
                            border.color: pwInput.activeFocus ? Theme.accentDim : Theme.border

                            TextInput {
                                id: pwInput
                                property bool showPw: false

                                anchors.fill: parent
                                anchors.leftMargin: 10 * root.s
                                anchors.rightMargin: 34 * root.s
                                echoMode: showPw ? TextInput.Normal : TextInput.Password
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                clip: true
                                selectionColor: Theme.accentDim
                                verticalAlignment: TextInput.AlignVCenter

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pwInput.text.length === 0 && !pwInput.activeFocus
                                    text: "Пароль…"
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 11.5 * root.s
                                }

                                onAccepted: Net.connectWithPassword(entry.ssid, pwInput.text)
                            }

                            // показать/скрыть пароль
                            GlyphIcon {
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14 * root.s
                                height: 14 * root.s
                                name: pwInput.showPw ? "eyeOff" : "eye"
                                color: eyeArea.containsMouse ? Theme.text : Theme.faint
                                stroke: 2
                            }

                            MouseArea {
                                id: eyeArea
                                anchors.right: parent.right
                                anchors.rightMargin: 4 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26 * root.s
                                height: parent.height
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pwInput.showPw = !pwInput.showPw;
                                    pwInput.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            width: 78 * root.s
                            height: 30 * root.s
                            radius: 9 * root.s
                            color: pwInput.text.length && !Net.connecting ? Theme.accentDim : Theme.veil

                            Text {
                                anchors.centerIn: parent
                                text: Net.connecting ? "…" : "Ввод"
                                color: pwInput.text.length && !Net.connecting ? Theme.text : Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: pwInput.text.length && !Net.connecting ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (pwInput.text.length && !Net.connecting)
                                        Net.connectWithPassword(entry.ssid, pwInput.text);
                                }
                            }
                        }
                    }

                    // пароль сохранённой сети — прочитать из nmcli
                    Row {
                        width: parent.width
                        spacing: 6 * root.s
                        visible: entry.expanded && entry.known

                        Rectangle {
                            width: parent.width
                            height: 30 * root.s
                            radius: 9 * root.s
                            color: Theme.veil
                            border.width: 1
                            border.color: Theme.border

                            TextInput {
                                id: savedPw
                                property bool showPw: false

                                anchors.fill: parent
                                anchors.leftMargin: 10 * root.s
                                anchors.rightMargin: 34 * root.s
                                readOnly: true
                                echoMode: savedPw.showPw || !Net.wifiPw.length
                                          ? TextInput.Normal : TextInput.Password
                                text: Net.wifiPw.length ? Net.wifiPw : "пароль не найден"
                                color: Net.wifiPw.length ? Theme.text : Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                clip: true
                                selectionColor: Theme.accentDim
                                verticalAlignment: TextInput.AlignVCenter
                            }

                            GlyphIcon {
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14 * root.s
                                height: 14 * root.s
                                name: savedPw.showPw ? "eyeOff" : "eye"
                                color: pwEye.containsMouse ? Theme.text : Theme.faint
                                stroke: 2
                            }

                            MouseArea {
                                id: pwEye
                                anchors.right: parent.right
                                anchors.rightMargin: 4 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26 * root.s
                                height: parent.height
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: savedPw.showPw = !savedPw.showPw
                            }
                        }
                    }

                    // подключённая / сохранённая — действия
                    Row {
                        width: parent.width
                        spacing: 6 * root.s
                        visible: entry.connected || entry.known

                        Rectangle {
                            width: (parent.width - 6 * root.s) / 2
                            height: 28 * root.s
                            radius: 9 * root.s
                            color: actArea1.containsMouse ? Theme.veilHover : Theme.veil

                            Text {
                                anchors.centerIn: parent
                                text: entry.connected ? "Отключить" : "Подключить"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                            }

                            MouseArea {
                                id: actArea1
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.expandedSsid = "";
                                    if (entry.connected)
                                        Net.disconnectWifi();
                                    else
                                        Net.connectSsid(entry.ssid);
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 6 * root.s) / 2
                            height: 28 * root.s
                            radius: 9 * root.s
                            color: actArea2.containsMouse ? Theme.veilHover : Theme.veil

                            Text {
                                anchors.centerIn: parent
                                text: "Забыть"
                                color: Theme.danger
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                            }

                            MouseArea {
                                id: actArea2
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.expandedSsid = "";
                                    Net.forget(entry.ssid);
                                }
                            }
                        }
                    }
                }
            }
            }

            SlimScroll {
                flick: netList
                s: root.s
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }
        }
    }
}
