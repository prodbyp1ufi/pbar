pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

/**
 * Активный медиаплеер: фильтрует playerctld-прокси, выбирает играющий плеер
 * (или ручной выбор) и отдаёт плоские свойства для бара и поверхности медиа.
 */
Singleton {
    id: root

    function isProxy(p) {
        return (p && p.dbusName ? p.dbusName : "").toLowerCase().indexOf("playerctld") >= 0;
    }

    function isIdle(p) {
        if (!p || isProxy(p))
            return true;
        return !p.isPlaying && (!p.trackTitle || p.trackTitle.length === 0);
    }

    readonly property var list: {
        var all = Mpris.players.values;
        var out = [];
        for (var i = 0; i < all.length; i++)
            if (all[i] && !isProxy(all[i]))
                out.push(all[i]);
        return out;
    }

    property var manual: null
    onListChanged: if (manual && list.indexOf(manual) < 0) manual = null;

    readonly property var active: {
        if (manual && list.indexOf(manual) >= 0)
            return manual;
        for (var i = 0; i < list.length; i++)
            if (list[i].isPlaying)
                return list[i];
        for (var j = 0; j < list.length; j++)
            if (!isIdle(list[j]))
                return list[j];
        return list.length > 0 ? list[0] : null;
    }

    readonly property bool has: active !== null
    readonly property bool playing: has && active.isPlaying
    readonly property string title: has ? (active.trackTitle || "") : ""
    readonly property string artist: has ? joinArtists(active.trackArtists, active.trackArtist) : ""
    readonly property string album: has ? (active.trackAlbum || "") : ""
    readonly property string artUrl: has ? (active.trackArtUrl || "") : ""
    readonly property real lengthSec: has && active.length > 0 ? active.length : 0
    readonly property bool live: has && (lengthSec <= 0 || lengthSec > 86400)
    readonly property string source: has ? labelOf(active) : ""

    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }

    function labelOf(p) {
        if (!p) return "";
        var n = p.identity ? p.identity : (p.desktopEntry ? p.desktopEntry : "");
        return n.length > 0 ? n : "media";
    }

    function select(p) {
        root.manual = (p && list.indexOf(p) >= 0) ? p : null;
    }
}
