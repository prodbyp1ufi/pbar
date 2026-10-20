pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Скриншоты (grim + slurp) и запись экрана (gpu-screen-recorder).
 * Снимки: область / весь экран / окно по клику — сохраняются в
 * ~/Pictures/Screenshots и копируются в буфер (wl-copy через setsid,
 * чтобы владелец буфера пережил перезапуск бара).
 * Запись: монитор, окно по клику или выделенная область, системный
 * звук и/или микрофон, файл в ~/Videos/Recordings. Остановка — SIGINT.
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string shotDir: home + "/Pictures/Screenshots"
    readonly property string recDir: home + "/Videos/Recordings"

    property bool busy: false        // идёт выбор области или съёмка кадра
    property bool recording: false
    property real recStart: 0
    property string lastShot: ""
    property string lastRec: ""
    property string lastError: ""

    // настройки записи — сохраняются между открытиями поверхности
    property bool recSysAudio: true
    property bool recMic: false
    property string recScope: "mon"  // "mon" | "win" | "region"

    Component.onCompleted: mkDirs.running = true

    Process {
        id: mkDirs
        command: ["mkdir", "-p", root.shotDir, root.recDir]
    }

    // ── снимки ──

    function shotScreen() {
        if (root.busy || root.recording) return;
        root.doShot("");
    }

    function shotRegion() {
        if (root.busy || root.recording) return;
        root.busy = true;
        root._slurpMode = "shot";
        UIState.close(); // спрятать бар на время выбора
        slurpDelay.restart();
    }

    // slurp перед стартом читает stdin до EOF. Quickshell Process держит
    // stdin-пайп ребёнка открытым — EOF не приходит, slurp вечно висит в
    // read() так и не подключившись к композитору (слой selection не
    // мапится). Перенаправляем stdin из /dev/null, exec подменяет sh собой,
    // поэтому StdioCollector на stdout продолжает работать как раньше.
    Timer {
        id: slurpDelay
        interval: 100
        onTriggered: {
            slurpProc.command = ["sh", "-c", "exec slurp < /dev/null"];
            slurpProc.running = true;
            slurpWatchdog.restart();
        }
    }

    // страховка: если slurp всё же завис — прервать и вернуть busy
    Timer {
        id: slurpWatchdog
        interval: 120000
        onTriggered: {
            if (slurpProc.running) {
                slurpProc.running = false;
                root.lastError = "Выбор области не удался — попробуй ещё раз";
            }
        }
    }

    // ── выбор окна: прямоугольники окон кормятся slurp с флагом -r
    // («restrict selection to predefined boxes»): рамки выбираемых окон
    // подсвечиваются на экране, клик выбирает окно целиком, свободную
    // область нарисовать нельзя — рисование это отдельное действие
    // «Область». Координаты отдаёт сам slurp (проверенный ukishima-путь),
    // поэтому геометрия всегда совпадает с тем, что ждут grim и gsr.

    property bool picking: false       // идёт выбор окна/области через slurp
    property bool pickForRec: false    // выбор открыт для записи, а не снимка

    function shotWindow() {
        pickWindow(false);
    }

    function pickWindow(rec) {
        if (root.busy || root.recording) return;
        root.busy = true;
        root.pickForRec = rec;
        root.picking = true;
        UIState.close();
        winPickProc.running = true;
    }

    function winPicked(geo) {
        console.log("[shot] window picked, rec:", root.pickForRec, "geo:", geo);
        if (root.pickForRec) root.startRec(geo);
        else root.doShot(geo);
    }

    function cancelPick() {
        if (!root.picking) return;
        root.picking = false;
        root.busy = false;
    }

    // страховка: пикер забыли закрыть — снимаем сами и убираем
    // осиротевший slurp (Quickshell SIGKILLит sh, внуки выживают)
    Timer {
        id: pickWatchdog
        interval: 300000
        running: root.picking
        onTriggered: {
            winPickProc.running = false;
            slurpKillProc.command = ["pkill", "-f", "slurp -r -f"];
            slurpKillProc.running = true;
            root.cancelPick();
        }
    }

    // пикируемый slurp — внук: SIGKILL от Quickshell убивает только sh,
    // осиротевший slurp остался бы держать выделение — добиваем по cmdline
    Process { id: slurpKillProc }

    // В фильтре jq остаются только окна активных (или специальных)
    // ворспейсов — иначе рисуются фантомные рамки окон «с других столов»
    // (жалоба «две области, хотя открыто одно окно»). Если фильтр вдруг
    // дал пусто — кормим все окна, чтобы пикер не оказался мёртвым.
    // Результат проверяется grep'ом по предложенным прямоугольникам:
    // даже если slurp проигнорировал -r, свободная область не пройдёт.
    // Пока пикер открыт, getrects() опрашивается каждые 0.3 с: сменился
    // набор окон (переключение стола, открытие/закрытие, перемещение) —
    // slurp перезапускается с новыми рамками, клики по старым не проходят.
    Process {
        id: winPickProc
        property bool _handled: false
        command: ["sh", "-c",
            "getrects() { hyprctl -j monitors 2>/dev/null | jq -c . > /tmp/qs-bar-mons.json; "
            + "ids=$(jq -c \"[.[] | .activeWorkspace.id] + [.[] | .specialWorkspace.id | select(. and . != 0)] | unique\" /tmp/qs-bar-mons.json 2>/dev/null); "
            + "r=$(hyprctl -j clients 2>/dev/null | jq -r --argjson ids \"$ids\" '"
            + ".[] | select(.workspace.id as $wid | $ids | index($wid)) | "
            + "\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"' 2>/dev/null | LC_ALL=C sort); "
            + "[ -z \"$r\" ] && r=$(hyprctl -j clients 2>/dev/null | jq -r '"
            + ".[] | \"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"' 2>/dev/null | LC_ALL=C sort); "
            + "printf '%s' \"$r\"; }; "
            + "while true; do rects=$(getrects); : > /tmp/qs-bar-geo.txt; "
            + "printf '%s\\n' \"$rects\" | slurp -r -f \"%x,%y %wx%h\" > /tmp/qs-bar-geo.txt & spid=$!; "
            + "changed=0; while kill -0 \"$spid\" 2>/dev/null; do sleep 0.3; "
            + "if [ \"$(getrects)\" != \"$rects\" ]; then changed=1; kill \"$spid\" 2>/dev/null; break; fi; done; "
            + "wait \"$spid\" 2>/dev/null; geo=$(cat /tmp/qs-bar-geo.txt); "
            + "if [ -z \"$geo\" ]; then [ \"$changed\" = 0 ] && exit 1; continue; fi; "
            + "printf '%s\\n' \"$rects\" | grep -qxF \"$geo\" && { echo \"$geo\"; exit 0; }; "
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                winPickProc._handled = true;
                root.picking = false;
                var geo = this.text.trim();
                if (geo.length > 0) root.winPicked(geo);
                else root.busy = false;
            }
        }
        onExited: function (code) {
            if (!winPickProc._handled) {
                root.picking = false;
                root.busy = false; // Esc или ошибка slurp — тихо отмена
            }
        }
    }

    function doShot(geo) {
        var path = root.shotDir + "/shot-"
            + Qt.formatDateTime(new Date(), "yyyy-MM-dd-HH-mm-ss") + ".png";
        var argv = ["grim", "-t", "png"];
        if (geo.length) argv.push("-g", geo);
        argv.push(path);
        console.log("[shot] grim argv:", argv.join(" "));
        shotProc._outPath = path;
        shotProc.command = argv;
        shotProc.running = true;
    }

    property string _slurpMode: ""

    Process {
        id: slurpProc
        stdout: StdioCollector {
            onStreamFinished: {
                slurpWatchdog.stop();
                var geo = this.text.trim();
                var mode = root._slurpMode;
                root._slurpMode = "";
                console.log("[shot] slurp done, mode:", mode, "geo:", geo);
                if (mode === "shot") {
                    if (geo.length) root.doShot(geo);
                    else root.busy = false;
                } else if (mode === "rec") {
                    if (geo.length) root.startRec(geo);
                    else root.busy = false;
                }
            }
        }
    }

    Process {
        id: shotProc
        property string _outPath: ""
        onExited: function (code) {
            root.busy = false;
            if (code === 0) {
                root.lastShot = _outPath;
                root.lastError = "";
                copyProc.command = ["sh", "-c",
                    "setsid wl-copy --type image/png < '" + _outPath + "'"];
                copyProc.running = true;
            } else {
                root.lastError = "Снимок не удался";
            }
        }
    }

    Process { id: copyProc }

    function openFolder(dir) {
        // kitty 0.42+ убрал -e; --directory задаёт cwd, в котором откроется superfile
        folderProc.command = ["setsid", "kitty", "--directory", dir, "spf"];
        folderProc.running = true;
    }

    Process { id: folderProc }

    // ── запись ──

    function startRecRegion() {
        if (root.busy || root.recording) return;
        root.busy = true;
        root._slurpMode = "rec";
        UIState.close();
        slurpDelay.restart();
    }

    function startRecWindow() {
        pickWindow(true);
    }

    // выбранный источник и собранная команда — заполняются асинхронно,
    // пока резолвится микрофон (pactl может ответить не мгновенно)
    property string _recOut: ""
    property var _recArgv: []

    function startRec(geo) {
        if (root.recording) return;
        root._recOut = root.recDir + "/rec-"
            + Qt.formatDateTime(new Date(), "yyyy-MM-dd-HH-mm-ss") + ".mp4";
        var mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        // slurp/gsr: "X,Y WxH" → gsr ждёт "WxH+X+Y"; X,Y могут быть
        // отрицательными (монитор слева/сверху от основного)
        var target = "";
        if (geo && geo.length) {
            var m = geo.match(/^(-?\d+),(-?\d+) (\d+)x(\d+)$/);
            target = m ? (m[3] + "x" + m[4] + "+" + m[1] + "+" + m[2]) : "";
        }
        var argv = ["gpu-screen-recorder", "-f", "60", "-q", "high", "-o", root._recOut];
        // gsr 6.x: область = -w region -region WxH+X+Y; иначе монитор или весь экран
        if (target.length) argv.push("-w", "region", "-region", target);
        else argv.push("-w", mon.length ? mon : "screen");
        // аудио как в ukishima: один -a, источники через "|".
        // Монитор выхода в PipeWire снимает сигнал ДО mute — при выключенном
        // звуке системный звук не берём вовсе.
        var sources = [];
        if (root.recSysAudio && !Audio.sinkMute) sources.push("default_output");
        if (root.recMic) sources.push("default_input");
        if (sources.length > 0) argv.push("-a", sources.join("|"));
        root._recArgv = argv;
        launchRec();
    }

    function launchRec() {
        recProc._outPath = root._recOut;
        recProc.command = root._recArgv;
        recProc.running = true;
        root.busy = false;      // дальше состояние держит recording
        root.recording = true;
        root.recStart = Date.now();
        root.lastError = "";
        root.lastRec = root._recOut;
    }

    function stopRec() {
        if (!root.recording) return;
        killProc.running = true;
    }

    // имя длиннее 15 символов, comm обрезан — матчим по cmdline
    Process {
        id: killProc
        command: ["pkill", "-INT", "-f", "gpu-screen-recorder"]
    }

    Process {
        id: recProc
        property string _outPath: ""
        onExited: function (code) {
            root.recording = false;
            root.busy = false; // критично: иначе все будущие снимки блокируются
            if (code !== 0 && root.lastError.length === 0)
                root.lastError = "Запись прервана";
        }
    }
}
