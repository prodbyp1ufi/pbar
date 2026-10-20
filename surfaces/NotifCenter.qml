pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Notifications
import "../Singletons"
import "../components"

/**
 * Центр уведомлений в стиле macOS: «облака», сгруппированные по приложениям.
 * Карточка группы — иконка и имя приложения, счётчик, время свежайшего;
 * внутри стопка уведомлений с крестиком у каждого и очисткой группы.
 * Живые и исторические записи объединены; тумблер «Не беспокоить», очистка.
 */
PillSurface {
    id: root

    w: 470
    h: 480

    property int tick: 0
    property var expandedApps: ({}); onOpenChanged: if (open) { Notifs.markAllSeen(); expandedApps = ({}) }

    function toggleGroup(app) {
        var m = {};
        for (var k in root.expandedApps) m[k] = root.expandedApps[k];
        m[app] = !m[app];
        root.expandedApps = m;
    }

    Timer {
        interval: 30000
        running: root.open
        repeat: true
        onTriggered: root.tick++
    }

    function ageLabel(ts) {
        void root.tick;
        var m = Math.floor((Date.now() - ts) / 60000);
        if (m < 1) return "сейчас";
        if (m < 60) return m + " мин";
        var h = Math.floor(m / 60);
        if (h < 24) return h + " ч";
        return Math.floor(h / 24) + " д";
    }

    // ── плоский список (живые + история), свежие сверху ──
    readonly property var entries: {
        void root.tick;
        var out = [];
        var t = Notifs.tracked;
        for (var i = 0; i < t.length; i++) {
            var n = t[i];
            out.push({
                live: true, n: n,
                app: (n.appName && n.appName.length) ? n.appName : "System",
                summary: n.summary || "",
                body: n.body || "",
                icon: Notifs.iconFor(n),
                critical: n.urgency === NotificationUrgency.Critical,
                ts: Date.now(),
                id: "live" + n.id
            });
        }
        var hist = Notifs.history;
        for (var j = 0; j < hist.length; j++) {
            var h = hist[j];
            out.push({
                live: false, n: null,
                app: h.app,
                summary: h.summary || "",
                body: h.body || "",
                icon: h.icon || "",
                critical: (h.urgency || 0) === NotificationUrgency.Critical,
                ts: h.ts || 0,
                id: h.id
            });
        }
        out.sort(function (a, b) { return b.ts - a.ts; });
        return out;
    }

    // ── группы по приложениям в порядке свежести ──
    readonly property var groups: {
        var g = [];
        var idx = {};
        var list = root.entries;
        for (var i = 0; i < list.length; i++) {
            var e = list[i];
            if (idx[e.app] === undefined) {
                idx[e.app] = g.length;
                g.push({ app: e.app, icon: e.icon, items: [], ts: e.ts });
            }
            g[idx[e.app]].items.push(e);
        }
        return g;
    }

    function dismissItem(e) {
        if (e.live)
            Notifs.dismissNotif(e.n);
        else
            Notifs.removeHistory(e.id);
    }

    function dismissGroup(items) {
        for (var i = 0; i < items.length; i++)
            root.dismissItem(items[i]);
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: 14 * root.s
        anchors.bottomMargin: 12 * root.s
        contentWidth: width
        contentHeight: innerCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: innerCol
            x: 16 * root.s
            width: flick.width - 32 * root.s
            spacing: 10 * root.s

            // ── заголовок ──
            Item {
                width: parent.width
                height: 28 * root.s

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Уведомления"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.fsTitle * root.s
                    font.weight: Font.DemiBold
                }

                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    icon: "trash"
                    activeTint: Theme.danger
                    onClicked: Notifs.clearAll()
                }
            }

            // ── облака по приложениям ──
            Repeater {
                model: root.groups

                delegate: Rectangle {
                    id: cloud

                    required property var modelData
                    required property int index

                    readonly property var items: modelData.items
                    readonly property bool expanded: root.expandedApps[cloud.modelData.app] === true

                    width: parent.width
                    // карточка = контент + верхний и нижний отступы колонки,
                    // иначе текст вылезает за нижний край (высота колонки
                    // считается от y = 12, а не от нуля карточки)
                    height: cloudCol.height + 24 * root.s
                    radius: Theme.radiusM * root.s

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.cardTop }
                        GradientStop { position: 1.0; color: Theme.cardBot }
                    }
                    border.width: 1
                    border.color: Theme.border

                    Column {
                        id: cloudCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12 * root.s
                        spacing: 9 * root.s

                        // ── шапка группы ──
                        Item {
                            width: parent.width
                            height: 32 * root.s

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleGroup(cloud.modelData.app)
                            }

                            Rectangle {
                                id: appBox
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30 * root.s
                                height: 30 * root.s
                                radius: 9 * root.s
                                color: Theme.veil

                                Image {
                                    anchors.centerIn: parent
                                    visible: cloud.modelData.icon.length > 0
                                    source: cloud.modelData.icon
                                    sourceSize.width: 40
                                    sourceSize.height: 40
                                    width: 19 * root.s
                                    height: 19 * root.s
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    asynchronous: true
                                }
                                GlyphIcon {
                                    anchors.centerIn: parent
                                    visible: cloud.modelData.icon.length === 0
                                    width: 15 * root.s
                                    height: 15 * root.s
                                    name: "bell"
                                    color: Theme.dim
                                }
                            }

                            IconButton {
                                id: groupClose
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                s: root.s * 0.85
                                icon: "x"
                                tint: Theme.faint
                                activeTint: Theme.text
                                onClicked: root.dismissGroup(cloud.items)
                            }

                            Text {
                                id: groupAge
                                anchors.right: groupClose.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.ageLabel(cloud.modelData.ts)
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 10.5 * root.s
                            }

                            GlyphIcon {
                                id: groupChev
                                anchors.right: groupCount.left
                                anchors.rightMargin: 6 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12 * root.s
                                height: 12 * root.s
                                name: "chevron-right"
                                rotation: cloud.expanded ? 90 : 0
                                color: Theme.dim
                                Behavior on rotation { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            Rectangle {
                                id: groupCount
                                anchors.right: groupAge.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                visible: cloud.items.length > 1
                                width: Math.max(16 * root.s, cntText.implicitWidth + 8 * root.s)
                                height: 18 * root.s
                                radius: height / 2
                                color: Theme.accentSoft
                                border.width: 1
                                border.color: Theme.accentDim

                                Text {
                                    id: cntText
                                    anchors.centerIn: parent
                                    text: cloud.items.length
                                    color: Theme.accent
                                    font.family: Theme.font
                                    font.pixelSize: 11 * root.s
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.left: appBox.right
                                anchors.leftMargin: 8 * root.s
                                anchors.right: groupCount.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: cloud.modelData.app
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 12 * root.s
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }

                        // ── уведомления группы ──
                        Repeater {
                            model: cloud.items

                            delegate: Column {
                                id: item

                                required property var modelData
                                required property int index

                                visible: cloud.expanded

                                // parent у делегата Repeater на миг null при
                                // разрушении — привязываемся к хосту облака
                                width: cloudCol.width
                                spacing: 5 * root.s

                                Rectangle {
                                    visible: item.index > 0
                                    width: item.width
                                    height: 1
                                    color: Theme.hair
                                }

                                Item {
                                    width: item.width
                                    height: itemSummary.implicitHeight

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: item.modelData.critical
                                        width: 5 * root.s
                                        height: 5 * root.s
                                        radius: width / 2
                                        color: Theme.danger
                                    }

                                    GlyphIcon {
                                        id: itemXIcon
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 11 * root.s
                                        height: 11 * root.s
                                        name: "x"
                                        color: itemXArea.containsMouse ? Theme.text : Theme.faint
                                        stroke: 2.2

                                        MouseArea {
                                            id: itemXArea
                                            anchors.fill: parent
                                            anchors.margins: -6 * root.s
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.dismissItem(item.modelData)
                                        }
                                    }

                                    Text {
                                        id: itemAge
                                        anchors.right: itemXIcon.left
                                        anchors.rightMargin: 8 * root.s
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.ageLabel(item.modelData.ts)
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 10 * root.s
                                    }

                                    Text {
                                        id: itemSummary
                                        anchors.left: parent.left
                                        anchors.leftMargin: item.modelData.critical ? 11 * root.s : 0
                                        anchors.right: itemAge.left
                                        anchors.rightMargin: 8 * root.s
                                        text: item.modelData.summary
                                        color: Theme.text
                                        font.family: Theme.font
                                        font.pixelSize: 12 * root.s
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    width: item.width
                                    visible: item.modelData.body.length > 0
                                    text: item.modelData.body
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11.5 * root.s
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 6
                                    elide: Text.ElideRight
                                    lineHeight: 1.15
                                }
                            }
                        }
                    }
                }
            }

            // ── пусто ──
            EmptyState {
                width: parent.width
                visible: root.entries.length === 0
                s: root.s
                icon: "bell"
                title: "Пусто"
                hint: "уведомления появятся здесь"
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
