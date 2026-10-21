pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Сервер уведомлений: всплывашки (макс. 3) + история (до 50).
 * Живые уведомления хранятся как объекты Notification (n.tracked = true),
 * в историю при закрытии уходит снимок с разрешённой иконкой — handle
 * картинки живёт только пока жив объект уведомления, хранить его нельзя.
 */
Singleton {
    id: root

    property var popups: []
    property var history: []
    property var seenIds: ({})
    property bool dnd: false

    readonly property var tracked: server.trackedNotifications.values

    readonly property int unread: {
        var u = 0;
        for (var i = 0; i < tracked.length; i++)
            if (!seenIds[tracked[i].id]) u++;
        return u;
    }

    /** Иконка для живого уведомления или снимка {icon:...}. */
    function iconFor(n) {
        if (!n) return "";
        var img = n.image || "";
        if (img.length && !/^image:\/\/qsimage\//i.test(img)) {
            if (img.indexOf("image://icon/") === 0)
                img = img.substring(13);
            if (/\.svg$/i.test(img))
                return ""; // svg-путь это обычно appIcon, обработается ниже
            return img;
        }
        return themeIconFor(n);
    }

    function themeIconFor(n) {
        var names = [n.appIcon, n.desktopEntry, (n.appName || "").toLowerCase()];
        for (var i = 0; i < names.length; i++) {
            var nm = names[i];
            if (!nm || !nm.length) continue;
            if (nm.charAt(0) === "/" || nm.indexOf("file://") === 0) return nm;
            var p = Quickshell.iconPath(nm, true);
            if (p.length) return p;
        }
        return "";
    }

    function removePopup(n) {
        root.popups = root.popups.filter(function (p) { return p !== n; });
    }

    function dismissNotif(n) {
        if (n && n._local) {
            // локальные: в историю снимок, как для серверных
            root.history = [{
                app: n.appName,
                summary: n.summary,
                body: n.body,
                icon: root.iconFor(n),
                urgency: n.urgency,
                ts: Date.now(),
                id: "hl" + Date.now()
            }].concat(root.history).slice(0, 50);
            root.removePopup(n);
            return;
        }
        if (n && typeof n.dismiss === "function")
            n.dismiss();
        else
            root.removePopup(n); // уже закрыто сервером — просто убрать
    }

    function clearAll() {
        var l = tracked.slice();
        for (var i = 0; i < l.length; i++)
            if (typeof l[i].dismiss === "function") l[i].dismiss();
        root.popups = [];
        root.history = [];
    }

    function removeHistory(id) {
        root.history = root.history.filter(function (h) { return h.id !== id; });
    }

    // ── клик по тосту → поднять окно приложения ──

    function raiseWindow(n) {
        if (!n) return;
        var token = String(n.desktopEntry && n.desktopEntry.length
            ? n.desktopEntry : (n.appName || "")).toLowerCase();
        if (!token.length) return;
        Quickshell.execDetached(["sh", "-c",
            "addr=$(hyprctl clients -j | jq -r --arg q \"$1\" "
            + "'first(.[] | select(((.class | if . then ascii_downcase else \"\" end) "
            + "| contains($q)) or ((.initialClass | if . then ascii_downcase else \"\" end) "
            + "| contains($q))) | .address)'); "
            + "[ -n \"$addr\" ] && hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\"",
            "sh", token]);
    }

    /** Клик по тосту: invoke default-действия серверного уведомления + поднятие окна. */
    function activatePopup(n) {
        if (!n) return;
        if (!n._local) {
            var acts = n.actions || [];
            for (var i = 0; i < acts.length; i++)
                if (acts[i].identifier === "default") { acts[i].invoke(); break; }
            raiseWindow(n);
        }
        if (root.popups.indexOf(n) >= 0) root.dismissNotif(n);
    }

    // ── звук уведомлений (pw-play, файлы freedesktop) ──

    // Свой звук приложения определяем автоматически, без списка: перед нашим
    // звуком даём приложению грейс на запуск его плеера и ищем его активный
    // стрим в PipeWire (pactl list sink-inputs) по имени приложения/desktop
    // entry. Стрим найден — приложение играет само, наш не дублируем.
    // Критические и локальные уведомления звучат сразу, без проверки.
    function normToken(s) {
        return String(s || "").toLowerCase().replace(/[\s._\-–—·]/g, "");
    }

    property var sndPending: null // последний запрос звука (вытесняет предыдущий)
    property var sndTokens: []
    property bool sndCritical: false

    function requestSound(n, critical) {
        // токены считаем сразу — объект уведомления гарантированно жив
        var name = String(n && n.appName || "");
        var entry = String(n && n.desktopEntry || "");
        var toks = [root.normToken(name), root.normToken(entry),
                    root.normToken(name.split(" ")[0])];
        root.sndPending = {
            tokens: toks.filter(function (t) { return t.length >= 4; }),
            critical: critical
        };
        sndGate.restart();
    }

    Timer {
        id: sndGate
        interval: 200
        onTriggered: root.flushSound()
    }

    function flushSound() {
        if (!root.sndPending) return;
        if (sndProbe.running) { sndGate.restart(); return; } // дождаться текущей проверки
        var p = root.sndPending;
        root.sndPending = null;
        root.sndTokens = p.tokens;
        root.sndCritical = p.critical;
        sndProbe.command = ["sh", "-c", "pactl list sink-inputs 2>/dev/null"];
        sndProbe.running = true;
    }

    Process {
        id: sndProbe
        stdout: StdioCollector {
            onStreamFinished: {
                var dump = root.normToken(this.text);
                for (var i = 0; i < root.sndTokens.length; i++)
                    if (dump.indexOf(root.sndTokens[i]) >= 0) return; // играет сам — молчим
                root.playSound(root.sndCritical);
            }
        }
    }

    function playSound(critical) {
        // Process игнорирует присвоение command бегущему/завершённому —
        // глушим, ставим команду, запускаем
        if (sndProc.running) sndProc.running = false;
        sndProc.command = ["pw-play", critical
            ? "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
            : "/usr/share/sounds/freedesktop/stereo/message.oga"];
        sndProc.running = true;
    }

    Process { id: sndProc }

    /**
     * Тост вытеснен OSD: убрать некритические попапы, сохранив в историю —
     * иначе после OSD тост «прилетит заново» и будет выглядеть вторым.
     */
    function retireTransient() {
        var l = root.popups.slice();
        for (var i = 0; i < l.length; i++) {
            var p = l[i];
            if (p && p.urgency === NotificationUrgency.Critical) continue;
            root.dismissNotif(p);
        }
    }

    /** Локальное уведомление бара (низкий заряд и т.п.) — как настоящий. */
    function pushLocal(summary, body, critical, app) {
        var n = {
            _local: true,
            appName: app || "Батарея",
            summary: summary,
            body: body || "",
            urgency: critical ? NotificationUrgency.Critical : NotificationUrgency.Normal,
            image: "",
            appIcon: "",
            desktopEntry: ""
        };
        if (!root.dnd) {
            root.popups = root.popups.concat([n]).slice(-3);
        }
        playSound(critical);
    }

    function markAllSeen() {
        var m = {};
        for (var i = 0; i < tracked.length; i++)
            m[tracked[i].id] = true;
        root.seenIds = m;
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: function (n) {
            n.tracked = true;
            var critical = n.urgency === NotificationUrgency.Critical;
            console.log("[notifs] new:", n.appName, "critical:", critical);
            if (!root.dnd || critical) {
                root.popups = root.popups.concat([n]).slice(-3);
                if (critical) root.playSound(true);
                else root.requestSound(n, false);
            }
            n.closed.connect(function () {
                console.log("[notifs] closed → history:", n.summary || "");
                root.history = [{
                    app: (n.appName && n.appName.length) ? n.appName : "System",
                    summary: n.summary,
                    body: n.body,
                    icon: root.themeIconFor(n),
                    urgency: n.urgency,
                    ts: Date.now(),
                    id: "h" + n.id + "-" + Date.now()
                }].concat(root.history).slice(0, 50);
                root.removePopup(n);
            });
        }
    }

}
