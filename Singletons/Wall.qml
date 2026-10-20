pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Обои через awww (форк swww, демон уже запускается в автостарте Hyprland).
 * Список картинок — ls по ~/Pictures/Wallpapers, текущее изображение —
 * из awww query, применение — awww img (на все выходы).
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string wallDir: home + "/Pictures/Wallpapers"

    /** полные пути к картинкам */
    property var files: []
    property string currentPath: ""

    Component.onCompleted: refresh()

    function refresh() {
        if (!listProc.running) listProc.running = true;
        if (!queryProc.running) queryProc.running = true;
    }

    function apply(path) {
        if (!path.length || applyProc.running) return;
        applyProc.command = ["awww", "img", path];
        applyProc.running = true;
    }

    function openFolder() {
        // superfile в kitty (kitty 0.42+ убрал -e), как в Shot.openFolder
        folderProc.command = ["setsid", "kitty", "--directory", root.wallDir, "spf"];
        folderProc.running = true;
    }

    Process {
        id: listProc
        command: ["ls", "-1", root.wallDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var arr = [];
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var n = lines[i].trim();
                    if (!n.length) continue;
                    if (/\.(jpg|jpeg|png|webp|gif|bmp)$/i.test(n))
                        arr.push(root.wallDir + "/" + n);
                }
                root.files = arr;
            }
        }
    }

    Process {
        id: queryProc
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = this.text.match(/currently displaying: image: (.+)/);
                root.currentPath = m ? m[1].trim() : "";
            }
        }
    }

    Process {
        id: applyProc
        onExited: refTimer.restart()
    }

    Timer {
        id: refTimer
        interval: 700
        onTriggered: queryProc.running = true
    }

    Process { id: folderProc }
}
