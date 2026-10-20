pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../Singletons"
import "../components"

/**
 * Спотлайт-лаунчер: центрированная карточка с поиском по DesktopEntries.
 * Стрелки — навигация, Enter — запуск, Esc — закрыть. Если по запросу
 * приложения не нашлись — предлагает поискать в Google, открыть путь
 * в superfile или выполнить его в kitty.
 */
PillSurface {
    id: root

    w: 600
    readonly property int rowH: 44
    readonly property int maxVisible: 9
    // строка поиска + разделитель + отступы + видимые ряды
    // при непустом запросе высота зафиксирована на максимум — не прыгает при поиске
    h: 55 + 12 + (query.trim().length ? maxVisible : Math.max(1, Math.min(rows.length, maxVisible))) * (rowH + 2) + 12

    scale: open ? 1 : 0.96
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    property string query: ""

    function reset() {
        query = "";
        input.clear();
        list.currentIndex = 0;
        input.forceActiveFocus();
    }
    onOpenChanged: if (open) reset()
    Component.onCompleted: if (open) reset()

    readonly property var apps: {
        var src = DesktopEntries.applications.values;
        var q = query.trim().toLowerCase();
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var e = src[i];
            if (!e || e.noDisplay) continue;
            if (q.length) {
                var hay = ((e.name || "") + " " + (e.comment || "") + " " + (e.id || "")).toLowerCase();
                if (hay.indexOf(q) < 0) continue;
            }
            out.push(e);
        }
        out.sort(function (a, b) {
            var an = (a.name || "").toLowerCase();
            var bn = (b.name || "").toLowerCase();
            if (q.length) {
                var as = an.indexOf(q) === 0 ? 0 : 1;
                var bs = bn.indexOf(q) === 0 ? 0 : 1;
                if (as !== bs) return as - bs;
            }
            return an < bn ? -1 : (an > bn ? 1 : 0);
        });
        return out.slice(0, 40);
    }

    // приложения кончились, а запрос есть — показываем действия
    readonly property var actions: query.trim().length > 0 && apps.length === 0 ? [
        { action: "web",    icon: "globe",    label: "Искать «" + query.trim() + "» в интернете", caption: "Google" },
        { action: "folder", icon: "folder",   label: "Открыть в файловом менеджере", caption: "superfile" },
        { action: "term",   icon: "terminal", label: "Выполнить в терминале", caption: "kitty" }
    ] : []

    readonly property var rows: apps.length > 0 ? apps : actions

    function iconSrc(e) {
        var ic = e.icon || "";
        if (ic.length === 0)
            return Quickshell.hasThemeIcon("application-x-executable") ? Quickshell.iconPath("application-x-executable") : "";
        if (ic.charAt(0) === "/" || ic.indexOf("file://") === 0)
            return ic;
        return Quickshell.hasThemeIcon(ic) ? Quickshell.iconPath(ic) : "";
    }

    function activate(entry) {
        if (!entry) return;
        if (entry.action !== undefined) {
            runAction(entry.action);
            return;
        }
        if (typeof entry.execute === "function")
            entry.execute();
        UIState.close();
    }

    // запуски — в синглтоне Run: закрытие карточки уничтожило бы Process
    // вместе с поверхностью раньше, чем запущенный процесс отвяжется
    function runAction(kind) {
        var q = query.trim();
        if (kind === "web") Run.web(q);
        else if (kind === "term") Run.term(q);
        else if (kind === "folder") Run.folder(q);
        UIState.close();
    }

    SpotCard {
        anchors.fill: parent
        s: root.s
    }

    Column {
        anchors.fill: parent

        // ── строка поиска ──
        Item {
            width: parent.width
            height: 54 * root.s

            Row {
                anchors.fill: parent
                anchors.leftMargin: 20 * root.s
                anchors.rightMargin: 20 * root.s
                spacing: 12 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * root.s
                    height: 17 * root.s
                    name: "search"
                    color: input.activeFocus ? Theme.accent : Theme.dim
                    stroke: 2.2
                }

                TextInput {
                    id: input
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30 * root.s
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14 * root.s
                    clip: true
                    cursorVisible: activeFocus
                    selectionColor: Theme.accentDim
                    verticalAlignment: TextInput.AlignVCenter

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text.length === 0
                        text: "Поиск приложений…"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 14 * root.s
                    }

                    onTextChanged: {
                        root.query = text;
                        list.currentIndex = 0;
                    }
                    onAccepted: root.activate(root.rows[list.currentIndex])
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        // ── список ──
        Item {
            width: parent.width
            height: parent.height - 55 * root.s

            ListView {
                id: list
                anchors.fill: parent
                anchors.topMargin: 6 * root.s
                anchors.bottomMargin: 6 * root.s
                clip: true
                spacing: 2 * root.s
                model: root.rows
                currentIndex: 0

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: 44 * root.s

                readonly property bool isAction: row.modelData.action !== undefined
                readonly property bool isActive: list.currentIndex === index

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusS * root.s
                    color: rowArea.containsMouse || row.isActive ? Theme.veilHover : "transparent"
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3 * root.s
                    height: parent.height * 0.5
                    radius: width / 2
                    color: Theme.accent
                    opacity: row.isActive ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                // иконка приложения из темы
                Image {
                    id: icon
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24 * root.s
                    height: 24 * root.s
                    source: row.isAction ? "" : root.iconSrc(row.modelData)
                    sourceSize.width: 48
                    sourceSize.height: 48
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: !row.isAction && status === Image.Ready
                }

                // приложение без иконки в теме — рисуем свой глиф
                Rectangle {
                    anchors.left: icon.left
                    anchors.verticalCenter: icon.verticalCenter
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: 7 * root.s
                    color: Theme.veil
                    visible: !row.isAction && icon.status !== Image.Ready

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 14 * root.s
                        height: 14 * root.s
                        name: "grid"
                        color: Theme.dim
                    }
                }

                // глиф действия (globe/folder/terminal)
                Rectangle {
                    anchors.left: icon.left
                    anchors.verticalCenter: icon.verticalCenter
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: 7 * root.s
                    color: Theme.accentSoft
                    visible: row.isAction

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 14 * root.s
                        height: 14 * root.s
                        name: row.isAction ? row.modelData.icon : ""
                        color: Theme.accent
                    }
                }

                Text {
                    anchors.left: icon.right
                    anchors.leftMargin: 11 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 150 * root.s
                    text: row.isAction ? row.modelData.label : (row.modelData.name || "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12.5 * root.s
                    elide: Text.ElideRight
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110 * root.s
                    text: row.isAction ? (row.modelData.caption || "")
                                       : (row.modelData.comment || "")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activate(row.modelData)
                    onContainsMouseChanged: if (containsMouse) list.currentIndex = row.index
                }
            }

            }
        }
    }
}
