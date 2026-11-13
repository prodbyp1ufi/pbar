pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Яркость экрана через brightnessctl. Если утилиты нет или чтение не
 * удалось — ok=false, слайдер в хабе просто скрывается. Формат -m:
 * device,device-name,class,current,maximum,percent
 */
Singleton {
    id: root

    property bool ok: false
    property int cur: 0
    property int max: 1

    readonly property real frac: max > 0 ? Math.max(0, Math.min(1, cur / max)) : 0

    // false, пока не пришло первое успешное чтение: заполнение cur/max из
    // дефолта (frac 0 → реальное) на старте не должно показывать OSD яркости
    property bool synced: false

    Component.onCompleted: probe.running = true

    function refresh() { getProc.running = true }

    function setFrac(f) {
        if (!root.ok) return;
        var v = Math.round(Math.max(0.01, Math.min(1, f)) * 100);
        // оптимистично двигаем значение сразу: реальное подтвердит пулл,
        // иначе слайдер отскакивает к старому значению на ~200 мс
        root.cur = Math.round(Math.max(0.01, Math.min(1, f)) * root.max);
        setProc.command = ["brightnessctl", "-q", "set", v + "%"];
        setProc.running = true;
        pullTimer.restart();
    }

    function parse(text) {
        var line = text.trim().split("\n").pop().trim();
        if (!line.length) { root.ok = false; return; }
        // формат меняется между версиями (с class или без): берём числовые
        // поля по порядку — первое current, второе maximum; поле с % игнорируем
        var parts = line.split(",");
        var nums = [];
        for (var i = 1; i < parts.length; i++) {
            var f = parts[i].trim();
            if (f.indexOf("%") >= 0) continue;
            var v = parseInt(f);
            if (!isNaN(v)) nums.push(v);
        }
        if (nums.length < 2 || nums[1] <= 0) { root.ok = false; return; }
        root.cur = nums[0];
        root.max = nums[1];
        root.ok = true;
        // synced — после присвоения: сигнал frac должен отработать, пока он ещё
        // false, чтобы первичное заполнение не показало OSD
        root.synced = true;
    }

    // первый запуск заодно проверяет наличие утилиты
    Process {
        id: probe
        command: ["sh", "-c", "command -v brightnessctl >/dev/null 2>&1 && brightnessctl -m"]
        stdout: StdioCollector { onStreamFinished: root.parse(this.text) }
    }

    Process {
        id: getProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector { onStreamFinished: root.parse(this.text) }
    }

    Process { id: setProc }

    Timer { id: pullTimer; interval: 200; onTriggered: root.refresh() }

    // мгновенная реакция на хоткеи/другие регуляторы: uevents ядра о смене
    // яркости. udevadm monitor -> каждая строка KERNEL — перечитать значение
    Process {
        id: blWatch
        running: true
        command: ["sh", "-c",
            "udevadm monitor --kernel --subsystem-match=backlight 2>/dev/null | " +
            "grep --line-buffered -E '^KERNEL.*backlight'"]
        stdout: SplitParser { onRead: blTick.restart() }
        onExited: blRevive.restart()
    }

    Timer {
        id: blRevive
        interval: 2000
        onTriggered: blWatch.running = true
    }

    Timer { id: blTick; interval: 120; onTriggered: root.refresh() }

    // страховочный пулл, если watcher не завёлся
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
