pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Singletons"
import "components"
import "surfaces"

/**
 * Точка входа бара. На каждом мониторе три layer-shell окна:
 *
 *  - `reserve` — пустая полоса сверху, которая только резервирует
 *    эксклюзивную зону высотой бара, чтобы тайлованные окна не залезали
 *    под пилюлю. В фулскрине зона освобождается.
 *  - `overlay` — полноэкранное прозрачное окно слоя Overlay с пилюлей
 *    по центру верха. Ввод маршрутизируется маской: свернутая пилюля —
 *    маска по пилюле (остальное кликается насквозь), открытая
 *    поверхность — вся площадь (клик мимо пилюли закрывает её),
 *    фулскрин — маска пустая. Esc и ввод текста работают через
 *    WlrKeyboardFocus. OSD и тосты уведомлений рисуются в самой пилюле
 *    (морф размера), отдельного окна уведомлений нет.
 */
ShellRoot {
    id: root

    readonly property string focusedMon: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    // прогрев синглтонов до первого открытия хаба: Loader создаёт поверхности
    // лениво, и без этого плитки Wi-Fi/BT при открытии панели мигают
    // состоянием «выключено», пока не придёт первый ответ nmcli/bluetoothctl
    Component.onCompleted: {
        Net.refreshMeta();
        BT.refresh();
        Battery.refreshProfile();
    }

    IpcHandler {
        target: "bar"

        function launcher(mon: string): void { UIState.toggleSurface(mon, "launcher"); }
        function hub(mon: string): void { UIState.toggleSurface(mon, "hub"); }
        function calendar(mon: string): void { UIState.toggleSurface(mon, "calendar"); }
        function mixer(mon: string): void { UIState.toggleSurface(mon, "mixer"); }
        function wifi(mon: string): void { UIState.toggleSurface(mon, "wifi"); }
        function bt(mon: string): void { UIState.toggleSurface(mon, "bt"); }
        function connections(mon: string): void { UIState.toggleSurface(mon, "connections"); }
        function shot(mon: string): void { UIState.toggleSurface(mon, "shot"); }
        function shotregion(mon: string): void { Shot.shotRegion(); }
        function shotwin(mon: string): void { Shot.shotWindow(); }
        function clip(mon: string): void { UIState.toggleSurface(mon, "clip"); }
        function wall(mon: string): void { UIState.toggleSurface(mon, "wall"); }
        function res(mon: string): void { UIState.toggleSurface(mon, "res"); }
        function media(mon: string): void { UIState.toggleSurface(mon, "media"); }
        function battery(mon: string): void { UIState.toggleSurface(mon, "battery"); }
        function power(mon: string): void { UIState.toggleSurface(mon, "power"); }
        function notifs(mon: string): void { UIState.toggleSurface(mon, "notifs"); }
        function sinkmute(): void { Audio.keyToggleSinkMute(); }
        function micmute(): void { Audio.keyToggleSrcMute(); }
        function close(): void { UIState.close(); }
    }

    // ── резерв полосы сверху ──
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserve
            required property var modelData
            readonly property real s: modelData ? modelData.height / 1080 : 1
            readonly property bool monFullscreen: HyprInfo.fullscreenOn(modelData.name)
            readonly property int bandH: monFullscreen ? 0 : Math.round(56 * s)

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: bandH
            aboveWindows: true
            anchors { top: true; left: true; right: true }
            implicitHeight: bandH

            // пустая маска — окно ничего не ловит, только резервирует место
            mask: emptyReserve
            Region { id: emptyReserve }
        }
    }

    // ── основное окно с пилюлей ──
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            readonly property real s: modelData ? modelData.height / 1080 : 1
            readonly property string mon: modelData.name
            readonly property bool surfaceHere: UIState.openSurface.length > 0 && UIState.openMon === mon
            readonly property bool monFullscreen: HyprInfo.fullscreenOn(mon)
            // хаб открыт по ховеру — клавиатуру не перехватывать, пока
            // поверхность сама не попросит (поле пароля/поиска); Esc и ввод
            // в остальных поверхностях работают через Exclusive
            readonly property bool wantKeys: surfaceHere && (UIState.isSpotlight
                || UIState.openSurface !== "hub" || pillHolder.wantsKeys)

            onMonFullscreenChanged: if (monFullscreen && surfaceHere) UIState.close();

            screen: modelData
            visible: !monFullscreen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-bar"
            WlrLayershell.keyboardFocus: wantKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors { top: true; left: true; right: true; bottom: true }

            mask: monFullscreen ? hiddenRegion
                : (surfaceHere ? fullRegion : pillRegion)
            Region { id: hiddenRegion }
            Region { id: pillRegion; item: pillHolder }
            Region { id: fullRegion; width: overlay.width; height: overlay.height }

            // клик мимо пилюли/карточки спотлайта при открытой поверхности
            // закрывает её; сама пилюля объявлена ниже и перехватывает свои
            // клики первой
            MouseArea {
                anchors.fill: parent
                enabled: overlay.surfaceHere
                onPressed: (mouse) => {
                    var target = spotlight.active && spotlight.item ? spotlight.item : pillHolder;
                    var p = mapToItem(target, mouse.x, mouse.y);
                    if (p.x < 0 || p.y < 0 || p.x > target.width || p.y > target.height)
                        UIState.close();
                }
            }

            FocusScope {
                anchors.fill: parent
                focus: overlay.surfaceHere
                Keys.onEscapePressed: UIState.close()

                Pill {
                    id: pillHolder
                    s: overlay.s
                    screenName: overlay.mon
                    barWindow: overlay
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8 * overlay.s
                }

                // ── спотлайт: центрированная карточка лаунчера/буфера ──
                // чуть выше середины, fade + scale как в macOS Spotlight
                Loader {
                    id: spotlight

                    readonly property bool shown: UIState.isSpotlight && UIState.openMon === overlay.mon
                    property bool closing: false
                    property Component curComp: null

                    active: spotlight.shown || spotlight.closing
                    sourceComponent: spotlight.shown
                        ? (UIState.openSurface === "launcher" ? spotLauncher : spotClip)
                        : spotlight.curComp
                    onShownChanged: {
                        if (shown)
                            spotlight.curComp = UIState.openSurface === "launcher" ? spotLauncher : spotClip;
                        else {
                            spotlight.closing = true;
                            spotCloseTimer.restart();
                        }
                    }

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -Math.round(parent.height * 0.08)
                    width: spotlight.item ? spotlight.item.surfW : 0
                    height: spotlight.item ? spotlight.item.surfH : 0

                    Component {
                        id: spotLauncher
                        Launcher {
                            s: overlay.s
                            open: spotlight.shown
                        }
                    }
                    Component {
                        id: spotClip
                        Clipboard {
                            s: overlay.s
                            open: spotlight.shown
                        }
                    }
                }

                Timer {
                    id: spotCloseTimer
                    interval: 220
                    onTriggered: spotlight.closing = false
                }
            }
        }
    }

    // выбор окна для скрина/записи делает slurp (см. Shot.qml) —
    // отдельный пикер не нужен
}
