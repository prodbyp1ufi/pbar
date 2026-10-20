pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Подключения: Wi-Fi (тумблер, текущая сеть с паролем, список сетей) и
 * Bluetooth (тумблер, автопоиск, устройства с настройками) в одном
 * прокручиваемом разделе.
 */
PillSurface {
    id: root

    w: 370
    h: 480

    property string expandedWifi: ""
    property string expandedBt: ""

    onOpenChanged: {
        if (open) {
            expandedWifi = "";
            expandedBt = "";
            Net.refreshMeta();
            BT.refresh();
            // поиск BT запускается автоматически при открытии
            if (BT.powered && !BT.scanning) BT.startScan();
        } else {
            BT.stopScan();
        }
    }

    // сети по уровню сигнала
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

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: innerCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: innerCol
            x: 14 * root.s
            width: flick.width - 28 * root.s
            spacing: 10 * root.s

            Text {
                text: "Подключения"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fsTitle * root.s
                font.weight: Font.DemiBold
            }

            // ══════════ WI-FI ══════════
            Rectangle {
                width: parent.width
                height: wifiCol.height + 24 * root.s
                radius: Theme.radiusM * root.s
                color: Theme.veil
                border.width: 1
                border.color: Theme.border

                Column {
                    id: wifiCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12 * root.s
                    spacing: 8 * root.s

                    // заголовок + тумблер
                    Row {
                        width: parent.width
                        spacing: 8 * root.s

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * root.s
                            height: 16 * root.s
                            name: "wifi"
                            level: Net.wifiOn ? Math.max(0.4, Net.strength) : -1
                            color: Net.wifiOn ? Theme.accent : Theme.dim
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Wi-Fi"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: Font.DemiBold
                        }

                        Item { width: parent.width - 150 * root.s; height: 1 }

                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            s: root.s
                            on: Net.wifiOn
                            onToggled: Net.toggleWifi()
                        }
                    }

                    Text {
                        visible: Net.connectFailed
                        width: parent.width
                        text: "Не удалось подключиться"
                        color: Theme.danger
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }

                    // список сетей
                    Column {
                        width: parent.width
                        visible: Net.wifiOn
                        spacing: 2 * root.s

                        Text {
                            visible: root.sorted.length === 0
                            width: parent.width
                            text: "Поиск сетей…"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Repeater {
                            model: root.sorted

                            delegate: Column {
                                id: entry

                                required property var modelData

                                readonly property string ssid: modelData.name || ""
                                readonly property bool connected: modelData.connected
                                readonly property bool known: Net.knownProfiles[ssid] === true
                                readonly property bool secured: Net.isSecured(ssid)
                                readonly property bool expanded: root.expandedWifi === ssid

                                width: parent.width

                                Rectangle {
                                    width: parent.width
                                    height: 34 * root.s
                                    radius: Theme.radiusS * root.s
                                    color: rowArea.containsMouse || entry.expanded ? Theme.veilHover : "transparent"

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 9 * root.s
                                        anchors.rightMargin: 9 * root.s
                                        spacing: 8 * root.s

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 15 * root.s
                                            height: 15 * root.s
                                            name: "wifi"
                                            level: Math.max(0.12, (entry.modelData.signalStrength || 0) / 100)
                                            color: entry.connected ? Theme.accent : Theme.dim
                                        }

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: entry.secured
                                            width: 11 * root.s
                                            height: 11 * root.s
                                            name: "lock"
                                            color: Theme.faint
                                            stroke: 2.2
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 80 * root.s
                                            text: entry.ssid
                                            color: entry.connected ? Theme.text : Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 11 * root.s
                                            elide: Text.ElideRight
                                        }

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: entry.connected
                                            width: 12 * root.s
                                            height: 12 * root.s
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
                                                root.expandedWifi = entry.expanded ? "" : entry.ssid;
                                                pwInput.text = "";
                                            } else if (entry.secured) {
                                                root.expandedWifi = entry.expanded ? "" : entry.ssid;
                                                pwInput.text = "";
                                                pwInput.forceActiveFocus();
                                            } else {
                                                root.expandedWifi = "";
                                                Net.connectSsid(entry.ssid);
                                            }
                                        }
                                    }
                                }

                                // раскрытая панель
                                Column {
                                    width: parent.width
                                    spacing: 6 * root.s
                                    visible: entry.expanded

                                    // пароль защищённой неизвестной сети
                                    Row {
                                        width: parent.width
                                        spacing: 6 * root.s
                                        visible: entry.secured && !entry.connected && !entry.known

                                        Rectangle {
                                            width: parent.width - 116 * root.s
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
                                            width: 74 * root.s
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

                                    // пароль сохранённой сети
                                    Row {
                                        width: parent.width
                                        spacing: 6 * root.s
                                        visible: entry.known

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

                                    // действия
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
                                                    root.expandedWifi = "";
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
                                            color: actArea2.containsMouse ? Theme.danger : Theme.veil

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Забыть"
                                                color: actArea2.containsMouse ? "#111318" : Theme.danger
                                                font.family: Theme.font
                                                font.pixelSize: 10.5 * root.s
                                            }

                                            MouseArea {
                                                id: actArea2
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.expandedWifi = "";
                                                    Net.forget(entry.ssid);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: !Net.wifiOn
                        width: parent.width
                        text: Net.ethernetUp ? "Wi-Fi выключен — работает кабель" : "Wi-Fi выключен"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // ══════════ BLUETOOTH ══════════
            Rectangle {
                width: parent.width
                height: btCol.height + 24 * root.s
                radius: Theme.radiusM * root.s
                color: Theme.veil
                border.width: 1
                border.color: Theme.border

                Column {
                    id: btCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12 * root.s
                    spacing: 8 * root.s

                    // заголовок + тумблер
                    Row {
                        width: parent.width
                        spacing: 8 * root.s

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * root.s
                            height: 16 * root.s
                            name: "bt"
                            color: BT.powered ? Theme.accent : Theme.dim
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Bluetooth"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: Font.DemiBold
                        }

                        Item { width: parent.width - 170 * root.s; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: BT.powered ? (BT.scanning ? "поиск…" : "вкл") : "выкл"
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

                    // устройства
                    Column {
                        width: parent.width
                        visible: BT.powered
                        spacing: 2 * root.s

                        Repeater {
                            model: BT.devices

                            delegate: Column {
                                id: bdev

                                required property var modelData

                                readonly property bool expanded: root.expandedBt === modelData.mac

                                width: parent.width

                                Rectangle {
                                    width: parent.width
                                    height: 34 * root.s
                                    radius: Theme.radiusS * root.s
                                    color: btRowArea.containsMouse || bdev.expanded ? Theme.veilHover : "transparent"

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 9 * root.s
                                        anchors.rightMargin: 9 * root.s
                                        spacing: 8 * root.s

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 8 * root.s
                                            height: 8 * root.s
                                            radius: width / 2
                                            color: bdev.modelData.connected ? Theme.ok
                                                 : bdev.modelData.paired ? Theme.accent : "transparent"
                                            border.width: 1
                                            border.color: bdev.modelData.connected ? Theme.ok
                                                        : bdev.modelData.paired ? Theme.accent : Theme.faint
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 110 * root.s
                                            text: bdev.modelData.name.length ? bdev.modelData.name : bdev.modelData.mac
                                            color: bdev.modelData.connected ? Theme.text : Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 10.5 * root.s
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 66 * root.s
                                            text: bdev.modelData.connected ? "подключено"
                                                 : bdev.modelData.paired ? "сопряжено" : "найдено"
                                            color: bdev.modelData.connected ? Theme.ok : Theme.faint
                                            font.family: Theme.font
                                            font.pixelSize: 10 * root.s
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }

                                    MouseArea {
                                        id: btRowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (bdev.modelData.connected) {
                                                root.expandedBt = bdev.expanded ? "" : bdev.modelData.mac;
                                            } else if (bdev.modelData.paired) {
                                                BT.connect(bdev.modelData.mac);
                                            } else {
                                                BT.pairAndConnect(bdev.modelData.mac);
                                            }
                                        }
                                    }
                                }

                                // панель действий подключённого устройства
                                Row {
                                    visible: bdev.expanded
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
                                                BT.disconnect(bdev.modelData.mac);
                                                root.expandedBt = "";
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
                                                BT.remove(bdev.modelData.mac);
                                                root.expandedBt = "";
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: BT.devices.length === 0
                            width: parent.width
                            text: BT.scanning ? "Поиск устройств…" : "Устройств не найдено"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Text {
                        visible: !BT.powered
                        width: parent.width
                        text: "Bluetooth выключен"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        visible: BT.busy
                        width: parent.width
                        text: "Подключение…"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }
                }
            }

            // проводное подключение
            Rectangle {
                visible: Net.ethernetUp
                width: parent.width
                height: 34 * root.s
                radius: Theme.radiusM * root.s
                color: Theme.veil
                border.width: 1
                border.color: Theme.border

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12 * root.s
                    spacing: 8 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14 * root.s
                        height: 14 * root.s
                        name: "ether"
                        color: Theme.ok
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Проводное подключение активно"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }
                }
            }
        }
    }

    SlimScroll {
        flick: flick
        s: root.s
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 8 * root.s
    }
}
