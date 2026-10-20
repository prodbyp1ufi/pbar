import QtQuick
import "../Singletons"

/**
 * Тонкий скроллбар для списков. Объявляется прямым ребёнком Flickable
 * (ListView/GridView — тоже Flickable): не скроллится вместе с контентом,
 * якорится к краям списка. Thumb появляется при прокрутке и плавно гаснет.
 *
 * Использование:
 *   ListView {
 *       id: list ...
 *       SlimScroll { flick: list; s: root.s
 *                    anchors.right: parent.right
 *                    anchors.top: parent.top; anchors.bottom: parent.bottom }
 *   }
 */
Item {
    id: root

    property Flickable flick: null
    property real s: 1

    // скроллбар живёт вместе со своим списком: у невидимого Flickable
    // контент обновляется и полоса «выскакивает» в чужих меню
    visible: flick ? flick.visible : false

    width: 6 * s
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    states: State {
        name: "shown"
        when: root.flick && (root.flick.moving || root.flick.flicking)
              || thumbTimer.running
        PropertyChanges { target: root; opacity: 1 }
    }

    Timer {
        id: thumbTimer
        interval: 900
    }

    function thumbKick() { thumbTimer.restart(); }

    onFlickChanged: if (flick) {
        // любые изменения содержимого/прокрутки показывают полосу
        flick.onContentYChanged.connect(root.thumbKick);
        flick.onContentHeightChanged.connect(root.thumbKick);
    }

    Rectangle {
        id: track
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 3 * root.s
        radius: width / 2
        color: Theme.veil
        height: parent.height - 4 * root.s
        visible: root.flick && root.flick.contentHeight > root.flick.height + 1
    }

    Rectangle {
        id: thumb
        anchors.right: parent.right
        width: 3 * root.s
        radius: width / 2
        color: Theme.faint
        visible: track.visible && root.flick
                 && root.flick.contentHeight > root.flick.height + 1

        readonly property real span: track.height - height
        height: root.flick
                ? Math.max(24 * root.s, track.height * root.flick.height / Math.max(1, root.flick.contentHeight))
                : 0
        y: track.y + (root.flick
                ? -root.flick.contentY / Math.max(1, root.flick.contentHeight - root.flick.height) * span
                : 0)
    }
}
