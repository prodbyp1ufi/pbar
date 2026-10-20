pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Services.Pipewire
import Quickshell.Io
import "../Singletons"
import "../components"

/**
 * Control Center — единая панель вместо отдельных окон: системный трей,
 * плитки Wi-Fi/Bluetooth/не беспокоить/батарея, узкие вертикальные
 * слайдеры, выбор устройств звука (вывод/вход), список сетей Wi-Fi
 * с паролем, устройства Bluetooth с поиском, батарея с профилем питания,
 * мониторинг (CPU/ОЗУ/диск), мини-плеер и быстрые действия. Всё
 * скроллится; высота подстраивается под содержимое (максимум 680).
 */
PillSurface {
    id: root

    property string screenName: ""
    property var barWindow

    property string expandedSsid: ""
    property string expandedMac: ""

    w: 380

    readonly property bool mediaRow: Players.has
    readonly property bool hasTray: trayRef.trayItems.length > 0

    h: Math.min(680, Math.ceil(flick.contentHeight / s))

    onOpenChanged: {
        if (open) {
            expandedSsid = "";
            expandedMac = "";
            dragFrac = -1;
            ctxOpen = "";
            wantsKeys = false;
            Net.refreshMeta();
            Battery.refreshProfile();
        } else {
            ctxOpen = "";
            BT.stopScan();
            wantsKeys = false;
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
        // подключённая сеть всегда сверху, затем по уровню сигнала
        arr.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            return (b.signalStrength || 0) - (a.signalStrength || 0);
        });
        return arr;
    }

    // устройства: подключённые сверху, затем сопряжённые
    readonly property var btSorted: {
        var arr = [];
        var devs = BT.devices;
        for (var i = 0; i < devs.length; i++)
            if (devs[i]) arr.push(devs[i]);
        arr.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.paired !== b.paired) return a.paired ? -1 : 1;
            return 0;
        });
        return arr;
    }

    property bool scanning: false

    Timer {
        id: scanPulse
        interval: 2500
        onTriggered: root.scanning = false
    }

    function rescan() {
        Net.rescan();
        scanning = true;
        scanPulse.restart();
    }

    // имя первого подключённого BT-устройства — для подписи плитки
    readonly property string btConnectedName: {
        for (var i = 0; i < BT.devices.length; i++)
            if (BT.devices[i] && BT.devices[i].connected)
                return BT.devices[i].name;
        return "";
    }

    // ── аудио-устройства (id нод читается, выбор — wpctl set-default) ──
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property int sinkId: (sink && sink.id !== undefined && sink.id !== null) ? sink.id : -1
    readonly property int srcId: (source && source.id !== undefined && source.id !== null) ? source.id : -1

    readonly property var sinks: {
        var all = Pipewire.nodes.values;
        var out = [];
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.isSink && n.audio && n.name && n.name.indexOf(".monitor") < 0)
                out.push(n);
        }
        return out;
    }

    readonly property var sources: {
        var all = Pipewire.nodes.values;
        var out = [];
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && !n.isSink && n.audio && n.name && n.name.indexOf(".monitor") < 0)
                out.push(n);
        }
        return out;
    }

    function nodeLabel(n) {
        if (!n) return "";
        return (n.description && n.description.length) ? n.description : (n.name || "");
    }

    // иконка сети для плитки: ethernet без wifi
    readonly property string netGlyph: Net.ethernetUp && !Net.activeNet ? "ether" : "wifi"

    // слайдеры: яркость (если доступна), звук, микрофон
    readonly property var sliders: {
        var m = [];
        if (Bright.ok)
            m.push({ kind: "bright", icon: "sun", fill: Theme.warn });
        m.push({ kind: "vol", icon: "volume", fill: Theme.accent });
        m.push({ kind: "mic", icon: "mic", fill: Theme.ok });
        return m;
    }

    function setSlider(kind, v) {
        if (kind === "bright")
            Bright.setFrac(v);
        else if (kind === "vol")
            Audio.setSinkVolume(v);
        else
            Audio.setSrcVolume(v);
    }

    // ── данные медиа ──
    readonly property var p: Players.active
    readonly property bool canPrev: Players.has && p && p.canGoPrevious
    readonly property bool canNext: Players.has && p && p.canGoNext
    readonly property bool canToggle: Players.has && p && p.canTogglePlaying
    readonly property bool canShuffle: Players.has && p && p.shuffleSupported === true
    readonly property bool shuffling: Players.has && p && p.shuffle === true
    readonly property bool canLoop: Players.has && p && p.loopSupported === true
    readonly property int loopMode: Players.has && p && p.loopState !== undefined ? p.loopState : 0
    readonly property bool canSeek: Players.has && p && p.canSeek && p.positionSupported
                                    && Players.lengthSec > 0 && !Players.live
    readonly property real posSec: Players.has && p && p.positionSupported ? p.position : 0
    property real dragFrac: -1

    function fmtTime(sec) {
        sec = Math.max(0, Math.floor(sec));
        var m = Math.floor(sec / 60);
        var s = sec % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // ── клавиатура: хаб её не перехватывает, кроме поля пароля Wi-Fi ──
    function grabKeys(input) {
        wantsKeys = true;
        input.forceActiveFocus();
    }

    function releaseKeys() {
        wantsKeys = false;
    }

    // ── вертикальный слайдер в стиле iOS: заливка снизу, иконка в «колодце».
    //      Тап ставит значение сразу, драг ведёт непрерывно; после отпускания
    //      показываем локальное значение, пока синглтон не подтвердит ──
    component VFader: Rectangle {
        id: vf

        property real s: 1
        property real value: 0
        property bool muted: false
        property color fillColor: Theme.accent
        property string icon: ""
        property real iconLevel: -1
        property color iconColor: muted ? Theme.faint : Theme.text

        signal moved(real v)
        signal committed(real v)
        signal menuRequested()

        // какой список открывает ПКМ: sink/source; пусто — меню нет
        property string menuKind: ""

        radius: 20 * s
        color: Theme.veil
        border.width: 1
        border.color: Theme.border
        clip: true

        property real dragVal: 0
        property bool wheelHold: false
        property bool acceptHold: false
        readonly property real shown: ma.pressed || wheelHold || acceptHold
                                      ? dragVal
                                      : Math.max(0, Math.min(1, value))

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * vf.shown
            radius: 20 * vf.s
            color: vf.muted ? Theme.faint : vf.fillColor
            opacity: vf.muted ? 0.45 : 1
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 9 * vf.s
            width: 30 * vf.s
            height: 30 * vf.s
            radius: height / 2
            color: Qt.rgba(0.04, 0.05, 0.07, 0.55)

            GlyphIcon {
                anchors.centerIn: parent
                width: 15 * vf.s
                height: 15 * vf.s
                name: vf.icon
                level: vf.iconLevel
                color: vf.iconColor
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            property bool rightHeld: false

            onPressed: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    rightHeld = true;
                    if (vf.menuKind.length) vf.menuRequested();
                    return;
                }
                vf.setFromY(mouse.y);
            }
            onPositionChanged: (mouse) => { if (pressed && !rightHeld) vf.setFromY(mouse.y) }
            onReleased: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    rightHeld = false;
                    return;
                }
                vf.accept();
            }
        }

        // колесо: крутим фейдер и блокируем прокрутку хаба под курсором —
        // иначе контент уезжает и фейдер не долистать до 100%
        WheelHandler {
            blocking: true
            onWheel: (ev) => vf.spin(ev.angleDelta.y)
        }

        Timer {
            id: wheelT
            interval: 500
            onTriggered: vf.wheelHold = false
        }

        // держим локальное значение, пока синглтон не подтвердит новое
        Timer {
            id: acceptT
            interval: 900
            onTriggered: vf.acceptHold = false
        }

        function clamp01(x) { return Math.max(0, Math.min(1, x)); }

        function setFromY(y) {
            var v = clamp01(1 - y / height);
            dragVal = v;
            moved(v);
        }

        function accept() {
            acceptHold = true;
            acceptT.restart();
            committed(dragVal);
        }

        // колесо мыши/тачпада: 5% на щелчок, дробные дельты — плавно;
        // у краёв добиваем ровно до 0 и 1
        function spin(delta) {
            var steps = delta / 120;
            if (!steps) return;
            var v = clamp01(shown + steps * 0.05);
            if (v >= 0.995) v = 1;
            if (v <= 0.005) v = 0;
            dragVal = v;
            wheelHold = true;
            moved(v);
            committed(v);
            wheelT.restart();
        }
    }

    // ── строка устройства звука: радиоточка + имя, клик — выбрать ──
    component DevRow: Rectangle {
        id: devRow

        property real s: 1
        property string label: ""
        property bool active: false
        property color dotColor: Theme.accent

        signal picked()

        height: 30 * s
        radius: Theme.radiusS * s
        color: devArea.containsMouse ? Theme.veilHover : "transparent"

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 8 * devRow.s
            anchors.verticalCenter: parent.verticalCenter
            width: 9 * devRow.s
            height: 9 * devRow.s
            radius: width / 2
            color: devRow.active ? devRow.dotColor : "transparent"
            border.width: 1
            border.color: devRow.active ? devRow.dotColor : Theme.faint
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 24 * devRow.s
            anchors.right: parent.right
            anchors.rightMargin: 8 * devRow.s
            anchors.verticalCenter: parent.verticalCenter
            text: devRow.label
            color: devRow.active ? Theme.text : Theme.dim
            font.family: Theme.font
            font.pixelSize: 10.5 * devRow.s
            elide: Text.ElideRight
        }

        MouseArea {
            id: devArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: devRow.picked()
        }
    }

    // ── блок мониторинга: иконка + значение + подпись + полоска загрузки ──
    component MonStat: Column {
        id: ms

        property real s: 1
        property string gicon: ""
        property string big: ""
        property string sub: ""
        property real frac: -1
        property real hot: 0.75

        spacing: 5 * ms.s

        Row {
            spacing: 10 * ms.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 22 * ms.s
                height: 22 * ms.s
                name: ms.gicon
                color: ms.frac > 0.9 ? Theme.danger
                                     : (ms.frac > ms.hot ? Theme.warn : Theme.dim)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * ms.s

                Text {
                    color: ms.frac > 0.9 ? Theme.danger : (ms.frac > ms.hot ? Theme.warn : Theme.text)
                    text: ms.big
                    font.family: Theme.font
                    font.pixelSize: 14 * ms.s
                    font.weight: Font.DemiBold
                }

                Text {
                    text: ms.sub
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12 * ms.s
                }
            }
        }

        // тонкая полоска загрузки; у сети (frac < 0) её нет
        Rectangle {
            visible: ms.frac >= 0
            width: parent.width
            height: 3 * ms.s
            radius: height / 2
            color: Theme.veilHover

            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, ms.frac))
                height: parent.height
                radius: parent.radius
                color: ms.frac > 0.9 ? Theme.danger : (ms.frac > ms.hot ? Theme.warn : Theme.accent)
                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: innerCol.y + innerCol.height + 14 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onMovementStarted: root.closeCtx()

        Column {
            id: innerCol
            x: 14 * root.s
            y: 14 * root.s
            width: flick.width - 28 * root.s
            spacing: 10 * root.s

            // ══ 1. системный трей ══
            Rectangle {
                visible: root.hasTray
                width: parent.width
                height: 36 * root.s
                radius: Theme.radiusM * root.s
                color: Theme.veil
                border.width: 1
                border.color: Theme.border

                Tray {
                    id: trayRef
                    anchors.centerIn: parent
                    s: root.s
                    barWindow: root.barWindow
                }
            }

            // ══ 2. плитки 2×2 + слайдеры + мониторинг справа ══
            Item {
                width: parent.width
                height: 268 * root.s

                readonly property real leftW: width - 170 * root.s

                // ── сетка 2×2: Wi-Fi, Bluetooth / не беспокоить, батарея ──
                Grid {
                    id: tileGrid
                    width: parent.leftW
                    columns: 2
                    spacing: 10 * root.s

                    // ── Wi-Fi ──
                    Rectangle {
                        id: wifiTile
                        width: (tileGrid.width - 10 * root.s) / 2
                        height: 64 * root.s
                        radius: Theme.radiusM * root.s
                        color: wifiTileArea.containsMouse ? Theme.veilHover : Theme.veil
                        border.width: 1
                        border.color: Theme.border
                        scale: wifiTileArea.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 38 * root.s
                            height: 38 * root.s
                            radius: height / 2
                            color: Net.wifiOn || Net.ethernetUp ? Theme.accent : Theme.veilHover
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 22 * root.s
                                height: 22 * root.s
                                name: root.netGlyph
                                level: !Net.wifiOn ? -1 : Math.max(0.3, Net.strength)
                                color: Net.wifiOn || Net.ethernetUp ? "#111318" : Theme.dim
                            }
                        }

                        MouseArea {
                            id: wifiTileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton)
                                    root.openCtx("wifi", wifiTile, true);
                                else
                                    Net.toggleWifi();
                            }
                        }
                    }

                    // ── Bluetooth ──
                    Rectangle {
                        id: btTile
                        width: (tileGrid.width - 10 * root.s) / 2
                        height: 64 * root.s
                        radius: Theme.radiusM * root.s
                        color: btTileArea.containsMouse ? Theme.veilHover : Theme.veil
                        border.width: 1
                        border.color: Theme.border
                        scale: btTileArea.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 38 * root.s
                            height: 38 * root.s
                            radius: height / 2
                            color: BT.powered ? Theme.accent : Theme.veilHover
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 22 * root.s
                                height: 22 * root.s
                                name: "bt"
                                color: BT.powered ? "#111318" : Theme.dim
                            }
                        }

                        MouseArea {
                            id: btTileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton)
                                    root.openCtx("bt", btTile, true);
                                else
                                    BT.togglePower();
                            }
                        }
                    }

                    // ── «Не беспокоить»: перечёркнутый колокол ──
                    Rectangle {
                        width: (tileGrid.width - 10 * root.s) / 2
                        height: 64 * root.s
                        radius: Theme.radiusM * root.s
                        color: dndTileArea.containsMouse ? Theme.veilHover : Theme.veil
                        border.width: 1
                        border.color: Theme.border
                        scale: dndTileArea.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 38 * root.s
                            height: 38 * root.s
                            radius: height / 2
                            color: Notifs.dnd ? Theme.accent : Theme.veilHover
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 22 * root.s
                                height: 22 * root.s
                                name: "bell-off"
                                color: Notifs.dnd ? "#111318" : Theme.dim
                            }
                        }

                        MouseArea {
                            id: dndTileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.dnd = !Notifs.dnd
                        }
                    }

                    // ── батарея: клик — меню с профилем питания ──
                    Rectangle {
                        id: battTile
                        visible: Battery.present
                        width: (tileGrid.width - 10 * root.s) / 2
                        height: 64 * root.s
                        radius: Theme.radiusM * root.s
                        color: battTileArea.containsMouse ? Theme.veilHover : Theme.veil
                        border.width: 1
                        border.color: root.ctxOpen === "battery" ? Theme.accentDim : Theme.border
                        scale: battTileArea.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 38 * root.s
                            height: 38 * root.s
                            radius: height / 2
                            color: Theme.veilHover

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 22 * root.s
                                height: 22 * root.s
                                name: "battery"
                                fill: Battery.pct / 100
                                bolt: Battery.charging
                                color: Battery.low ? Theme.danger : (Battery.charging ? Theme.ok : Theme.text)
                            }
                        }

                        MouseArea {
                            id: battTileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: root.openCtx("battery", battTile, true)
                        }
                    }
                }

                // ── узкие слайдеры ──
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10 * root.s
                    anchors.bottom: parent.bottom
                    spacing: 10 * root.s

                    Repeater {
                        model: root.sliders

                        delegate: VFader {
                            id: fdel

                            required property var modelData
                            readonly property string kind: modelData.kind === "vol" ? "sink"
                                                         : modelData.kind === "mic" ? "source" : ""

                            width: 50 * root.s
                            height: 120 * root.s
                            s: root.s
                            menuKind: fdel.kind
                            icon: fdel.modelData.icon
                            fillColor: fdel.modelData.fill
                            value: fdel.modelData.kind === "bright" ? Bright.frac
                                 : fdel.modelData.kind === "vol" ? Audio.sinkVol
                                 : Audio.srcVol
                            muted: fdel.modelData.kind === "vol" ? Audio.sinkMute
                                 : fdel.modelData.kind === "mic" ? Audio.srcMute
                                 : false
                            iconLevel: fdel.modelData.kind === "vol" ? (Audio.sinkMute ? -1 : Audio.sinkVol) : -1
                            onMoved: (v) => root.setSlider(fdel.modelData.kind, v)
                            onCommitted: (v) => root.setSlider(fdel.modelData.kind, v)
                            onMenuRequested: root.toggleCtx(fdel.kind, fdel)
                        }
                    }
                }

                // ── мониторинг: CPU / ОЗУ / диск / сеть ──
                Rectangle {
                    anchors.right: parent.right
                    width: 160 * root.s
                    height: parent.height
                    radius: Theme.radiusM * root.s
                    color: Theme.veil
                    border.width: 1
                    border.color: Theme.border

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 13 * root.s
                        anchors.right: parent.right
                        anchors.rightMargin: 13 * root.s
                        anchors.top: parent.top
                        anchors.topMargin: 13 * root.s
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 13 * root.s
                        spacing: Math.max(10 * root.s,
                            (height - cpuStat.height - ramStat.height
                                   - diskStat.height - netStat.height) / 3)

                        MonStat {
                            id: cpuStat
                            width: parent.width
                            s: root.s
                            gicon: "cpu"
                            big: Math.round(Res.cpu * 100) + "%"
                            sub: "CPU · " + Math.round(Res.temp) + "°"
                            frac: Res.cpu
                            hot: 0.7
                        }

                        MonStat {
                            id: ramStat
                            width: parent.width
                            s: root.s
                            gicon: "ram"
                            big: (Res.memUsed / 1024).toFixed(1) + " / " + (Res.memTotal / 1024).toFixed(0) + " ГБ"
                            sub: "ОЗУ · " + Math.round(Res.mem * 100) + "%"
                            frac: Res.mem
                        }

                        MonStat {
                            id: diskStat
                            width: parent.width
                            s: root.s
                            gicon: "drive"
                            big: (Res.diskUsed / 1e9).toFixed(0) + " / " + (Res.diskTotal / 1e9).toFixed(0) + " ГБ"
                            sub: "Диск · " + Math.round((Res.diskTotal > 0 ? Res.diskUsed / Res.diskTotal : 0) * 100) + "%"
                            frac: Res.diskTotal > 0 ? Res.diskUsed / Res.diskTotal : 0
                        }

                        MonStat {
                            id: netStat
                            width: parent.width
                            s: root.s
                            gicon: "activity"
                            big: "↓ " + root.netSpd(Res.netDown)
                            sub: "↑ " + root.netSpd(Res.netUp)
                        }
                    }
                }
            }


            // ══ 3. сейчас играет ══
            Rectangle {
                visible: root.mediaRow
                width: parent.width
                height: 128 * root.s
                radius: Theme.radiusM * root.s
                color: Theme.veil
                border.width: 1
                border.color: Theme.border

                Column {
                    anchors.fill: parent
                    anchors.margins: 12 * root.s
                    spacing: 9 * root.s

                    // ── верх: обложка, титулы, управление ──
                    Row {
                        width: parent.width
                        spacing: 12 * root.s

                        Rectangle {
                            id: hubCover
                            anchors.verticalCenter: parent.verticalCenter
                            width: 62 * root.s
                            height: 62 * root.s
                            radius: 12 * root.s
                            color: Theme.veilHover
                            border.width: 1
                            border.color: Theme.glassBorder
                            clip: true

                            Image {
                                anchors.fill: parent
                                visible: Players.artUrl.length > 0
                                source: Players.artUrl
                                sourceSize.width: 124
                                sourceSize.height: 124
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                            }

                            GlyphIcon {
                                anchors.centerIn: parent
                                visible: Players.artUrl.length === 0
                                width: 24 * root.s
                                height: 24 * root.s
                                name: "note"
                                color: Theme.faint
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - hubCover.width - hubCtrl.width - 2 * 12 * root.s
                            spacing: 3 * root.s

                            Text {
                                width: parent.width
                                text: Players.title.length ? Players.title : "—"
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: Players.artist.length ? Players.artist : Players.source
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 11 * root.s
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: hubCtrl
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4 * root.s

                            // shuffle
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26 * root.s
                                height: 26 * root.s
                                radius: height / 2
                                color: hubShufArea.containsMouse ? Theme.veilHover : "transparent"
                                opacity: root.canShuffle ? 1 : 0.35

                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 13 * root.s
                                    height: 13 * root.s
                                    name: "shuffle"
                                    color: root.shuffling ? Theme.accent
                                         : (hubShufArea.containsMouse ? Theme.text : Theme.dim)
                                }

                                MouseArea {
                                    id: hubShufArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.canShuffle
                                    onClicked: if (root.p) root.p.shuffle = !root.p.shuffle
                                }
                            }

                            // prev
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28 * root.s
                                height: 28 * root.s
                                radius: height / 2
                                color: hubPrevArea.containsMouse && root.canPrev ? Theme.veilHover : "transparent"
                                opacity: root.canPrev ? 1 : 0.35

                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 13 * root.s
                                    height: 13 * root.s
                                    name: "prev"
                                    color: Theme.text
                                }

                                MouseArea {
                                    id: hubPrevArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.canPrev
                                    onClicked: if (root.p) root.p.previous()
                                }
                            }

                            // play / pause
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36 * root.s
                                height: 36 * root.s
                                radius: height / 2
                                color: Players.playing ? Theme.accentDim : Theme.accent

                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 16 * root.s
                                    height: 16 * root.s
                                    name: Players.playing ? "pause" : "play"
                                    color: "#111318"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.canToggle
                                    onClicked: if (root.p) root.p.togglePlaying()
                                }
                            }

                            // next
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28 * root.s
                                height: 28 * root.s
                                radius: height / 2
                                color: hubNextArea.containsMouse && root.canNext ? Theme.veilHover : "transparent"
                                opacity: root.canNext ? 1 : 0.35

                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 13 * root.s
                                    height: 13 * root.s
                                    name: "next"
                                    color: Theme.text
                                }

                                MouseArea {
                                    id: hubNextArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.canNext
                                    onClicked: if (root.p) root.p.next()
                                }
                            }

                            // repeat
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26 * root.s
                                height: 26 * root.s
                                radius: height / 2
                                color: hubRepArea.containsMouse ? Theme.veilHover : "transparent"
                                opacity: root.canLoop ? 1 : 0.35

                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 13 * root.s
                                    height: 13 * root.s
                                    name: "repeat"
                                    color: root.loopMode > 0 ? Theme.accent
                                         : (hubRepArea.containsMouse ? Theme.text : Theme.dim)
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 4 * root.s
                                    anchors.bottomMargin: 2 * root.s
                                    visible: root.loopMode === 1
                                    text: "1"
                                    color: Theme.accent
                                    font.family: Theme.font
                                    font.pixelSize: 8 * root.s
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: hubRepArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.canLoop
                                    onClicked: if (root.p) root.p.loopState = (root.loopMode + 1) % 3
                                }
                            }
                        }
                    }

                    // ── низ: время + прогресс с перемоткой ──
                    Item {
                        width: parent.width
                        height: 20 * root.s

                        Text {
                            id: hubCurT
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtTime(root.dragFrac >= 0 ? root.dragFrac * Players.lengthSec : root.posSec)
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                        }

                        Text {
                            id: hubTotT
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: Players.live ? "LIVE" : root.fmtTime(Players.lengthSec)
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                        }

                        Fader {
                            anchors.left: hubCurT.right
                            anchors.leftMargin: 8 * root.s
                            anchors.right: hubTotT.left
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            s: root.s
                            interactive: root.canSeek
                            value: Players.lengthSec > 0 && !Players.live
                                   ? (root.dragFrac >= 0 ? root.dragFrac : root.posSec / Players.lengthSec)
                                   : 0
                            fillColor: Theme.accent
                            trackColor: Theme.hair
                            onMoved: (v) => { root.dragFrac = v }
                            onCommitted: (v) => {
                                if (root.p && Players.lengthSec > 0) {
                                    var target = Math.max(0, Math.min(Players.lengthSec - 0.5, v * Players.lengthSec));
                                    if (typeof root.p.setPosition === "function") root.p.setPosition(target);
                                    else if (typeof root.p.seek === "function") root.p.seek(target - root.posSec);
                                }
                                root.dragFrac = -1
                            }
                        }
                    }
                }
            }

            // ══ 4. быстрые действия ══
            Row {
                width: parent.width
                height: 48 * root.s
                spacing: 8 * root.s

                Repeater {
                    model: [
                        { icon: "camera",  surf: "shot" },
                        { icon: "image",   surf: "wall" },
                        { icon: "palette", surf: "tint" },
                        { icon: "power",   surf: "power" }
                    ]

                    delegate: Rectangle {
                        id: act

                        required property var modelData

                        width: (parent.width - 3 * 8 * root.s) / 4
                        height: 48 * root.s
                        radius: Theme.radiusM * root.s
                        color: actArea.containsMouse ? Theme.veilHover : Theme.veil
                        border.width: 1
                        border.color: Theme.border
                        scale: actArea.pressed ? 0.92 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 22 * root.s
                            height: 22 * root.s
                            name: act.modelData.icon
                            color: actArea.containsMouse ? Theme.text : Theme.dim
                        }

                        MouseArea {
                            id: actArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.go(act.modelData.surf)
                        }
                    }
                }
            }
        }
    }

    // ── контекстные меню: Wi-Fi и Bluetooth — удержание плитки,
    //    устройства звука — выпадающий список под слайдером ──
    function netSpd(v) {
        if (v >= 1024) return (v / 1024).toFixed(1) + " МБ/с";
        return Math.round(v) + " КБ/с";
    }

    property string ctxOpen: ""
    property Item ctxAnchor: null
    property bool ctxAbove: false

    function toggleCtx(kind, anchor, above) {
        if (ctxOpen === kind) {
            closeCtx();
            return;
        }
        openCtx(kind, anchor, above);
    }

    function openCtx(kind, anchor, above) {
        if (kind === "wifi") {
            wifiFlick.contentY = 0;
            wifiFlick.keepY = 0;
            Net.refreshMeta();
            rescan();
        } else if (kind === "bt") {
            btFlick.contentY = 0;
            btFlick.keepY = 0;
            BT.refresh();
            if (BT.powered && !BT.scanning)
                BT.startScan();
        } else if (kind === "battery") {
            Battery.refreshProfile();
        }
        expandedSsid = "";
        expandedMac = "";
        ctxAbove = above === true;
        ctxAnchor = anchor;
        ctxOpen = kind;
        positionCtx();
    }

    function closeCtx() {
        if (ctxOpen === "bt")
            BT.stopScan();
        ctxOpen = "";
        expandedSsid = "";
        expandedMac = "";
        releaseKeys();
    }

    function positionCtx() {
        if (!ctxAnchor || ctxOpen.length === 0 || !root.width)
            return;
        var p = ctxAnchor.mapToItem(root, 0, 0);
        var w = ctxCard.width;
        var x = p.x + ctxAnchor.width / 2 - w / 2;
        ctxCard.x = Math.max(10 * s, Math.min(x, root.width - w - 10 * s));
        var yBelow = p.y + anchorHeight() + 8 * s;
        var yAbove = p.y - ctxCard.height - 8 * s;
        var belowFits = yBelow + ctxCard.height <= root.height - 8 * s;
        var aboveFits = yAbove >= 8 * s;
        var y;
        if (ctxAbove)
            y = aboveFits ? yAbove : (belowFits ? yBelow : yAbove);
        else
            y = belowFits ? yBelow : (aboveFits ? yAbove : yBelow);
        ctxCard.y = Math.max(8 * s, Math.min(y, root.height - ctxCard.height - 8 * s));
    }

    function anchorHeight() {
        return ctxAnchor ? ctxAnchor.height : 0;
    }

    // ── всплывающее меню: содержимое зависит от ctxOpen ──
    Item {
        id: ctxLayer

        anchors.fill: parent
        visible: root.ctxOpen !== ""
        enabled: visible
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // клик мимо закрывает, колесо не крутит список под меню
        MouseArea {
            anchors.fill: parent
            onWheel: (w) => w.accepted = true
            onClicked: root.closeCtx()
        }

        // тень отдельным квадом: layer.effect рендерит весь контент меню
        // через текстуру слоя и делает текст мыльным
        RectangularShadow {
            anchors.fill: ctxCard
            offset.y: 4 * root.s
            radius: ctxCard.radius
            blur: 18 * root.s
            color: Theme.shadow
        }

        Rectangle {
            id: ctxCard

            // ширина только декларативно: присвоение из positionCtx убило бы
            // биндинг, и при следующем открытии меню осталось бы старое значение
            width: 250 * root.s
            height: Math.min(ctxCol.implicitHeight + 16 * root.s, 620 * root.s)
            radius: Theme.radiusM * root.s
            clip: true
            onHeightChanged: root.positionCtx()

            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.cardTop }
                GradientStop { position: 1.0; color: Theme.cardBot }
            }
            border.width: 1
            border.color: Theme.border

            Column {
                id: ctxCol
                x: 8 * root.s
                y: 8 * root.s
                width: ctxCard.width - 16 * root.s
                spacing: 6 * root.s

                // ── шапка: заголовок + сканер/mute ──
                Item {
                    id: ctxHeader
                    width: parent.width
                    height: 26 * root.s

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8 * root.s

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14 * root.s
                            height: 14 * root.s
                            name: root.ctxOpen === "wifi" ? "wifi"
                                : root.ctxOpen === "bt" ? "bt"
                                : root.ctxOpen === "sink" ? "volume"
                                : root.ctxOpen === "source" ? "mic"
                                : root.ctxOpen === "battery" ? "battery" : "power"
                            level: root.ctxOpen === "wifi" ? (Net.wifiOn ? Math.max(0.3, Net.strength) : -1)
                                : root.ctxOpen === "sink" ? (Audio.sinkMute ? -1 : Math.max(0.05, Audio.sinkVol))
                                : root.ctxOpen === "source" ? Math.max(0.05, Audio.srcVol)
                                : -1
                            fill: root.ctxOpen === "battery" ? Battery.pct / 100 : -1
                            bolt: root.ctxOpen === "battery" && Battery.charging
                            color: Theme.dim
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ctxOpen === "wifi" ? "Wi-Fi"
                                : root.ctxOpen === "bt" ? "Bluetooth"
                                : root.ctxOpen === "sink" ? "Вывод"
                                : root.ctxOpen === "source" ? "Вход"
                                : root.ctxOpen === "battery" ? "Батарея · " + Battery.pct + "%" : "Питание"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 13 * root.s
                            font.weight: Font.DemiBold
                        }
                    }

                    // mute для аудио-меню
                    Rectangle {
                        visible: root.ctxOpen === "sink" || root.ctxOpen === "source"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26 * root.s
                        height: 26 * root.s
                        radius: Theme.radiusS * root.s
                        color: ctxMuteArea.containsMouse
                               || (root.ctxOpen === "sink" ? Audio.sinkMute : Audio.srcMute)
                               ? Theme.veilHover : Theme.veil

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 13 * root.s
                            height: 13 * root.s
                            name: root.ctxOpen === "sink"
                                  ? (Audio.sinkMute ? "x" : "volume")
                                  : (Audio.srcMute ? "x" : "mic")
                            level: root.ctxOpen === "sink" && !Audio.sinkMute ? Audio.sinkVol : -1
                            color: (root.ctxOpen === "sink" ? Audio.sinkMute : Audio.srcMute) ? Theme.danger : Theme.dim
                        }

                        MouseArea {
                            id: ctxMuteArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ctxOpen === "sink" ? Audio.toggleSinkMute() : Audio.toggleSrcMute()
                        }
                    }
                }

                // ── выключенный радиомодуль ──
                Column {
                    visible: root.ctxOpen === "wifi" && !Net.wifiOn
                    width: parent.width
                    spacing: 8 * root.s

                    Rectangle {
                        width: parent.width
                        height: 28 * root.s
                        radius: 9 * root.s
                        color: wifiOnArea.containsMouse ? Theme.veilHover : Theme.veil

                        Text {
                            anchors.centerIn: parent
                            text: "Включить"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                        }

                        MouseArea {
                            id: wifiOnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Net.toggleWifi()
                        }
                    }
                }

                Column {
                    visible: root.ctxOpen === "bt" && !BT.powered
                    width: parent.width
                    spacing: 8 * root.s

                    Rectangle {
                        width: parent.width
                        height: 28 * root.s
                        radius: 9 * root.s
                        color: btOnArea.containsMouse ? Theme.veilHover : Theme.veil

                        Text {
                            anchors.centerIn: parent
                            text: "Включить"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                        }

                        MouseArea {
                            id: btOnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BT.togglePower()
                        }
                    }
                }

                // ── Wi-Fi: список сетей ──
                Flickable {
                    id: wifiFlick
                    visible: root.ctxOpen === "wifi" && Net.wifiOn
                    width: parent.width
                    height: Math.min(contentHeight, 350 * root.s)
                    contentWidth: width
                    contentHeight: wifiList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // при пересборке списка возвращаем позицию скролла.
                    // keepY пишем только пока список реально скроллится
                    // (contentHeight > height): при пересборке делегаты
                    // уничтожаются, высота схлопывается до высоты окна —
                    // сохранить уже сброшенный в 0 contentY нельзя
                    property real keepY: 0
                    onContentHeightChanged: if (contentHeight > height)
                        contentY = Math.max(0, Math.min(keepY, contentHeight - height))
                    onContentYChanged: if (contentHeight > height) keepY = contentY

                    Column {
                        id: wifiList
                        width: parent.width
                        spacing: 6 * root.s

                        // ── заголовок ──

                        Text {
                            width: parent.width
                            visible: Net.connectFailed
                            text: "Не удалось подключиться"
                            color: Theme.danger
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                        }

                        Text {
                            width: parent.width
                            visible: root.sorted.length === 0
                            text: root.scanning ? "Поиск сетей…" : "Сети не найдены"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // ── список сетей ──
                        Repeater {
                            model: root.sorted

                            delegate: Column {
                                id: netEntry

                                required property var modelData

                                readonly property string ssid: modelData.name || ""
                                readonly property bool connected: modelData.connected
                                readonly property bool known: Net.knownProfiles[ssid] === true
                                readonly property bool secured: Net.isSecured(ssid)
                                readonly property bool expanded: root.expandedSsid === ssid
                                // неизвестная сеть: клик разворачивает в строке поле пароля
                                readonly property bool askPw: expanded && !connected && !known

                                width: wifiList.width

                                Rectangle {
                                    width: parent.width
                                    height: netEntry.askPw ? 46 * root.s : 38 * root.s
                                    radius: Theme.radiusS * root.s
                                    color: netRowArea.containsMouse || netEntry.expanded ? Theme.veilHover : "transparent"

                                    // клик-зона ДО контента: поле пароля и глаз
                                    // остаются поверх и получают свои клики
                                    MouseArea {
                                        id: netRowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: netEntry.askPw ? Qt.IBeamCursor : Qt.PointingHandCursor
                                        onClicked: {
                                            if (netEntry.askPw) {
                                                root.grabKeys(pwInput);
                                            } else if (netEntry.connected || netEntry.known) {
                                                root.expandedSsid = netEntry.expanded ? "" : netEntry.ssid;
                                            } else if (netEntry.secured) {
                                                root.expandedSsid = netEntry.ssid;
                                                root.grabKeys(pwInput);
                                            } else {
                                                root.expandedSsid = "";
                                                root.releaseKeys();
                                                Net.connectSsid(netEntry.ssid);
                                            }
                                        }
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10 * root.s
                                        anchors.rightMargin: 10 * root.s
                                        spacing: 9 * root.s

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 17 * root.s
                                            height: 17 * root.s
                                            name: "wifi"
                                            level: Math.max(0.12, (netEntry.modelData.signalStrength || 0) / 100)
                                            color: netEntry.connected ? Theme.accent : Theme.dim
                                        }

                                        // неизвестная сеть: вместо имени — поле пароля
                                        TextInput {
                                            id: pwInput
                                            property bool showPw: false

                                            visible: netEntry.askPw
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: netEntry.askPw ? parent.width - 70 * root.s : 0
                                            echoMode: showPw ? TextInput.Normal : TextInput.Password
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 12.5 * root.s
                                            clip: true
                                            selectionColor: Theme.accentDim
                                            verticalAlignment: TextInput.AlignVCenter

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: pwInput.text.length === 0 && !pwInput.activeFocus
                                                text: "Пароль…"
                                                color: Theme.faint
                                                font.family: Theme.font
                                                font.pixelSize: 12.5 * root.s
                                            }

                                            onAccepted: {
                                                Net.connectWithPassword(netEntry.ssid, pwInput.text);
                                                root.releaseKeys();
                                                root.expandedSsid = "";
                                            }
                                            onActiveFocusChanged: {
                                                if (activeFocus) root.wantsKeys = true;
                                                else root.releaseKeys();
                                            }
                                        }

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: netEntry.secured && !netEntry.askPw
                                            width: 11 * root.s
                                            height: 11 * root.s
                                            name: "lock"
                                            color: Theme.faint
                                            stroke: 2.2
                                        }

                                        Text {
                                            visible: !netEntry.askPw
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 70 * root.s
                                            text: netEntry.ssid
                                            color: netEntry.connected ? Theme.text : Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 12.5 * root.s
                                            elide: Text.ElideRight
                                        }

                                        // показать/скрыть вводимый пароль
                                        Item {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: netEntry.askPw
                                            width: 15 * root.s
                                            height: 15 * root.s

                                            GlyphIcon {
                                                anchors.fill: parent
                                                name: pwInput.showPw ? "eyeOff" : "eye"
                                                color: pwEyeArea.containsMouse ? Theme.text : Theme.faint
                                                stroke: 2
                                            }

                                            MouseArea {
                                                id: pwEyeArea
                                                anchors.fill: parent
                                                anchors.margins: -5 * root.s
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    pwInput.showPw = !pwInput.showPw;
                                                    pwInput.forceActiveFocus();
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── раскрытая панель ──
                                Column {
                                    width: parent.width
                                    spacing: 7 * root.s
                                    visible: netEntry.expanded

                                    // воздушный зазор между именем сети и кнопками
                                    Item {
                                        width: 1
                                        height: visible ? 3 * root.s : 0
                                        visible: netEntry.expanded
                                    }

                                // ── действия: прямоугольные кнопки без подписей ──
                                Row {
                                    width: parent.width
                                    height: 28 * root.s
                                    spacing: 6 * root.s
                                    visible: netEntry.expanded && (netEntry.connected || netEntry.known)

                                    Repeater {
                                        model: [
                                            { icon: netEntry.connected ? "x" : "check",
                                              act: netEntry.connected ? "disc" : "conn" },
                                            { icon: "share", act: "share" },
                                            { icon: "trash", act: "forget" }
                                        ]

                                        delegate: Rectangle {
                                            id: netAct

                                            required property var modelData

                                            width: (netEntry.width - 12 * root.s) / 3
                                            height: 28 * root.s
                                            radius: 10 * root.s
                                            color: netActArea.containsMouse
                                                   ? (netAct.modelData.act === "forget" ? Theme.danger
                                                        : netAct.modelData.act === "share" ? Theme.accentDim : Theme.veilHover)
                                                   : Theme.veil
                                            border.width: 1
                                            border.color: netActArea.containsMouse ? Theme.accentDim : Theme.border
                                            scale: netActArea.pressed ? 0.94 : 1
                                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                                            GlyphIcon {
                                                anchors.centerIn: parent
                                                width: 14 * root.s
                                                height: 14 * root.s
                                                name: netAct.modelData.icon
                                                color: netActArea.containsMouse && netAct.modelData.act === "forget"
                                                       ? "#111318" : Theme.text
                                            }

                                            MouseArea {
                                                id: netActArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (netAct.modelData.act === "forget") {
                                                        root.expandedSsid = "";
                                                        Net.forget(netEntry.ssid);
                                                    } else if (netAct.modelData.act === "share") {
                                                        // QR растёт в пилюле: меню закрываем сразу
                                                        Net.makeQr(netEntry.ssid);
                                                        UIState.toggleSurface(root.screenName, "netqr");
                                                    } else if (netEntry.connected) {
                                                        root.expandedSsid = "";
                                                        Net.disconnectWifi();
                                                    } else {
                                                        root.expandedSsid = "";
                                                        Net.connectSsid(netEntry.ssid);
                                                    }
                                                }
                                            }
                                        }
                                    }

                                }
                            }
                        }
                    }
                }
                }

                // ── Bluetooth: устройства ──
                Flickable {
                    id: btFlick
                    visible: root.ctxOpen === "bt" && BT.powered
                    width: parent.width
                    height: Math.min(contentHeight, 380 * root.s)
                    contentWidth: width
                    contentHeight: btList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // то же сохранение позиции при пересборке
                    property real keepY: 0
                    onContentHeightChanged: if (contentHeight > height)
                        contentY = Math.max(0, Math.min(keepY, contentHeight - height))
                    onContentYChanged: if (contentHeight > height) keepY = contentY

                    Column {
                        id: btList
                        width: parent.width
                        spacing: 6 * root.s

                        Text {
                            width: parent.width
                            visible: BT.devices.length === 0
                            text: "Устройства не найдены"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // ── устройства ──
                        Repeater {
                            model: root.btSorted

                            delegate: Rectangle {
                                id: btDev

                                required property var modelData

                                readonly property bool expanded: root.expandedMac === modelData.mac

                                width: btList.width
                                height: btDevCol.implicitHeight + 8 * root.s
                                radius: Theme.radiusS * root.s
                                color: btDevArea.containsMouse || btDev.expanded ? Theme.veilHover : "transparent"
                                border.width: btDev.expanded ? 1 : 0
                                border.color: Theme.accentDim

                                // клик-зона объявлена ДО контента: кнопки панели
                                // действий остаются поверх и получают свои клики
                                MouseArea {
                                    id: btDevArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (btDev.modelData.paired)
                                            root.expandedMac = btDev.expanded ? "" : btDev.modelData.mac;
                                        else
                                            BT.pairAndConnect(btDev.modelData.mac);
                                    }
                                }

                                Column {
                                    id: btDevCol
                                    anchors.fill: parent
                                    anchors.margins: 4 * root.s

                                    Row {
                                        width: parent.width
                                        height: 30 * root.s
                                        spacing: 9 * root.s

                                        GlyphIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 15 * root.s
                                            height: 15 * root.s
                                            name: "bt"
                                            color: btDev.modelData.connected ? Theme.ok
                                                 : btDev.modelData.paired ? Theme.accent : Theme.faint
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 24 * root.s
                                            text: btDev.modelData.name.length ? btDev.modelData.name : btDev.modelData.mac
                                            color: btDev.modelData.connected ? Theme.text : Theme.dim
                                            font.family: Theme.font
                                            font.pixelSize: 12 * root.s
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // ── действия: прямоугольные кнопки без подписей ──
                                    Item {
                                        width: 1
                                        height: visible ? 2 * root.s : 0
                                        visible: btDev.expanded
                                    }

                                    Row {
                                        visible: btDev.expanded
                                        width: parent.width
                                        height: visible ? 28 * root.s : 0
                                        spacing: 6 * root.s

                                        Repeater {
                                            model: [
                                                { icon: btDev.modelData.connected ? "x" : "bt",
                                                  act: btDev.modelData.connected ? "disc" : "conn" },
                                                { icon: "trash", act: "forget" }
                                            ]

                                            delegate: Rectangle {
                                                id: btAct

                                                required property var modelData

                                                width: (btDev.width - 6 * root.s) / 2
                                                height: 28 * root.s
                                                radius: 10 * root.s
                                                color: btActArea.containsMouse
                                                       ? (btAct.modelData.act === "forget" ? Theme.danger : Theme.veilHover)
                                                       : Theme.veil
                                                border.width: 1
                                                border.color: btActArea.containsMouse ? Theme.accentDim : Theme.border
                                                scale: btActArea.pressed ? 0.94 : 1
                                                Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                                Behavior on color { ColorAnimation { duration: Motion.fast } }

                                                GlyphIcon {
                                                    anchors.centerIn: parent
                                                    width: 14 * root.s
                                                    height: 14 * root.s
                                                    name: btAct.modelData.icon
                                                    color: btActArea.containsMouse && btAct.modelData.act === "forget"
                                                           ? "#111318" : Theme.text
                                                }

                                                MouseArea {
                                                    id: btActArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (btAct.modelData.act === "forget") {
                                                            root.expandedMac = "";
                                                            BT.remove(btDev.modelData.mac);
                                                        } else if (btDev.modelData.connected) {
                                                            root.expandedMac = "";
                                                            BT.disconnect(btDev.modelData.mac);
                                                        } else {
                                                            root.expandedMac = "";
                                                            BT.connect(btDev.modelData.mac);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                }
                            }
                        }
                    }
                }

                // ── устройства вывода/входа ──
                Column {
                    id: devCol
                    visible: root.ctxOpen === "sink" || root.ctxOpen === "source"
                    width: parent.width
                    spacing: 4 * root.s

                    Repeater {
                        model: root.ctxOpen === "sink" ? root.sinks.slice(0, 4)
                             : root.ctxOpen === "source" ? root.sources.slice(0, 3)
                             : []

                        delegate: DevRow {
                            required property var modelData

                            width: devCol.width
                            s: root.s
                            label: root.nodeLabel(modelData)
                            active: root.ctxOpen === "sink" ? modelData.id === root.sinkId
                                                            : modelData.id === root.srcId
                            dotColor: root.ctxOpen === "sink" ? Theme.accent : Theme.warn
                            onPicked: {
                                if (root.ctxOpen === "sink")
                                    Audio.setDefaultSink(modelData.id);
                                else
                                    Audio.setDefaultSource(modelData.id);
                                root.closeCtx();
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.ctxOpen === "sink" ? root.sinks.length === 0 : root.sources.length === 0
                        text: "Нет устройств"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // ── батарея: профиль иконками + авто-экономия ──
                Column {
                    visible: root.ctxOpen === "battery"
                    width: parent.width
                    spacing: 8 * root.s

                    Text {
                        width: parent.width
                        height: 14 * root.s
                        verticalAlignment: Text.AlignVCenter
                        // именно visible: через opacity строка продолжала бы
                        // занимать место и оставляла пустой зазор в меню
                        visible: Battery.charging
                        text: "Заряжается"
                              + (Battery.hasTime ? " · " + Battery.timeStr + " до полной" : "")
                        color: Battery.low ? Theme.danger : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }

                    Text {
                        width: parent.width
                        visible: !Battery.hasProfiles
                        text: "Профили недоступны"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }

                    Row {
                        visible: Battery.hasProfiles
                        width: parent.width

                        Repeater {
                            model: [
                                { id: "performance", icon: "bolt",  cap: "Макс" },
                                { id: "balanced",    icon: "gauge", cap: "Баланс" },
                                { id: "power-saver", icon: "leaf",  cap: "Эконом" }
                            ]

                            delegate: Column {
                                id: profCol

                                required property var modelData
                                readonly property bool active: Battery.profile === modelData.id

                                width: parent.width / 3
                                spacing: 4 * root.s

                                Rectangle {
                                    id: profBtn
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 46 * root.s
                                    height: 46 * root.s
                                    radius: height / 2
                                    color: profCol.active ? Theme.accent
                                                          : (profBtnArea.containsMouse ? Theme.veilHover : Theme.veil)
                                    border.width: 1
                                    border.color: profCol.active ? Theme.accent : Theme.border
                                    scale: profBtnArea.pressed ? 0.92 : 1
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    GlyphIcon {
                                        anchors.centerIn: parent
                                        width: 19 * root.s
                                        height: 19 * root.s
                                        name: profCol.modelData.icon
                                        color: profCol.active ? "#111318" : Theme.dim
                                    }

                                    MouseArea {
                                        id: profBtnArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Battery.setProfile(profCol.modelData.id)
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: profCol.modelData.cap
                                    color: profCol.active ? Theme.text : Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 9.5 * root.s
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.hair }

                    Column {
                        id: saverCol

                        property real dragPct: -1
                        readonly property int shownPct: dragPct >= 0 ? dragPct : Battery.saverAt

                        width: parent.width
                        spacing: 4 * root.s

                        Text {
                            width: parent.width
                            text: "Авто-экономия: " + (saverCol.shownPct > 0 ? saverCol.shownPct + "%" : "выкл")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10.5 * root.s
                        }

                        Item {
                            id: saverSlider
                            width: parent.width
                            height: 32 * root.s

                            Fader {
                                id: saverFader
                                width: parent.width
                                s: root.s
                                step: 0.1
                                value: Battery.saverAt / 100
                                fillColor: Theme.accent
                                trackColor: Theme.hair
                                onMoved: (v) => saverCol.dragPct = Math.round(v * 100)
                                onCommitted: (v) => {
                                    saverCol.dragPct = -1;
                                    Battery.setSaverAt(Math.round(v * 100));
                                }
                            }

                            // деления каждые 10%
                            Repeater {
                                model: 11

                                delegate: Rectangle {
                                    required property int index

                                    x: 6 * root.s + (saverSlider.width - 12 * root.s) * index / 10 - width / 2
                                    y: saverFader.height + 2 * root.s
                                    width: 1
                                    height: 4 * root.s
                                    color: Theme.faint
                                }
                            }
                        }
                    }
                }

            }
        }
    }

    function go(name) {
        UIState.toggleSurface(root.screenName, name);
    }

    // горячие клавиши меняют звук/яркость вне бара — пока хаб открыт,
    // подтягиваем значения чаще фоновых пяти секунд
    Timer {
        interval: 600
        running: root.open
        repeat: true
        onTriggered: {
            Audio.refresh();
            Bright.refresh();
        }
    }

    // сети сами не ресканятся — обновляем список, пока панель открыта
    Timer {
        interval: 15000
        running: root.open
        repeat: true
        onTriggered: root.rescan()
    }

    // MPRIS не пушит позицию — подтягиваем раз в секунду
    Timer {
        interval: 1000
        running: root.open && root.mediaRow && Players.playing
        repeat: true
        onTriggered: if (root.p) root.p.positionChanged()
    }
}
