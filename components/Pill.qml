pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "../Singletons"
import "../surfaces"

/**
 * Пилюля в стиле macOS. Свернута — компактный островок: [action] [время+дата]
 * [раскладка]. action живёт своей жизнью: играет музыка — эквалайзер, фокус
 * в приложении — его иконка, иначе — заряд батареи. Левый клик по пилюле
 * открывает Control Center (хаб), правый — центр уведомлений.
 * Открытая поверхность держится до Esc/клика мимо/повторного клика.
 *
 * Внутри окна пилюли живут также OSD (громкость/яркость/зарядка) и стопка
 * тостов уведомлений под пилюлей.
 */
Item {
    id: pill

    property real s: 1
    property string screenName: ""
    property var barWindow

    // тосты/OSD показываем только на фокусированном мониторе
    readonly property bool monFocused: screenName === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")

    // ── режимы свернутой пилюли: бар / OSD / тост ──
    // критический тост главнее OSD; OSD вытесняет некритические тосты
    readonly property bool toastCrit: {
        var ps = Notifs.popups;
        for (var i = 0; i < ps.length; i++)
            if (ps[i] && ps[i].urgency === NotificationUrgency.Critical) return true;
        return false;
    }
    readonly property bool osdMode: Osd.active && monFocused && !open && !toastCrit
    readonly property bool toastMode: Notifs.popups.length > 0 && monFocused && !open && !osdMode
    readonly property bool barMode: !open && !osdMode && !toastMode

    // OSD вытесняет некритический тост, иначе после OSD он «прилетит заново»
    onOsdModeChanged: if (osdMode) Notifs.retireTransient()

    readonly property real modH: 34 * s
    readonly property real barH: 46 * s
    readonly property real barPad: 12 * s

    // наведение — мягкая подсветка; открывают клики
    HoverHandler { id: pillHover }
    readonly property bool hovered: pillHover.hovered

    // спотлайт (лаунчер/буфер) рисуется в overlay отдельно — пилюля остаётся баром
    readonly property bool open: UIState.openSurface.length > 0 && UIState.openMon === screenName
                                 && !UIState.isSpotlight

    // поверхность закрыли (Esc/клик мимо), а курсор ещё на пилюле — вернуть хаб
    onOpenChanged: {
        if (open)
            curComp = comps[UIState.openSurface] !== undefined ? comps[UIState.openSurface] : null;
        else {
            closing = true;
            closeTimer.restart();
        }
    }

    // поверхность просит клавиатуру (поле пароля Wi-Fi в хабе и т.п.)
    readonly property bool wantsKeys: loader.item ? loader.item.wantsKeys : false

    // ── служебное: держим поверхность загруженной, пока идёт fade-out ──
    property bool closing: false

    Connections {
        target: UIState
        function onOpenSurfaceChanged() {
            if (pill.open && pill.comps[UIState.openSurface] !== undefined)
                pill.curComp = pill.comps[UIState.openSurface];
        }
    }

    Timer {
        id: closeTimer
        interval: 220
        onTriggered: pill.closing = false
    }

    // ── OSD-поток: громкость/микрофон/яркость/зарядка → Osd.show ──
    Connections {
        target: Audio
        function onSinkVolChanged() { if (!pill.open) Osd.show("vol", Audio.sinkVol, Audio.sinkMute); }
        function onSinkMuteChanged() { if (!pill.open) Osd.show("vol", Audio.sinkVol, Audio.sinkMute); }
        function onSrcVolChanged() { if (!pill.open) Osd.show("mic", Audio.srcVol, Audio.srcMute); }
        function onSrcMuteChanged() { if (!pill.open) Osd.show("mic", Audio.srcVol, Audio.srcMute); }
    }
    Connections {
        target: Bright
        function onFracChanged() { if (!pill.open) Osd.show("bright", Bright.frac, false); }
    }
    Connections {
        target: Battery
        // OSD только на подключение зарядки; при отключении пилюля не дёргается
        function onChargingChanged() {
            if (!pill.open && Battery.charging)
                Osd.show("charge", Battery.pct / 100, false, "");
        }
    }
    Connections {
        target: Osd
        function onActiveChanged() {
            if (Osd.active) Notifs.retireTransient();
        }
    }

    // ── данные модулей бара ──

    // action-слот: 3 — идёт запись экрана (высший приоритет), 2 — играет музыка
    // (эквалайзер), 1 — активное приложение, 0 — батарея
    readonly property int actionMode: Shot.recording ? 3
                                     : (Players.playing ? 2
                                     : (HyprInfo.activeClass.length > 0 ? 1 : 0))

    // биндинги держат синглтоны живыми с момента старта бара
    // (cliphist watch, опрос ресурсов)
    readonly property int keepClip: Clip.entries.length
    readonly property int keepRes: Res.cpuHist.length

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ── геометрия-морф ──
    readonly property real barW: barRow.implicitWidth + 2 * barPad
    // OSD не меняет ширину пилюли
    readonly property real osdW: Math.max(barW, osdCore.width + 2 * barPad)
    readonly property real toastW: 384 * s
    readonly property real toastH: toastLoader.active && toastLoader.item
        ? toastLoader.item.implicitHeight + 22 * s : barH
    readonly property real targetW: open ? (loader.item ? loader.item.surfW : 420 * s)
        : (osdMode ? osdW : (toastMode ? toastW : barW))
    readonly property real targetH: open ? (loader.item ? loader.item.surfH : 300 * s)
        : (toastMode ? toastH : barH)

    width: targetW
    height: targetH

    Behavior on width {
        NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
    }
    Behavior on height {
        NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
    }

    // ── фон: стеклянная карточка ──
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: pill.open ? Theme.radiusL * pill.s : Math.min(height / 2, 24 * pill.s)
        Behavior on radius { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard } }

        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.glassTop }
            GradientStop { position: 1.0; color: Theme.glassBot }
        }
        border.width: 1
        border.color: Theme.glassBorder

        // блик по верхнему краю
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1 * pill.s
            anchors.left: parent.left
            anchors.leftMargin: 20 * pill.s
            anchors.right: parent.right
            anchors.rightMargin: 20 * pill.s
            height: 1
            color: Theme.glassSheen
        }

        // мягкая подсветка при наведении
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.veil
            opacity: pill.hovered && !pill.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        // непрозрачная подложка открытой поверхности: стекло — только у пилюли
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.cardTop }
                GradientStop { position: 1.0; color: Theme.cardBot }
            }
            opacity: pill.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 1.0
            shadowVerticalOffset: 5 * pill.s
        }
    }

    // ── свернутый бар ──
    Row {
        id: barRow
        anchors.centerIn: parent
        spacing: 13 * pill.s
        // бар всегда в раскладке — морфим только прозрачностью, иначе
        // implicitWidth у скрытого Row схлопнется и пилюля «потеряет» ширину
        opacity: pill.barMode ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        // индикатор записи переехал в action-слот пилюли (высший приоритет)

        // ── action-слот: запись → таймер, музыка → эквалайзер, приложение → иконка, иначе батарея ──
        Item {
            id: actionSlot
            anchors.verticalCenter: parent.verticalCenter
            width: 40 * pill.s
            height: pill.modH - 8 * pill.s

            property int recTick: 0

            function recLabel() {
                void recTick;
                var sec = Math.max(0, Math.floor((Date.now() - Shot.recStart) / 1000));
                var m = Math.floor(sec / 60);
                var s = sec % 60;
                return m + ":" + (s < 10 ? "0" : "") + s;
            }

            Timer {
                interval: 1000
                running: Shot.recording
                repeat: true
                onTriggered: actionSlot.recTick++
            }

            // запись экрана — пульсирующая точка + время
            Row {
                anchors.centerIn: parent
                spacing: 6 * pill.s
                opacity: pill.actionMode === 3 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8 * pill.s
                    height: 8 * pill.s
                    radius: width / 2
                    color: Theme.danger

                    SequentialAnimation on opacity {
                        running: Shot.recording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: actionSlot.recLabel()
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: 12.5 * pill.s
                    font.weight: Font.DemiBold
                }
            }

            // эквалайзер
            Item {
                anchors.centerIn: parent
                width: 18 * pill.s
                height: 16 * pill.s
                opacity: pill.actionMode === 2 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                Repeater {
                    model: 4

                    Rectangle {
                        required property int index
                        anchors.bottom: parent.bottom
                        x: index * 5 * pill.s
                        width: 3 * pill.s
                        radius: width / 2
                        color: Theme.accent
                        height: 4 * pill.s

                        SequentialAnimation on height {
                            // пилюля не в bar-режиме — эквалайзер скрыт, анимацию гасим
                            running: pill.barMode && Players.playing
                            loops: Animation.Infinite
                            NumberAnimation { to: 15 * pill.s; duration: 300 + index * 90; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 4 * pill.s; duration: 300 + (3 - index) * 90; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }

            // иконка активного приложения
            Item {
                anchors.centerIn: parent
                width: 22 * pill.s
                height: 22 * pill.s
                opacity: pill.actionMode === 1 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                Image {
                    anchors.centerIn: parent
                    width: 18 * pill.s
                    height: 18 * pill.s
                    source: AppIcon.iconPath
                    asynchronous: true
                    mipmap: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(width * 2, height * 2)
                    visible: AppIcon.iconPath.length > 0 && status === Image.Ready
                }
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 15 * pill.s
                    height: 15 * pill.s
                    name: "window"
                    color: Theme.dim
                    visible: AppIcon.iconPath.length === 0
                }
            }

            // батарея — только процент: зарядка → зелёный, <25% → красный, иначе обычный
            Text {
                anchors.centerIn: parent
                opacity: pill.actionMode === 0 ? 1 : 0
                visible: opacity > 0 && Battery.present
                text: Battery.pct + "%"
                color: Battery.charging ? Theme.ok
                     : (Battery.pct < 25 ? Theme.danger : Theme.dim)
                font.family: Theme.font
                font.pixelSize: 14.5 * pill.s
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
        }

        // ── время + дата ──
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * pill.s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 14.5 * pill.s
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: clock.date.toLocaleDateString(Qt.locale("ru_RU"), "ddd d MMM")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * pill.s
            }
        }

        // ── раскладка (слот той же ширины, что и action — время ровно по центру) ──
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 40 * pill.s
            height: pill.modH - 8 * pill.s

            Text {
                anchors.centerIn: parent
                text: HyprInfo.kbLayout
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 14.5 * pill.s
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
        }
    }

    // ── клики по свернутой пилюле: левый — Control Center, правый — уведомления ──
    MouseArea {
        anchors.fill: barRow
        visible: pill.barMode
        enabled: pill.barMode
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                UIState.toggleSurface(pill.screenName, "notifs");
            else
                UIState.toggleSurface(pill.screenName, "hub");
        }
    }

    // ── открытая поверхность ──
    Loader {
        id: loader
        anchors.fill: parent
        active: pill.open || pill.closing
        sourceComponent: pill.open ? pill.comps[UIState.openSurface] : pill.curComp
    }

    // ── OSD внутри пилюли: [иконка] — тонкая полоска — [%], как в ukishima ──
    Item {
        id: osdCore

        readonly property bool vol: Osd.kind === "vol"
        readonly property bool mic: Osd.kind === "mic"
        readonly property bool bright: Osd.kind === "bright"
        readonly property bool charge: Osd.kind === "charge"
        readonly property bool off: Osd.off

        anchors.centerIn: parent
        width: rows.implicitWidth
        height: 26 * pill.s
        opacity: pill.osdMode ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        Row {
            id: rows
            anchors.centerIn: parent
            spacing: 11 * pill.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * pill.s
                height: 16 * pill.s
                name: osdCore.charge ? "battery"
                    : (osdCore.bright ? "sun" : (osdCore.mic ? "mic" : "volume"))
                color: osdCore.off ? Theme.faint
                    : ((osdCore.charge || osdCore.mic) ? Theme.ok : Theme.text)
                level: osdCore.charge || osdCore.off || osdCore.mic ? -1 : Osd.value
                fill: osdCore.charge ? Osd.value : -1
                bolt: osdCore.charge
                stroke: 1.9
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 108 * pill.s
                height: 4 * pill.s
                radius: 2 * pill.s
                color: Theme.hair

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(0, Math.min(1, Osd.value)) * parent.width
                    radius: parent.radius
                    color: osdCore.off ? Theme.faint
                        : ((osdCore.charge || osdCore.mic) ? Theme.ok : Theme.accent)
                    Behavior on width { NumberAnimation { duration: Motion.fast } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 30 * pill.s
                text: osdCore.off ? "off" : Math.round(Math.max(0, Math.min(1, Osd.value)) * 100) + "%"
                color: osdCore.off ? Theme.faint : Theme.text
                font.family: Theme.font
                font.pixelSize: 11 * pill.s
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    // ── тост в теле пилюли: иконка + приложение + заголовок + текст ──
    Loader {
        id: toastLoader

        property var cur: Notifs.popups.length > 0 ? Notifs.popups[Notifs.popups.length - 1] : null
        readonly property int extra: Math.max(0, Notifs.popups.length - 1)

        anchors.centerIn: parent
        // ширина фикс — иначе цикл биндингов (контент растёт от ширины пилюли)
        width: pill.toastW - 28 * pill.s
        height: item ? item.implicitHeight : 0
        opacity: pill.toastMode ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        sourceComponent: Item {
            id: toastRoot

            property var n: toastLoader.cur
            property bool crit: n ? n.urgency === NotificationUrgency.Critical : false
            property string iconSrc: n ? Notifs.iconFor(n) : ""

            readonly property int life: crit ? 8000 : 4600

            width: toastLoader.width
            implicitHeight: Math.max(28 * pill.s, toastRow.implicitHeight)

            // новое уведомление — таймер жизни заново
            onNChanged: lifeT.restart()

            Timer {
                id: lifeT
                interval: toastRoot.life
                running: toastRoot.n !== null && pill.toastMode && !toastRoot.crit
                onTriggered: {
                    var n = toastRoot.n;
                    if (n) Notifs.dismissNotif(n);
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (toastRoot.n) Notifs.activatePopup(toastRoot.n);
                    else Notifs.clearPopups();
                }
            }

            Row {
                id: toastRow
                anchors.fill: parent
                spacing: 10 * pill.s

                Rectangle {
                    id: tile
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28 * pill.s
                    height: 28 * pill.s
                    radius: 9 * pill.s
                    color: toastRoot.crit ? Theme.accentSoft : Theme.veil
                    border.width: 1
                    border.color: Theme.hair

                    Image {
                        anchors.fill: parent
                        anchors.margins: toastRoot.iconSrc.length > 0 && toastRoot.n && toastRoot.n.image ? 0 : 6 * pill.s
                        source: toastRoot.iconSrc
                        sourceSize.width: 56
                        sourceSize.height: 56
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        visible: toastRoot.iconSrc.length > 0
                    }

                    GlyphIcon {
                        anchors.centerIn: parent
                        visible: toastRoot.iconSrc.length === 0
                        width: 13 * pill.s
                        height: 13 * pill.s
                        name: toastRoot.crit ? "power" : "bell"
                        color: toastRoot.crit ? Theme.danger : Theme.dim
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - tile.width - toastRow.spacing - (expW.visible ? expW.width + toastRow.spacing : 0)
                    spacing: 2 * pill.s

                Text {
                    width: parent.width
                    visible: toastRoot.n && (toastRoot.n.appName || "").length > 0
                    text: toastRoot.n ? toastRoot.n.appName : ""
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 8.5 * pill.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2 * pill.s
                    elide: Text.ElideRight
                }

                Row {
                    width: parent.width
                    spacing: 5 * pill.s

                    Rectangle {
                        visible: toastRoot.crit
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8 * pill.s
                        height: 8 * pill.s
                        color: "transparent"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 * pill.s
                            height: 8 * pill.s
                            radius: width / 2
                            color: Theme.danger
                            opacity: 0.3
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 4 * pill.s
                            height: 4 * pill.s
                            radius: width / 2
                            color: Theme.danger
                        }
                    }

                    Text {
                        width: parent.width - (toastRoot.crit ? 12 * pill.s : 0)
                        text: toastRoot.n ? (toastRoot.n.summary || "") : ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11.5 * pill.s
                        font.weight: Font.DemiBold
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }
                }

                Text {
                    width: parent.width
                    visible: toastRoot.n && (toastRoot.n.body || "").length > 0
                    text: toastRoot.n ? (toastRoot.n.body || "") : ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * pill.s
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            // «+N» — остальные уведомления в стопке
            Rectangle {
                id: expW
                anchors.verticalCenter: parent.verticalCenter
                visible: toastLoader.extra > 0
                width: 26 * pill.s
                height: 18 * pill.s
                radius: height / 2
                color: Theme.veil
                border.width: 1
                border.color: Theme.hair

                Text {
                    anchors.centerIn: parent
                    text: "+" + toastLoader.extra
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 9.5 * pill.s
                    font.weight: Font.DemiBold
                }
            }
            }
        }
    }

    property Component curComp: null

    readonly property var comps: ({
        hub: compHub,
        calendar: compCalendar,
        mixer: compMixer,
        wifi: compWifi,
        bt: compBt,
        netqr: compNetQr,
        connections: compConnections,
        shot: compShot,
        wall: compWall,
        res: compRes,
        media: compMedia,
        battery: compBattery,
        power: compPower,
        notifs: compNotifs,
        tint: compTint
    })

    Component {
        id: compHub
        Hub {
            s: pill.s
            open: pill.open
            screenName: pill.screenName
            barWindow: pill.barWindow
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compCalendar
        Calendar {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compMixer
        Mixer {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compWifi
        Wifi {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compBt
        Bluetooth {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compNetQr
        NetQr {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compConnections
        ConnectionsPanel {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compShot
        ShotSurface {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compWall
        Wallpaper {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compRes
        Resources {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compMedia
        Media {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compBattery
        BatterySurface {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compPower
        Power {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compNotifs
        NotifCenter {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }
    Component {
        id: compTint
        Tint {
            s: pill.s
            open: pill.open
            onRequestClose: UIState.close()
        }
    }

    // ── модуль бара: подложка-ховер + Row контента + клик-роутинг ──
    component Mod: Item {
        id: mod

        default property alias content: modRow.data
        property string surf: ""
        property bool interactive: true
        property bool hoverable: true
        readonly property bool hovered: mArea.containsMouse

        width: implicitWidth
        height: pill.modH - 6 * pill.s
        implicitWidth: modRow.implicitWidth + 2 * 9 * pill.s

        Rectangle {
            anchors.fill: parent
            radius: 10 * pill.s
            color: mod.interactive && mArea.containsMouse ? Theme.veilHover : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Row {
            id: modRow
            anchors.centerIn: parent
            spacing: 7 * pill.s
        }

        MouseArea {
            id: mArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: mod.interactive
            cursorShape: mod.surf.length ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (mod.surf.length) UIState.toggleSurface(pill.screenName, mod.surf)
        }
    }

    // тонкий вертикальный разделитель между логическими группами модулей
    component ModSep: Item {
        width: 7 * pill.s
        height: pill.modH - 6 * pill.s

        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: 14 * pill.s
            radius: 0.5
            color: Theme.hair
        }
    }
}
