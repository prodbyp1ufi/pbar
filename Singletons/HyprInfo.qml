pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Состояние Hyprland: воркспейсы по мониторам, активное окно, раскладка.
 * Данные читаются напрямую из hyprctl -j (модели Quickshell пусты на старте),
 * обновление — по событиям + короткий boot-поллинг. Раскладка парсится из
 * socket2 (activelayout>>), как в старом Main.qml.
 */
Singleton {
    id: root

    /** [{name, activeWs, hasFullscreen}] */
    property var monitors: []
    /** {monitorName: [id, ...]} */
    property var wsByMonitor: ({})
    property string activeTitle: ""
    property string activeClass: ""
    property string kbLayout: "EN"
    property bool ready: false

    function refresh() { proc.running = true; }

    function monitor(name) {
        var m = root.monitors;
        for (var i = 0; i < m.length; i++)
            if (m[i].name === name) return m[i];
        return null;
    }

    function fullscreenOn(name) {
        var m = monitor(name);
        return m ? !!m.hasFullscreen : false;
    }

    function activeWsOf(name) {
        var m = monitor(name);
        return m ? m.activeWs : "";
    }

    function wsList(name) {
        return root.wsByMonitor[name] || [];
    }

    function switchWs(id) {
        Hyprland.dispatch("workspace " + id);
    }

    function shortLayout(name) {
        if (name.startsWith("English"))   return "EN";
        if (name.startsWith("Russian"))   return "RU";
        if (name.startsWith("Ukrainian")) return "UA";
        if (name.startsWith("German"))    return "DE";
        return name.substring(0, 2).toUpperCase();
    }

    function parse(text) {
        try {
            var parts = text.split("@@@");
            var mons = JSON.parse(parts[0] || "[]");
            var wss = JSON.parse(parts[1] || "[]");
            var winRaw = (parts[2] || "").trim();
            var win = null;
            if (winRaw.length > 0 && winRaw.charAt(0) === "{")
                win = JSON.parse(winRaw);

            var m = [];
            var byMon = {};
            for (var i = 0; i < mons.length; i++) {
                var mo = mons[i];
                m.push({
                    name: mo.name,
                    activeWs: mo.activeWorkspace ? String(mo.activeWorkspace.name) : "",
                    hasFullscreen: !!mo.hasfullscreen
                });
                byMon[mo.name] = [];
            }
            for (var j = 0; j < wss.length; j++) {
                var w = wss[j];
                if (w.monitor && byMon[w.monitor])
                    byMon[w.monitor].push(w.id);
            }
            for (var k in byMon)
                byMon[k].sort(function (a, b) { return a - b; });

            root.monitors = m;
            root.wsByMonitor = byMon;
            root.activeTitle = (win && win.title) ? win.title : "";
            root.activeClass = (win && win.class) ? win.class : "";
            root.ready = true;
        } catch (e) { }
    }

    // Только события, реально влияющие на отрисовку бара.
    readonly property var eventSet: ({
        workspace: 1, workspacev2: 1,
        createworkspace: 1, createworkspacev2: 1,
        destroyworkspace: 1, destroyworkspacev2: 1,
        moveworkspace: 1, moveworkspacev2: 1,
        renameworkspace: 1, focusedmon: 1, focusedmonv2: 1,
        openwindow: 1, closewindow: 1,
        fullscreen: 1, fullscreenstate: 1,
        monitoradded: 1, monitoraddedv2: 1, monitorremoved: 1,
        activewindow: 1, activewindowv2: 1,
        configreloaded: 1
    })

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.eventSet[event.name])
                root.refresh();
        }
    }

    Process {
        id: proc
        command: ["sh", "-c",
            "hyprctl -j monitors; printf '@@@'; hyprctl -j workspaces; printf '@@@'; hyprctl -j activewindow"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    // На старте hyprctl может ответить раньше, чем поднимется сокет —
    // короткий поллинг до первого успешного снимка.
    Timer {
        id: bootPoll
        interval: 400
        repeat: true
        running: true
        property int tries: 0
        onTriggered: {
            root.refresh();
            tries++;
            if (root.ready || tries >= 10)
                running = false;
        }
    }

    // Раскладка клавиатуры из socket2 — проверенный вариант из Main.qml.
    Socket {
        id: hyprSocket

        path: Quickshell.env("XDG_RUNTIME_DIR")
              + "/hypr/"
              + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
              + "/.socket2.sock"
        connected: true

        parser: SplitParser {
            onRead: line => {
                if (line.startsWith("activelayout>>")) {
                    const parts = line.slice("activelayout>>".length).split(",")
                    root.kbLayout = root.shortLayout(parts[parts.length - 1])
                }
            }
        }
    }
}
