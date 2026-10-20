import QtQuick
import QtQuick.Effects
import "../Singletons"

/**
 * Стеклянная карточка спотлайта — фон центрированных поверхностей
 * (лаунчер, буфер). В отличие от пилюли живёт прямо в overlay-окне,
 * поэтому рисует собственное стекло и тень.
 */
Rectangle {
    id: card

    property real s: 1

    radius: Theme.radiusL * card.s
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.glassTop }
        GradientStop { position: 1.0; color: Theme.glassBot }
    }
    border.width: 1
    border.color: Theme.glassBorder

    // блик по верхнему краю
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1 * card.s
        anchors.left: parent.left
        anchors.leftMargin: 20 * card.s
        anchors.right: parent.right
        anchors.rightMargin: 20 * card.s
        height: 1
        color: Theme.glassSheen
    }

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 1.0
        shadowVerticalOffset: 5 * card.s
    }
}
