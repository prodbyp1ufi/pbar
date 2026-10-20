pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Мониторинг ресурсов. CPU — дельты /proc/stat, память — /proc/meminfo,
 * температура — hwmon (k10temp, с фолбэками на amdgpu/thermal_zone),
 * сеть — /proc/net/dev, диск — df, плюс loadavg и uptime.
 * Обновление раз в 2 секунды, история CPU для спарклайна.
 */
Singleton {
    id: root

    property real cpu: 0            // 0..1
    property var cpuHist: []        // последние ~60 сэмплов
    property real mem: 0            // 0..1
    property real memUsed: 0        // МБ
    property real memTotal: 0       // МБ
    property real temp: 0           // °C
    property real netDown: 0        // КБ/с
    property real netUp: 0          // КБ/с
    property real diskUsed: 0       // байты
    property real diskTotal: 0      // байты
    property string loadavg: ""
    property string uptime: ""

    property string _tempPath: "/sys/class/thermal/thermal_zone0/temp"
    property real _prevTotal: 0
    property real _prevIdle: 0
    property real _prevRx: 0
    property real _prevTx: 0

    Component.onCompleted: {
        tempProbe.running = true;
        root.tick();
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.tick()
    }

    function tick() {
        statView.reload();
        memView.reload();
        netView.reload();
        loadView.reload();
        upView.reload();
        if (root._tempPath.length) {
            tempView.path = root._tempPath;
            tempView.reload();
        }
        diskProc.running = true;
    }

    function parseStat(text) {
        var f = text.split("\n")[0].split(/\s+/);
        if (f.length < 5) return;
        var total = 0;
        for (var i = 1; i < f.length; i++) total += (+f[i] || 0);
        var idle = (+f[4] || 0) + (+f[5] || 0);
        var dT = total - root._prevTotal;
        var dI = idle - root._prevIdle;
        if (root._prevTotal > 0 && dT > 0) {
            var v = Math.max(0, Math.min(1, 1 - dI / dT));
            root.cpu = v;
            var h = root.cpuHist.slice();
            h.push(v);
            if (h.length > 60) h.shift();
            root.cpuHist = h;
        }
        root._prevTotal = total;
        root._prevIdle = idle;
    }

    function parseMem(text) {
        var t = text.match(/MemTotal:\s+(\d+)/);
        var a = text.match(/MemAvailable:\s+(\d+)/);
        if (!t || !a) return;
        var total = +t[1], avail = +a[1];
        root.memTotal = total / 1024;
        root.memUsed = (total - avail) / 1024;
        root.mem = total > 0 ? (total - avail) / total : 0;
    }

    function parseNet(text) {
        var lines = text.split("\n");
        var rx = 0, tx = 0;
        for (var i = 2; i < lines.length; i++) {
            var ci = lines[i].indexOf(":");
            if (ci < 0) continue;
            var iface = lines[i].substring(0, ci).trim();
            if (iface === "lo") continue;
            var f = lines[i].substring(ci + 1).trim().split(/\s+/);
            if (f.length < 9) continue;
            rx += +f[0] || 0;
            tx += +f[8] || 0;
        }
        if (root._prevRx > 0) {
            root.netDown = Math.max(0, (rx - root._prevRx) / 2 / 1024);
            root.netUp = Math.max(0, (tx - root._prevTx) / 2 / 1024);
        }
        root._prevRx = rx;
        root._prevTx = tx;
    }

    FileView {
        id: statView
        path: "/proc/stat"
        onTextChanged: root.parseStat(text())
    }

    FileView {
        id: memView
        path: "/proc/meminfo"
        onTextChanged: root.parseMem(text())
    }

    FileView {
        id: netView
        path: "/proc/net/dev"
        onTextChanged: root.parseNet(text())
    }

    FileView {
        id: loadView
        path: "/proc/loadavg"
        onTextChanged: {
            var f = text().trim().split(" ");
            if (f.length >= 3) root.loadavg = f[0] + "  " + f[1] + "  " + f[2];
        }
    }

    FileView {
        id: upView
        path: "/proc/uptime"
        onTextChanged: {
            var sec = parseFloat(text());
            if (isNaN(sec)) return;
            var h = Math.floor(sec / 3600);
            var m = Math.floor((sec % 3600) / 60);
            root.uptime = h > 0 ? (h + " ч " + m + " м") : (m + " м");
        }
    }

    FileView {
        id: tempView
        onTextChanged: {
            var v = parseFloat(text());
            if (!isNaN(v)) root.temp = v / 1000;
        }
    }

    // ищем k10temp (CPU), иначе amdgpu, иначе thermal_zone0
    Process {
        id: tempProbe
        command: ["sh", "-c", "grep -H . /sys/class/hwmon/hwmon*/name 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                var pick = "";
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i];
                    if (l.indexOf("k10temp") >= 0) { pick = l; break; }
                    if (pick.length === 0 && l.indexOf("amdgpu") >= 0) pick = l;
                }
                if (pick.length) {
                    // ".../hwmon5/name:k10temp" → отрезаем суффикс "/name"
                    var file = pick.substring(0, pick.indexOf(":"));
                    root._tempPath = file.substring(0, file.lastIndexOf("/")) + "/temp1_input";
                }
            }
        }
    }

    Process {
        id: diskProc
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                if (lines.length < 2) return;
                var f = lines[1].trim().split(/\s+/);
                if (f.length < 2) return;
                root.diskUsed = +f[0] || 0;
                root.diskTotal = +f[1] || 0;
            }
        }
    }
}
