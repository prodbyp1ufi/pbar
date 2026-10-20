import QtQuick

/**
 * База морф-поверхности пилюли. Хост задаёт open и s; поверхность объявляет
 * базовые размеры w/h (в единицах дизайна), surfW/surfH отдаются уже
 * умноженными на масштаб — пилюля морфится под них.
 */
Item {
    id: surface

    property real s: 1
    property bool open: false

    property int w: 400
    property int h: 300
    // поверхность сама решает, когда перехватить клавиатуру (поле пароля и т.п.)
    property bool wantsKeys: false
    readonly property int surfW: Math.round(w * s)
    readonly property int surfH: Math.round(h * s)

    signal requestClose()

    opacity: open ? 1 : 0
    visible: opacity > 0.01
    enabled: open

    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
}
