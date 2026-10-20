pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Сеть — целиком через nmcli: скан сетей, радио, подключение (в т.ч. по
 * паролю), отключение и «забыть». Quickshell.Networking в этой сборке
 * отдаёт почти пустой список сетей, поэтому не используется.
 *
 * nets: [{name, signalStrength (0-100), connected}] — форма совместима
 * с прежней (Pill и Wifi читают name/signalStrength/connected).
 */
Singleton {
    id: root

    readonly property bool wifiOn: _wifiOn
    property bool _wifiOn: false

    /** [{name, signalStrength, connected}] */
    property var nets: []
    readonly property var activeNet: {
        for (var i = 0; i < nets.length; i++)
            if (nets[i] && nets[i].connected) return nets[i];
        return null;
    }
    readonly property string activeSsid: activeNet ? (activeNet.name || "") : ""
    readonly property real strength: activeNet ? ((activeNet.signalStrength || 0) / 100) : 0

    readonly property bool ethernetUp: _ethernetUp
    property bool _ethernetUp: false

    /** {ssid: "WPA2"|""} — пустая строка = открытая сеть */
    property var securityMap: ({})
    /** {ssid: true} — сохранённые профили */
    property var knownProfiles: ({})
    /** wifi-интерфейс (wlp2s0) — для отключения */
    property string wifiIface: ""

    function isSecured(ssid) {
        var s = securityMap[ssid];
        return s !== undefined && s.length > 0;
    }

    function toggleWifi() {
        root.runNm(["radio", "wifi", _wifiOn ? "off" : "on"]);
    }

    function rescan() {
        scanProc.running = true;
    }

    function refreshMeta() {
        metaProc.running = true;
    }

    /** Открытая или сохранённая сеть — nmcli сам возьмёт сохранённый пароль */
    function connectSsid(ssid) {
        if (connProc.running || !ssid.length) return;
        _connecting = true;
        _connectFailed = false;
        connProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
        connProc.running = true;
    }

    function connectWithPassword(ssid, pw) {
        if (connProc.running || !ssid.length || !pw.length) return;
        _connecting = true;
        _connectFailed = false;
        connProc.command = ["nmcli", "dev", "wifi", "connect", ssid, "password", pw];
        connProc.running = true;
    }

    function disconnectWifi() {
        if (!wifiIface.length) return;
        root.runNm(["device", "disconnect", wifiIface]);
    }

    function forget(ssid) {
        if (!ssid.length) return;
        root.runNm(["connection", "delete", "id", ssid]);
    }

    /** пароль сохранённой сети (-s = показать секреты) */
    property string wifiPw: ""
    function showPassword(ssid) {
        root.wifiPw = "";
        if (!ssid.length) return;
        pwProc.command = ["nmcli", "-s", "-g", "802-11-wireless-security.psk",
                          "connection", "show", ssid];
        pwProc.running = true;
    }

    // ── QR для «поделиться» сетью: nmcli → payload → qrencode → PNG в /tmp.
    // Каждому коду своё имя файла, иначе Image отдаёт закэшированную картинку.
    // Отдельные процессы: pwProc живёт для «показать пароль», здесь — свой,
    // чтобы запросы не перебивали друг друга (command у бегущего Process
    // игнорируется — из-за этого цепочка часто срывалась).
    property string qrFile: ""
    property string _qrSsid: ""
    property int _qrN: 0

    function makeQr(ssid) {
        root.qrFile = "";
        root._qrSsid = ssid;
        root.wifiPw = "";
        if (!ssid.length) return;
        if (qrPwProc.running) qrPwProc.running = false;
        qrPwProc.command = ["nmcli", "-s", "-g", "802-11-wireless-security.psk",
                            "connection", "show", ssid];
        qrPwProc.running = true;
    }

    function _wifiPayload(ssid, pw) {
        // экранирование спецсимволов формата WIFI: (\ ; , : ")
        var s = ssid.replace(/([\\;,:"])/g, "\\$1");
        var p = pw.replace(/([\\;,:"])/g, "\\$1");
        return pw.length
            ? "WIFI:T:WPA;S:" + s + ";P:" + p + ";;"
            : "WIFI:T:nopass;S:" + s + ";;";
    }

    Process {
        id: qrProc
        property string outPath: ""
        stderr: SplitParser {
            onRead: data => console.warn("[qr] qrencode:", data)
        }
        onExited: function (code) {
            if (code !== 0) {
                console.warn("[qr] qrencode завершился с кодом", code);
                return;
            }
            if (root._qrN > 0)
                root.qrFile = "file://" + outPath;
        }
    }

    // пароль конкретно для QR — не пересекается с «показать пароль»
    Process {
        id: qrPwProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiPw = this.text.trim();
                root._qrN++;
                var path = "/tmp/qsbar-qr-" + root._qrN + ".png";
                qrProc.outPath = path;
                if (qrProc.running) qrProc.running = false;
                qrProc.command = ["qrencode", "-t", "PNG", "-o", path,
                                  "-s", "10", "-m", "2", "-l", "M",
                                  root._wifiPayload(root._qrSsid, root.wifiPw)];
                qrProc.running = true;
            }
        }
    }

    function runNm(argv) {
        nmProc.command = ["nmcli"].concat(argv);
        nmProc.running = true;
    }

    property bool _connecting: false
    readonly property bool connecting: _connecting
    property bool _connectFailed: false
    readonly property bool connectFailed: _connectFailed

    Component.onCompleted: refreshMeta()

    // опрос редко и дешево: один процесс, четыре быстрых вызова nmcli
    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refreshMeta()
    }

    Process {
        id: metaProc
        command: ["sh", "-c",
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null; printf '@@@'; "
            + "nmcli -t -f NAME,TYPE connection show 2>/dev/null; printf '@@@'; "
            + "nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null; printf '@@@'; "
            + "nmcli radio wifi 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.split("@@@");

                // ── скан сетей: "IN-USE:SSID:SIGNAL:SECURITY" (SSID может содержать ':')
                var arr = [];
                var sec = {};
                try {
                    var lines = parts[0].split("\n");
                    for (var i = 0; i < lines.length; i++) {
                        var l = lines[i];
                        if (!l.length) continue;
                        var idx1 = l.indexOf(":");
                        var idxLast = l.lastIndexOf(":");
                        var idxSig = l.lastIndexOf(":", idxLast - 1);
                        if (idx1 < 0 || idxSig < 0 || idxLast <= idxSig) continue;
                        var inuse = l.substring(0, idx1);
                        var ssid = l.substring(idx1 + 1, idxSig);
                        var signal = parseInt(l.substring(idxSig + 1, idxLast));
                        var security = l.substring(idxLast + 1);
                        if (!ssid.length || isNaN(signal)) continue;
                        arr.push({
                            name: ssid,
                            signalStrength: signal,
                            connected: inuse.indexOf("*") >= 0
                        });
                        sec[ssid] = security;
                    }
                } catch (e) { }

                // ── сохранённые профили
                var known = {};
                try {
                    var cl = parts[1].split("\n");
                    for (var j = 0; j < cl.length; j++) {
                        var ci = cl[j].lastIndexOf(":");
                        if (ci < 0) continue;
                        var name = cl[j].substring(0, ci);
                        var type = cl[j].substring(ci + 1);
                        if (name.length && type.indexOf("wireless") >= 0)
                            known[name] = true;
                    }
                } catch (e2) { }

                // ── устройства: wifi-интерфейс и ethernet
                var iface = "";
                var eth = false;
                try {
                    var dl = parts[2].split("\n");
                    for (var k = 0; k < dl.length; k++) {
                        var fields = dl[k].split(":");
                        if (fields.length < 3) continue;
                        var dev = fields[0];
                        var dtype = fields[1];
                        var dstate = fields.slice(2).join(":");
                        if (dtype === "wifi" && iface.length === 0) iface = dev;
                        if (dtype === "ethernet" && dstate === "connected") eth = true;
                    }
                } catch (e3) { }

                // пересоздаём список только когда он реально изменился
                // (состав сетей или подключённость). Сравнение БЕЗ учёта
                // порядка: nmcli при каждом скане отдаёт сети в разном
                // порядке, и сравнение по индексам пересобирало список
                // почти при каждом опросе — скролл меню прыгал наверх.
                // Сила сигнала обновляется на месте, без уведомления
                var same = arr.length === root.nets.length;
                var match = [];
                if (same) {
                    var used = [];
                    for (var n = 0; n < arr.length; n++) {
                        var found = -1;
                        for (var q = 0; q < root.nets.length; q++) {
                            if (!used[q] && root.nets[q].name === arr[n].name) {
                                found = q;
                                break;
                            }
                        }
                        if (found < 0
                            || root.nets[found].connected !== arr[n].connected) {
                            same = false;
                            break;
                        }
                        used[found] = true;
                        match[n] = found;
                    }
                }
                if (same) {
                    for (var m = 0; m < arr.length; m++)
                        root.nets[match[m]].signalStrength = arr[m].signalStrength;
                } else {
                    root.nets = arr;
                }
                root.securityMap = sec;
                root.knownProfiles = known;
                root.wifiIface = iface;
                root._ethernetUp = eth;

                var radio = (parts[3] || "").trim();
                if (radio.length)
                    root._wifiOn = radio.indexOf("enabled") >= 0;
            }
        }
    }

    Process {
        id: scanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: delayedRefresh.start()
    }

    Timer {
        id: delayedRefresh
        interval: 2500
        onTriggered: root.refreshMeta()
    }

    Process {
        id: connProc
        onExited: function (code) {
            root._connecting = false;
            root._connectFailed = code !== 0;
            root.refreshMeta();
        }
    }

    Process {
        id: nmProc
        onExited: root.refreshMeta()
    }
}
