pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

/**
 * Bluetooth через Quickshell.Bluetooth (BlueZ D-Bus напрямую): никаких
 * процессов и парсинга вывода bluetoothctl. Адаптер и устройства приходят
 * реактивно; connect/disconnect/forget — методы устройства, сопряжение —
 * штатный pair(). Список devices — прежняя форма ({mac, name, paired,
 * connected}), чтобы потребители не менялись.
 */
Singleton {
    id: root

    readonly property var adapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null

    property bool powered: adapter ? adapter.enabled === true : false
    property string ctrlName: adapter && adapter.name ? adapter.name : ""

    /** [{mac, name, paired, connected, pairing, connecting, battery}] */
    property var devices: []

    // busy: идёт сопряжение или какое-то устройство в переходном состоянии
    readonly property bool busy: {
        if (_pendingMac.length > 0) return true;
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i];
            if (d && (d.pairing || d.connecting)) return true;
        }
        return false;
    }

    property bool scanning: adapter ? adapter.discovering === true : false

    // сырой список: пересобирается при добавлении/удалении устройств
    readonly property var rawDevices: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices)
                                      ? Bluetooth.devices.values : []
    onRawDevicesChanged: rebuild()

    property string _pendingMac: ""

    Component.onCompleted: rebuild()

    // Устройства — живые QObject'ы: изменение connected/paired не меняет сам
    // список values, у каждого объекта вешаем свои Connection'ы на обновление
    Instantiator {
        model: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices) ? Bluetooth.devices : null

        delegate: QtObject {
            id: watcher

            required property var modelData
            readonly property Item sigHost: Item {
                Timer { id: t; interval: 300; onTriggered: root.refSoon.restart() }
                Connections {

                    target: watcher.modelData

                    function onConnectedChanged() { t.restart(); }

                    function onPairedChanged() {

                        t.restart();

                        root.maybeConnectAfterPair(watcher.modelData);

                    }

                    function onPairingChanged() { t.restart(); }

                    function onNameChanged() { t.restart(); }

                    function onStateChanged() { t.restart(); }

                    function onBatteryChanged() { t.restart(); }
                }
            }
        }
    }

    // склейка обновлений: несколько сигналов подряд → одна пересборка
    Timer { id: refSoon; interval: 300; onTriggered: root.rebuild() }

    Timer {
        id: scanTimer
        interval: 20000
        onTriggered: root.stopScan()
    }

    // страховка: pair мог молча не пройти (устройство ждёт PIN) — снимаем
    // ожидание, иначе busy висит и блокирует остальные кнопки
    Timer {
        id: pendingTimer
        interval: 35000
        onTriggered: root._pendingMac = ""
    }

    function refresh() { rebuild(); }

    function rebuild() {
        var src = root.rawDevices;
        var arr = [];
        for (var i = 0; i < src.length; i++) {
            var d = src[i];
            if (!d || !d.address || !d.address.length) continue;
            var connecting = false;
            if (typeof BluetoothDeviceState !== "undefined")
                connecting = d.state === BluetoothDeviceState.Connecting;
            var batt = -1;
            if (d.batteryAvailable && d.battery > 0)
                batt = Math.round(d.battery <= 1 ? d.battery * 100 : d.battery);
            var nm = (d.deviceName && d.deviceName.length) ? d.deviceName : d.name;
            arr.push({
                mac: d.address,
                name: (nm && nm.length) ? nm : "Неизвестное устройство",
                paired: d.paired === true,
                connected: d.connected === true,
                pairing: d.pairing === true,
                connecting: connecting,
                battery: batt
            });
        }
        // без изменений структуры не трогаем список — иначе меню дёргается
        // и сбрасывает скролл; сравнение без учёта порядка — по mac
        var same = arr.length === root.devices.length;
        if (same) {
            var used = [];
            for (var a = 0; a < arr.length; a++) {
                var found = -1;
                for (var q = 0; q < root.devices.length; q++) {
                    if (!used[q] && root.devices[q].mac === arr[a].mac) { found = q; break; }
                }
                if (found < 0
                    || root.devices[found].name !== arr[a].name
                    || root.devices[found].paired !== arr[a].paired
                    || root.devices[found].connected !== arr[a].connected
                    || root.devices[found].pairing !== arr[a].pairing
                    || root.devices[found].connecting !== arr[a].connecting
                    || root.devices[found].battery !== arr[a].battery) {
                    same = false;
                    break;
                }
                used[found] = true;
            }
        }
        if (!same) root.devices = arr;
    }

    function maybeConnectAfterPair(dev) {
        if (!dev || !_pendingMac.length || dev.address !== _pendingMac) return;
        if (dev.paired === true) {
            _pendingMac = "";
            pendingTimer.stop();
            if (!dev.connected) dev.connect();
        }
    }

    function togglePower() {
        if (!root.adapter) return;
        if (root.adapter.enabled) {
            root.adapter.enabled = false;
            return;
        }
        // пока rfkill блокирует контроллер, BlueZ отклонит power on — сначала unblock
        if (typeof BluetoothAdapterState !== "undefined"
                && root.adapter.state === BluetoothAdapterState.Blocked) {
            rfkillProc.command = ["rfkill", "unblock", "bluetooth"];
            if (rfkillProc.running) rfkillProc.running = false;
            rfkillProc.running = true;
        } else {
            root.adapter.enabled = true;
        }
    }

    Process {
        id: rfkillProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: if (root.adapter) root.adapter.enabled = true
    }

    function startScan() {
        if (!root.adapter) return;
        if (root.adapter.discovering) { scanTimer.restart(); return; }
        root.adapter.discovering = true;
        scanTimer.restart();
    }

    function stopScan() {
        if (root.adapter && root.adapter.discovering) root.adapter.discovering = false;
        scanTimer.stop();
    }

    function deviceByMac(mac) {
        var src = root.rawDevices;
        for (var i = 0; i < src.length; i++) {
            var d = src[i];
            if (d && d.address === mac) return d;
        }
        return null;
    }

    function connect(mac) {
        if (root.busy) return;
        var d = deviceByMac(mac);
        if (d && !d.connected) d.connect();
    }

    function disconnect(mac) {
        if (root.busy) return;
        var d = deviceByMac(mac);
        if (d && d.connected) d.disconnect();
    }

    function remove(mac) {
        if (root.busy) return;
        var d = deviceByMac(mac);
        if (d) d.forget();
    }

    function pairAndConnect(mac) {
        if (root.busy) return;
        var d = deviceByMac(mac);
        if (!d) return;
        if (d.paired) {
            if (!d.connected) d.connect();
            return;
        }
        // сопряжение: после появления paired автоподключаем; если BlueZ
        // требует подтверждения — pendingTimer снимет ожидание через 35с
        _pendingMac = mac;
        pendingTimer.restart();
        d.pair();
    }
}