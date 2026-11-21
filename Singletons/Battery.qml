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

    // «от сети»: надёжнее, чем state === Charging — покрывает PendingCharge и
    // ограничение заряда прошивкой, когда Charging может так и не наступить,
    // из-за чего авто-экономия не снималась после подключения зарядки
    readonly property bool acPowered: !UPower.onBattery

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

    // Профиль ведём оптимистично, а не по ответу powerprofilesctl get: get
    // асинхронный и отстаёт от set. Из-за сравнения запроса с этим устаревшим
    // значением рестор авто-экономии мог проглатываться гонкой get/set, и
    // профиль залипал на power-saver. _wantProfile — последняя цель; при
    // занятом set она доводится в ppSet.onExited.
    property string _wantProfile: ""

    function refreshProfile() {
        ppGet.running = true;
    }

    // публичный выбор профиля отменяет авто-экономию: иначе рестор после
    // зарядки вернул бы профиль вопреки выбору пользователя
    function setProfile(p) {
        root._saverLatched = false;
        root._preSaverProfile = "";
        root._requestProfile(p);
    }

    // внутренний запрос профиля (в т.ч. из авто-экономии)
    function _requestProfile(p) {
        if (!p.length || p === root._wantProfile) return;
        root._wantProfile = p;
        root._pumpProfile();
    }

    // доводит _wantProfile до демона; пока set занят — применится в ppSet.onExited
    function _pumpProfile() {
        if (ppSet.running) return;
        if (!root._wantProfile.length || root._wantProfile === root._profile) {
            root.refreshProfile();
            return;
        }
        root._profile = root._wantProfile; // оптимистично: UI и решения не ждут get
        ppSet.command = ["powerprofilesctl", "set", root._wantProfile];
        ppSet.running = true;
    }

    Process {
        id: ppGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim();
                // пока идёт запись — ответ get устарел (старое состояние демона),
                // не перетираем им свежую цель
                if (p.length && !ppSet.running) {
                    root._profile = p;
                    root._wantProfile = p; // внешнее изменение принимаем за цель
                }
                root.maybeAutoSaver();
            }
        }
    }

    Process {
        id: ppSet
        onExited: root._pumpProfile()
    }

    // ── авто-переход на power-saver ниже порога (0 = выключено) ──
    // Переключает один раз при пересечении порога вниз; наверху порога
    // защёлка сбрасывается. Питание от сети/полный заряд снимают защёлку.
    property int saverAt: 0
    property bool _saverLatched: false
    property string _preSaverProfile: ""

    // авто-экономия снялась — вернуть профиль, который был до переключения
    function _releaseSaver() {
        root._saverLatched = false;
        var back = root._preSaverProfile;
        root._preSaverProfile = "";
        if (back.length) _requestProfile(back);
    }

    function maybeAutoSaver() {
        if (!root.present || root.saverAt <= 0) {
            if (root._saverLatched) _releaseSaver();
            return;
        }
        // от сети (или полная) экономия не нужна — снимаем и возвращаем профиль
        if (root.acPowered || root.full) {
            if (root._saverLatched) _releaseSaver();
            return;
        }
        if (!root._saverLatched && root.pct <= root.saverAt) {
            root._saverLatched = true;
            if (_profile.length && _profile !== "power-saver") {
                root._preSaverProfile = _profile;
                _requestProfile("power-saver");
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
    // подключение/отключение зарядки надёжнее ловить по источнику питания:
    // state может пройти PendingCharge или остаться Discharging при лимите заряда
    onAcPoweredChanged: maybeAutoSaver()

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
