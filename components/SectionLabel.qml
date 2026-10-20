import QtQuick
import "../Singletons"

/**
 * Микро-заголовок секции в стиле iOS: капс с разрядкой.
 * Текст пишется уже в верхнем регистре.
 */
Text {
    property real s: 1

    color: Theme.faint
    font.family: Theme.font
    font.pixelSize: 10 * s
    font.weight: Font.DemiBold
    font.letterSpacing: 1.4
}
