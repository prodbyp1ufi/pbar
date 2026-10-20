import QtQuick
import "../Singletons"

/**
 * Квадратная иконочная кнопка (корзина, папка, обновить…).
 * Мягкая подложка, ховер, опциональный tint для акцентных действий.
 */
Rectangle {
    id: root

    property real s: 1
    property string icon: ""
    property real iconSize: 13
    property color tint: Theme.dim
    property color activeTint: Theme.text
    property real strokeW: 1.9
    property string label: ""

    signal clicked()

    width: 28 * s
    height: 28 * s
    radius: Theme.radiusS * s
    color: area.containsMouse ? Theme.veilHover : Theme.veil
    opacity: area.pressed ? 0.6 : 1
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    Accessible.role: Accessible.Button
    Accessible.name: root.label !== "" ? root.label : root.icon
    Accessible.onPressAction: root.clicked()

    GlyphIcon {
        anchors.centerIn: parent
        width: root.iconSize * root.s
        height: root.iconSize * root.s
        name: root.icon
        color: area.containsMouse ? root.activeTint : root.tint
        stroke: root.strokeW
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
