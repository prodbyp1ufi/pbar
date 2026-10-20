import QtQuick
import "../Singletons"

/**
 * Премиум-карточка: мягкий градиент, тонкий бордер, блик по верхнему
 * краю. Базовый контейнер для группировки контента в поверхностях.
 */
Rectangle {
    id: root

    property real s: 1

    radius: Theme.radiusM * s
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.cardTop }
        GradientStop { position: 1.0; color: Theme.cardBot }
    }
    border.width: 1
    border.color: Theme.border

    // блик по верхней кромке — «стекло»
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1 * root.s
        anchors.left: parent.left
        anchors.leftMargin: Math.max(8, root.radius / 2)
        anchors.right: parent.right
        anchors.rightMargin: Math.max(8, root.radius / 2)
        height: 1
        color: Theme.glassSheen
    }
}
