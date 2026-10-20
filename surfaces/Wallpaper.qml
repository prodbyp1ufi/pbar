pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Карусель обоев: большое превью из ~/Pictures/Wallpapers, стрелки и ←/→
 * листают по кругу, Enter или клик по превью — применить (awww img, все
 * выходы). Esc не ловим: событие всплывает до FocusScope в shell.qml и
 * закрывает поверхность.
 */
PillSurface {
    id: root

    w: 430
    h: 440

    property int idx: 0

    readonly property var list: Wall.files
    readonly property string cur: list.length ? list[Math.min(idx, list.length - 1)] : ""
    readonly property bool isCurrent: Wall.currentPath.length > 0 && Wall.currentPath === cur

    readonly property string curPath: Wall.currentPath
    readonly property string fileName: cur.length ? cur.substring(cur.lastIndexOf("/") + 1) : ""

    // список и текущие обои могут догрузить асинхронный ls/query после открытия
    onListChanged: if (open) root.syncToCurrent()
    onCurPathChanged: if (open) root.syncToCurrent()

    onOpenChanged: if (open) {
        Wall.refresh();
        root.syncToCurrent();
        root.forceActiveFocus();
    }

    function syncToCurrent() {
        var i = Wall.files.indexOf(Wall.currentPath);
        idx = i >= 0 ? i : 0;
    }

    function step(d) {
        if (Wall.files.length < 2) return;
        idx = (idx + d + Wall.files.length) % Wall.files.length;
    }

    function applyCurrent() {
        if (root.cur.length)
            Wall.apply(root.cur);
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Left) {
            root.step(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.step(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applyCurrent();
            event.accepted = true;
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16 * root.s
        spacing: 10 * root.s

        // ── заголовок ──

        Text {

            width: parent.width

            height: 28 * root.s

            verticalAlignment: Text.AlignVCenter

            text: "Обои"

            color: Theme.text

            font.family: Theme.font

            font.pixelSize: Theme.fsTitle * root.s

            font.weight: Font.DemiBold

        }

        // ── превью ──
        Item {
            width: parent.width
            height: parent.height - 64 * root.s

            Rectangle {
                id: frame

                anchors.fill: parent
                radius: Theme.radiusL * root.s
                color: Theme.veil
                border.width: root.isCurrent ? 2 : 1
                border.color: root.isCurrent ? Theme.accent : Theme.border
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                Image {
                    anchors.fill: parent
                    anchors.margins: 8 * root.s
                    visible: root.cur.length > 0
                    source: root.cur.length ? "file://" + encodeURI(root.cur) : ""
                    // декод в размер превью, а не оригинальных 4K
                    sourceSize: Qt.size(width * 1.5, height * 1.5)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    cache: true
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.cur.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyCurrent()
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 12 * root.s
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * root.s
                    visible: root.isCurrent
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: width / 2
                    color: Theme.accent

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 12 * root.s
                        height: 12 * root.s
                        name: "check"
                        color: "#111318"
                        stroke: 2.6
                    }
                }

                Rectangle {
                    id: prevBtn

                    anchors.left: parent.left
                    anchors.leftMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34 * root.s
                    height: 34 * root.s
                    radius: width / 2
                    visible: root.list.length > 1
                    color: prevArea.containsMouse ? Theme.veilHover : Theme.veil
                    border.width: 1
                    border.color: Theme.border
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 15 * root.s
                        height: 15 * root.s
                        name: "chevron-left"
                        color: prevArea.containsMouse ? Theme.text : Theme.dim
                    }

                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.step(-1)
                    }
                }

                Rectangle {
                    id: nextBtn

                    anchors.right: parent.right
                    anchors.rightMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34 * root.s
                    height: 34 * root.s
                    radius: width / 2
                    visible: root.list.length > 1
                    color: nextArea.containsMouse ? Theme.veilHover : Theme.veil
                    border.width: 1
                    border.color: Theme.border
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 15 * root.s
                        height: 15 * root.s
                        name: "chevron-right"
                        color: nextArea.containsMouse ? Theme.text : Theme.dim
                    }

                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.step(1)
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: root.list.length === 0
                    s: root.s
                    icon: "image"
                    title: "Папка пуста"
                    hint: "сложи картинки в ~/Pictures/Wallpapers"
                }
            }
        }

        // ── подпись ──
        Text {
            width: parent.width
            height: 16 * root.s
            verticalAlignment: Text.AlignVCenter
            visible: root.fileName.length > 0
            text: root.fileName
                  + (root.list.length > 1 ? "  ·  " + (Math.min(root.idx, root.list.length - 1) + 1) + " / " + root.list.length : "")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
