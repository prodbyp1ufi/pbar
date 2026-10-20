pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * История буфера обмена (cliphist): список (текст и картинки), возврат в
 * буфер, удаление, полная очистка. Превью картинок декодируются ленивой
 * очередью в XDG_RUNTIME_DIR/qsbar-clip/<id>.img.
 *
 * В автостарте Hyprland у пользователя строка вотчера картинок содержит
 * опечатку (--watcg), поэтому картинки в cliphist не пишутся: если вотчера
 * нет при старте бара — запускаем свой (wl-paste --type image --watch).
 */
Singleton {
    id: root

    readonly property string cacheDir: Quickshell.env("XDG_RUNTIME_DIR") + "/qsbar-clip"

    /** [{id, type, preview, image}] — свежие сверху */
    property var entries: []
    /** id → "file://..." путь к декодированному превью */
    property var previews: ({})

    Component.onCompleted: {
        mkCache.running = true;
        watchCheck.running = true;
    }

    Process {
        id: mkCache
        command: ["mkdir", "-p", root.cacheDir]
    }

    function refresh() {
        if (!listProc.running) listProc.running = true;
    }

    // точный паттерн с [ ]-трюком, чтобы не совпасть ни с самим sh -c,
    // ни с ручными тестами вида "wl-paste --type image -"
    Process {
        id: watchCheck
        command: ["sh", "-c", "pgrep -f 'wl-paste --type image --watc[h] cliphist' >/dev/null 2>&1 && echo run || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "no" && !watchProc.running)
                    watchProc.running = true;
            }
        }
    }

    Process {
        id: watchProc
        command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
    }

    // само-заживление: если вотчер пропал (например, бар перезапускался),
    // периодически перепроверяем
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: watchCheck.running = true
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // формат cliphist: "<id>\t<preview>"; у картинок превью —
                // "[[ binary data 178 KiB png 824x594 ]]", у текста — сам текст
                var arr = [];
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i];
                    if (!l.length) continue;
                    var t1 = l.indexOf("\t");
                    if (t1 < 0) continue;
                    var idn = parseInt(l.substring(0, t1));
                    if (isNaN(idn)) continue;
                    var preview = l.substring(t1 + 1);
                    var isImg = preview.indexOf("[[ binary data") === 0;
                    var type = "text/plain";
                    if (isImg) {
                        var mm = preview.match(/\b(png|jpe?g|gif|bmp|webp)\b/);
                        type = "image/" + (mm ? (mm[1] === "jpg" ? "jpeg" : mm[1]) : "png");
                    }
                    arr.push({ id: idn, type: type, preview: preview, image: isImg });
                }
                arr.sort(function (a, b) { return b.id - a.id; });
                root.entries = arr;
                root.decodePreviews();
            }
        }
    }

    property var _queue: []

    function decodePreviews() {
        var q = [];
        var n = 0;
        for (var i = 0; i < root.entries.length && n < 12; i++) {
            var e = root.entries[i];
            if (!e.image) continue;
            n++;
            if (root.previews[e.id] !== undefined) continue;
            q.push(e.id);
        }
        root._queue = q;
        root.pump();
    }

    function pump() {
        if (decProc.running || root._queue.length === 0) return;
        var id = root._queue.shift();
        decProc._curId = id;
        decProc.command = ["sh", "-c",
            "cliphist decode " + id + " > '" + root.cacheDir + "/" + id + ".img'"];
        decProc.running = true;
    }

    Process {
        id: decProc
        property int _curId: -1
        onExited: {
            if (_curId >= 0) {
                var patch = {};
                patch[_curId] = "file://" + root.cacheDir + "/" + _curId + ".img";
                root.previews = Object.assign({}, root.previews, patch);
                _curId = -1;
            }
            root.pump();
        }
    }

    function copyBack(entry) {
        // setsid: wl-copy должен переживать перезапуск бара
        var pipe = "cliphist decode " + entry.id + " | setsid wl-copy";
        if (entry.image) pipe += " --type " + entry.type;
        copyProc.command = ["sh", "-c", pipe];
        copyProc.running = true;
    }

    function remove(id) {
        // cliphist delete читает строку формата "id\t..." только со stdin;
        // форма "cliphist delete <id>" аргументом молча не срабатывает.
        // Превью после таба игнорируется — достаточно id.
        delProc.command = ["sh", "-c",
            "printf '" + id + "\\t\\n' | cliphist delete"];
        delProc.running = true;
    }

    function wipe() {
        delProc.command = ["cliphist", "wipe"];
        delProc.running = true;
    }

    Process { id: copyProc }

    Process {
        id: delProc
        onExited: refTimer.restart()
    }

    Timer {
        id: refTimer
        interval: 250
        onTriggered: root.refresh()
    }
}
