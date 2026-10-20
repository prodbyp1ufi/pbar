import QtQuick
import "../Singletons"

/**
 * Тумблер в стиле iOS: подложка подсвечивается активным цветом,
 * белый круглый knob плавно переезжает.
 */
Item {
    id: root

    property real s: 1
    property bool on: false
    property color activeColor: Theme.accent
    property string label: ""

    signal toggled()

    width: 34 * s
    height: 20 * s
    opacity: ma.pressed ? 0.7 : 1
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.checked: root.on
    Accessible.onToggleAction: root.toggled()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.on ? Qt.alpha(root.activeColor, 0.28) : Theme.veil
        border.width: 1
        border.color: root.on ? root.activeColor : Theme.border
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.on ? parent.width - width - 2 * root.s : 2 * root.s
            width: 16 * root.s
            height: 16 * root.s
            radius: width / 2
            color: root.on ? root.activeColor : Theme.dim
            Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
