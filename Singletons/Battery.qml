pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * Батарея через UPower. На десктопе без аккумулятора present === false —
 * модуль батареи просто не показывается.
 */
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev !== null && dev.isLaptopBattery && dev.isPresent

    readonly property int pct: dev ? Math.round(Math.max(0, Math.min(1, dev.percentage)) * 100) : 0
    readonly property int state: dev ? dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool full: state === UPowerDeviceState.FullyCharged || pct >= 100
    readonly property bool low: discharging && pct <= 20

    // уведомления о низком заряде: защёлки, чтобы не спамить каждый опрос
    property bool _warnLow: false
    property bool _warn10: false

    function checkLowBattery() {
        if (!root.present) return;
        if (root.charging || root.full) {
            root._warnLow = false;
            root._warn10 = false;
            return;
        }
        if (root.discharging) {
            // порог «низкого заряда» = порог авто-экономии, чтобы уведомление
            // приходило в тот же момент, что и переключение профиля
            // (авто-экономия выключена — предупреждаем на 20%)
            var lowAt = root.saverAt > 0 ? root.saverAt : 20;
            if (root.pct <= 10 && !root._warn10) {
                root._warn10 = true;
                Notifs.pushLocal("Критический заряд — " + root.pct + "%",
                                 "Подключите зарядное устройство", true, "Батарея");
            } else if (root.pct <= lowAt && !root._warnLow && !root._warn10) {
                root._warnLow = true;
                Notifs.pushLocal("Низкий заряд — " + root.pct + "%",
                                 "Подключите зарядное устройство", false, "Батарея");
            }
        }
    }

    readonly property real rateW: !dev ? 0
        : (discharging ? -dev.changeRate : (charging ? dev.changeRate : 0))
    readonly property real capacityWh: dev ? dev.energyCapacity : 0

    readonly property bool hasTime: dev ? (charging ? dev.timeToFull > 0 : (discharging ? dev.timeToEmpty > 0 : false)) : false
    readonly property string timeStr: !dev ? ""
        : (charging ? fmt(dev.timeToFull) : (discharging ? fmt(dev.timeToEmpty) : ""))

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (h > 0) return h + " ч " + m + " мин";
        return m + " мин";
    }

    function stateLabel() {
        if (charging) return "Заряжается";
        if (full)     return "Заряжена";
        if (discharging) return "Разряжается";
        return "От сети";
    }

    // ── профиль энергопотребления (power-profiles-daemon) ──
    // "performance" | "balanced" | "power-saver"; пусто = демон недоступен
    readonly property bool hasProfiles: _profile.length > 0
    property string _profile: ""
    readonly property string profile: _profile

    function refreshProfile() {
        ppGet.running = true;
    }

    function setProfile(p) {
        if (!p.length || p === _profile || ppSet.running) return;
        ppSet.command = ["powerprofilesctl", "set", p];
        ppSet.running = true;
    }

    Process {
        id: ppGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._profile = this.text.trim();
                root.maybeAutoSaver();
            }
        }
    }

    Process {
        id: ppSet
        onExited: root.refreshProfile()
    }

    // ── авто-переход на power-saver ниже порога (0 = выключено) ──
    // Переключает один раз при пересечении порога вниз; наверху порога
    // защёлка сбрасывается. Зарядка/полный заряд снимают защёлку.
    property int saverAt: 0
    property bool _saverLatched: false
    property string _preSaverProfile: ""

    // авто-экономия снялась — вернуть профиль, который был до переключения
    function _releaseSaver() {
        root._saverLatched = false;
        if (root._preSaverProfile.length && _profile === "power-saver")
            setProfile(root._preSaverProfile);
        root._preSaverProfile = "";
    }

    function maybeAutoSaver() {
        if (root.saverAt <= 0) {
            if (root._saverLatched) _releaseSaver();
            return;
        }
        if (root.charging || root.full) {
            if (root._saverLatched) _releaseSaver();
            return;
        }
        if (!root._saverLatched && root.pct <= root.saverAt) {
            root._saverLatched = true;
            if (_profile.length && _profile !== "power-saver") {
                root._preSaverProfile = _profile;
                setProfile("power-saver");
            }
        } else if (root._saverLatched && root.pct > root.saverAt) {
            _releaseSaver();
        }
    }

    function setSaverAt(v) {
        root.saverAt = Math.max(0, Math.min(100, Math.round(v)));
        json.saverAt = root.saverAt;
        store.writeAdapter();
        root.maybeAutoSaver();
        root.checkLowBattery(); // уведомление синхронно со сменой порога
    }

    onPctChanged: {
        maybeAutoSaver();
        checkLowBattery();
    }
    onChargingChanged: {
        maybeAutoSaver();
        checkLowBattery();
    }

    // ── персист порога: отдельная папка бара в кэше ──
    readonly property string cacheBase:
        Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string storeDir: cacheBase + "/bar"
    readonly property string storePath: storeDir + "/battery.json"

    Component.onCompleted: mkStore.running = true

    // папка под файлы бара + разовый перенос старого файла
    // (~/.cache/bar-battery.json) — после переезда можно убрать перенос
    Process {
        id: mkStore
        command: ["sh", "-c",
            "mkdir -p '" + root.storeDir + "'; "
            + "[ -f '" + root.cacheBase + "/bar-battery.json' ] && mv -n '"
            + root.cacheBase + "/bar-battery.json' '" + root.storePath + "'; true"]
        onExited: store.reload()
    }

    FileView {
        id: store
        path: root.storePath
        watchChanges: false
        blockLoading: true
        onLoaded: {
            root.saverAt = json.saverAt;
            root.maybeAutoSaver();
            root.checkLowBattery(); // батарея уже ниже порога — уведомить сразу
        }

        JsonAdapter {
            id: json
            property int saverAt: 0
        }
    }
}
