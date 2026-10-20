pragma Singleton
import QtQuick
import Quickshell

/**
 * OSD в пилюле: индикатор громкости/микрофона/яркости/зарядки.
 * Показывается на фокусированном мониторе поверх пилюли, прячется сам
 * через 1.6 с после последнего изменения. Данные подключаются в Pill.qml
 * (Connections), чтобы синглтоны не были живыми без бара.
 */
Singleton {
    id: root

    property string kind: "vol"   // "vol" | "mic" | "bright" | "charge"
    property real value: 0        // 0..1
    property bool off: false      // mute / выключено
    property string note: ""      // доп. текст (время до полной зарядки)
    property bool active: false

    function show(k, v, off_, note_) {
        root.kind = k;
        if (v !== undefined && v !== null && !isNaN(v)) root.value = v;
        root.off = off_ === true;
        root.note = note_ === undefined ? "" : note_;
        root.active = true;
        holdTimer.restart();
    }

    Timer {
        id: holdTimer
        interval: 1600
        onTriggered: root.active = false
    }
}