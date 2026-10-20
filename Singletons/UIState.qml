pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Маршрутизация поверхностей: какая поверхность открыта и на каком мониторе.
 * Все клики и IPC-вызовы сходятся сюда, пилюли на каждом экране читают open.
 */
Singleton {
    id: root

    property string openMon: ""
    property string openSurface: ""

    readonly property bool anyOpen: openSurface.length > 0
    // лаунчер и буфер рисуются в overlay центрированной карточкой (спотлайт),
    // минуя морф пилюли
    readonly property bool isSpotlight: openSurface === "launcher" || openSurface === "clip"

    function toggleSurface(mon, name) {
        if (!mon || mon.length === 0)
            mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (root.openMon === mon && root.openSurface === name) {
            root.close();
            return;
        }
        root.openMon = mon;
        root.openSurface = name;
    }

    function close() {
        root.openMon = "";
        root.openSurface = "";
    }
}
