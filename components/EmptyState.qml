import QtQuick
import "../Singletons"

/**
 * Пустое состояние списка: иконка + заголовок + опциональная подсказка.
 * Центрируется в родителе.
 */
Column {
    id: root

    property real s: 1
    property string icon: ""
    property string title: ""
    property string hint: ""

    spacing: 10 * s

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 44 * s
        height: 44 * s
        radius: 14 * s
        color: Theme.veil
        border.width: 1
        border.color: Theme.border

        GlyphIcon {
            anchors.centerIn: parent
            width: 19 * s
            height: 19 * s
            name: root.icon
            color: Theme.faint
            stroke: 1.9
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.title.length > 0
        text: root.title
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 11 * s
        font.weight: Font.DemiBold
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.hint.length > 0
        text: root.hint
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * s
        horizontalAlignment: Text.AlignHCenter
    }
}
