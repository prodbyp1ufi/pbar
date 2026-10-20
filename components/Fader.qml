import QtQuick
import "../Singletons"

/**
 * Горизонтальный фейдер (громкость, прогресс). Внешний value приходит
 * привязкой; во время перетаскивания показывается локальный dragVal, чтобы
 * привязка не ломалась — onMoved отдаёт значение наружу.
 */
Item {
    id: root

    property real s: 1
    property real value: 0
    property bool muted: false
    property color trackColor: Theme.veil
    property color fillColor: muted ? Theme.faint : Theme.accent
    property bool interactive: true
    property real step: 0   // 0 — плавно; иначе сетка значений (0.1 = 10%)

    signal moved(real v)
    signal committed(real v)

    implicitWidth: 180 * s
    implicitHeight: 22 * s
    width: implicitWidth
    height: implicitHeight

    property bool dragging: false
    property real dragVal: 0
    readonly property real shown: dragging ? dragVal : Math.max(0, Math.min(1, value))

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 6 * root.s
        width: parent.width - 12 * root.s
        height: 5 * root.s
        radius: height / 2
        color: root.trackColor
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 6 * root.s
        width: (parent.width - 12 * root.s) * root.shown
        height: 5 * root.s
        radius: height / 2
        color: root.fillColor
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 6 * root.s + (parent.width - 12 * root.s) * root.shown - width / 2
        width: 13 * root.s
        height: 13 * root.s
        radius: width / 2
        color: root.muted ? Theme.faint : Theme.text
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -6 * root.s
        anchors.bottomMargin: -6 * root.s
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onPressed: (mouse) => root.setFromX(mouse.x)
        onPositionChanged: (mouse) => { if (pressed) root.setFromX(mouse.x) }
        onReleased: {
            root.dragging = false;
            if (root.interactive)
                root.committed(root.dragVal);
        }
        onCanceled: root.dragging = false

        onWheel: (wheel) => {
            var st = root.step > 0 ? root.step : 0.05;
            var v = root.snap(root.shown + (wheel.angleDelta.y > 0 ? st : -st));
            root.dragging = true;
            root.dragVal = v;
            root.moved(v);
            root.committed(v);
            wheelAcceptTimer.restart();
        }
    }

    // после колесика держим локальное значение, пока внешняя привязка догоняет
    Timer {
        id: wheelAcceptTimer
        interval: 500
        onTriggered: root.dragging = false
    }

    function snap(v) {
        if (root.step <= 0) return Math.max(0, Math.min(1, v));
        return Math.max(0, Math.min(1, Math.round(v / root.step) * root.step));
    }

    function setFromX(x) {
        var v = root.snap((x - 6 * root.s) / (width - 12 * root.s));
        dragging = true;
        dragVal = v;
        moved(v);
    }
}
