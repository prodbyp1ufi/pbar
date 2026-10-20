pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Запуски из спотлайт-лаунчера: браузер, superfile, терминал. Process'ы
 * живут здесь, а не в карточке: закрытие спотлайта уничтожает поверхность
 * вместе с её Process'ами и убивает только что запущенный процесс.
 */
Singleton {
    id: root

    function web(query) {
        var url = "https://www.google.com/search?q=" + encodeURIComponent(query);
        exec(["sh", "-c", "setsid xdg-open '" + url + "'"]);
    }

    function term(command) {
        exec(["setsid", "kitty", "--hold", "sh", "-c", command]);
    }

    function folder(path) {
        if (dirProbe.running) return;
        dirProbe.target = expandHome(path);
        dirProbe.running = true;
    }

    function expandHome(p) {
        if (p === "~" || p.indexOf("~/") === 0)
            return Quickshell.env("HOME") + p.substring(1);
        return p;
    }

    function exec(argv) {
        if (runProc.running) runProc.running = false;
        runProc.command = argv;
        runProc.running = true;
    }

    Process { id: runProc }

    // существует ли путь из запроса: если нет — superfile откроет дом
    Process {
        id: dirProbe
        property string target: ""
        command: ["sh", "-c", "test -d \"$0\" && echo y || echo n", dirProbe.target]
        stdout: StdioCollector {
            onStreamFinished: {
                var dir = this.text.trim() === "y" ? dirProbe.target : Quickshell.env("HOME");
                root.exec(["setsid", "kitty", "--directory", dir, "spf"]);
            }
        }
    }
}
