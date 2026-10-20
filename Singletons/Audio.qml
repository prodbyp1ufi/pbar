pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Аудио через wpctl. В этой сборке quickshell (0.3.1) ноды PipeWire не
 * привязываются к реестру: чтение volume даёт 0, запись отбрасывается
 * с "Tried to change node volumes ... not bound". wpctl работает надёжно,
 * поэтому и чтение, и запись идут через него. Список устройств по-прежнему
 * берётся из Pipewire (имена читаются), выбор устройства — wpctl set-default.
 */
Singleton {
    id: root

    property real sinkVol: 0
    property bool sinkMute: false
    property real srcVol: 0
    property bool srcMute: false

    // ── защита от гонок get/set ──
    // Ответ get нельзя применять, если во время его полёта состояние могло
    // измениться: ушла команда set (кнопка/IPC) или пришло событие PipeWire
    // (хоткей, другой микшер) — иначе устаревший ответ откатывает оптимистичное
    // значение (выглядело как «mute срабатывает через раз»). getInFlight держится
    // до обработки ответа: между выходом процесса и доставкой StdioCollector
    // есть зазор, в котором Process.running уже false, а ответ ещё не пришёл.
    property bool getInFlight: false
    property real runIssuedAt: -1       // setIssuedAt на момент старта get
    property real setIssuedAt: 0        // момент последней команды set
    property bool pendingRefresh: false // просили refresh, пока get был в полёте

    function refresh() {
        if (root.getInFlight) { root.pendingRefresh = true; return; }
        if (wpProc.running) return; // после set перечитает wpProc.onExited
        root.getInFlight = true;
        root.runIssuedAt = root.setIssuedAt;
        getProc.running = true;
    }

    function setSinkVolume(v) {
        var c = Math.max(0, Math.min(1, v));
        // оптимистично: реальное значение подтвердит пулл после wpctl
        root.sinkVol = c;
        root.runWpctl(["set-volume", "@DEFAULT_AUDIO_SINK@", c.toFixed(3)]);
    }

    function setSinkMute(m) {
        root.sinkMute = m;
        // явное значение, не toggle:WirePlumber применяет toggle асинхронно,
        // и два подряд toggle могут отработать как один — расхождение UI и
        // провода затем живёт вечно («раз через раз»). Явный 0/1 идемпотентен
        root.runWpctl(["set-mute", "@DEFAULT_AUDIO_SINK@", m ? "1" : "0"]);
    }

    function toggleSinkMute() { root.setSinkMute(!root.sinkMute); }

    function setSrcVolume(v) {
        var c = Math.max(0, Math.min(1, v));
        root.srcVol = c;
        root.runWpctl(["set-volume", "@DEFAULT_AUDIO_SOURCE@", c.toFixed(3)]);
    }

    function setSrcMute(m) {
        root.srcMute = m;
        root.runWpctl(["set-mute", "@DEFAULT_AUDIO_SOURCE@", m ? "1" : "0"]);
    }

    function toggleSrcMute() { root.setSrcMute(!root.srcMute); }

    // для клавиатурных биндов: автоповтор клавиши mute шлёт toggle многократно,
    // чётное число повторов возвращает состояние назад («не нажимается»).
    // Глушим повторы: отсчёт от последней ПОПЫТКИ, не от принятой
    property real lastSinkMuteTry: 0
    property real lastSrcMuteTry: 0

    function keyToggleSinkMute() {
        var now = Date.now();
        if (now - root.lastSinkMuteTry < 400) return;
        root.lastSinkMuteTry = now;
        root.setSinkMute(!root.sinkMute);
    }

    function keyToggleSrcMute() {
        var now = Date.now();
        if (now - root.lastSrcMuteTry < 400) return;
        root.lastSrcMuteTry = now;
        root.setSrcMute(!root.srcMute);
    }

    function setDefaultSink(nodeId) {
        if (nodeId === undefined || nodeId === null) return;
        root.runWpctl(["set-default", String(nodeId)]);
    }

    function setDefaultSource(nodeId) {
        if (nodeId === undefined || nodeId === null) return;
        root.runWpctl(["set-default", String(nodeId)]);
    }

    function runWpctl(argv) {
        // процесс один: если ещё занят — запоминаем последнюю команду,
        // чтобы быстрый драг фейдера не терял финальное значение
        if (wpProc.running) { root.pendingWpctl = argv; return; }
        root.setIssuedAt = Date.now();
        wpProc.command = ["wpctl"].concat(argv);
        wpProc.running = true;
        pullTimer.restart();
    }

    property var pendingWpctl: null

    function parseVol(text) {
        // "Volume: 0.60" | "Volume: 1.00 [MUTED]" | "Volume: 0.00"
        var t = (text || "").trim();
        if (t.indexOf("Volume:") !== 0) return null;
        var num = parseFloat(t.substring(7));
        if (isNaN(num)) return null;
        return { vol: num, mute: t.indexOf("[MUTED]") >= 0 };
    }

    Component.onCompleted: refresh()

    // внешние изменения — страховочный пулл (основное — pactl subscribe ниже)
    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    // мгновенный подхват хоткеев/других микшеров: события PipeWire
    // (фейдер в хабе и OSD обновляются без задержки)
    Process {
        id: evtProc
        running: true
        command: ["sh", "-c",
            "pactl subscribe 2>/dev/null | grep --line-buffered -E \" on (sink|source|server|card) #\""]
        stdout: SplitParser {
            onRead: evtTick.restart()
        }
    }

    Timer {
        id: evtTick
        interval: 120
        onTriggered: root.refresh()
    }

    Timer {
        id: pullTimer
        interval: 180
        onTriggered: root.refresh()
    }

    // перезапрос сразу после отбраковки устаревшего ответа get
    Timer {
        id: refetch
        interval: 30
        onTriggered: root.refresh()
    }

    Process {
        id: getProc
        command: ["sh", "-c",
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; printf '@@@'; "
            + "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.getInFlight = false;
                // устарел, если во время полёта get ушла команда set
                // или пришло событие PipeWire — применить его значит
                // откатить оптимистичное значение
                if (root.setIssuedAt > root.runIssuedAt || root.pendingRefresh) {
                    root.pendingRefresh = false;
                    refetch.restart();
                    return;
                }
                var parts = this.text.split("@@@");
                var s = root.parseVol(parts[0]);
                if (s) { root.sinkVol = s.vol; root.sinkMute = s.mute; }
                var r = root.parseVol(parts[1]);
                if (r) { root.srcVol = r.vol; root.srcMute = r.mute; }
            }
        }
    }

    Process {
        id: wpProc
        onExited: {
            if (root.pendingWpctl !== null) {
                var next = root.pendingWpctl;
                root.pendingWpctl = null;
                root.runWpctl(next);
            } else {
                root.refresh();
            }
        }
    }
}
