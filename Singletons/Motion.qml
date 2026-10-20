pragma Singleton
import QtQuick
import Quickshell

/**
 * Длительности и кривые анимаций. morphCurve — «жидкий» морфинг
 * cubic-bezier(0.16, 1, 0.3, 1) вместе с Easing.BezierSpline.
 */
Singleton {
    readonly property int fast:     140
    readonly property int standard: 240
    readonly property int morph:    420
    readonly property int glide:    260

    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeMorph:    Easing.BezierSpline
    readonly property var morphCurve:   [0.16, 1, 0.3, 1, 1, 1]
}
