pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Палитра бара: тёмная база пользователя (#111318) + Tokyo Night акцент.
 * База (bg), цвет текста и акцент можно менять на лету из поверхности
 * «tint» — выбор сохраняется в ~/.cache/bar/theme.json. Остальные цвета
 * выводятся из базы, чтобы вся тема оставалась согласованной.
 */
Singleton {
    id: root

    property color bg:        "#111318"
    property color text:      "#eceff4"
    property color accent:    "#7aa2f7"

    // значения по умолчанию — для сброса
    readonly property color bgDefault:     "#111318"
    readonly property color textDefault:   "#eceff4"
    readonly property color accentDefault: "#7aa2f7"

    // ── производные цвета (привязаны к базе) ──
    readonly property color cardTop:   tint(bg, 1.72, 1.75, 1.78)
    readonly property color cardBot:   tint(bg, 1.20, 1.24, 1.28)
    readonly property color border:    tint(bg, 2.25, 2.25, 2.25)
    readonly property color dim:       tint(text, 0.64, 0.64, 0.66)
    readonly property color faint:     tint(text, 0.52, 0.54, 0.57)
    readonly property color accentDim: tint(accent, 0.40, 0.40, 0.42)
    readonly property color danger:    "#f7768e"
    readonly property color ok:        "#9ece6a"
    readonly property color warn:      "#e0af68"

    // полупрозрачные "слои" поверх карточек
    readonly property color hair:      Qt.alpha(text, 0.10)
    readonly property color sheen:     Qt.alpha(text, 0.07)
    readonly property color veil:      Qt.alpha(text, 0.045)
    readonly property color veilHover: Qt.alpha(text, 0.085)
    readonly property color shadow:    Qt.rgba(0, 0, 0, 0.5)

    // ── стекло: полупрозрачная подложка бара/поверхностей ──
    readonly property color glassTop:    Qt.rgba(clamp(bg.r * 1.32 + 0.008), clamp(bg.g * 1.36 + 0.008), clamp(bg.b * 1.36 + 0.008), 0.93)
    readonly property color glassBot:    Qt.rgba(bg.r, bg.g, bg.b, 0.97)
    readonly property color glassBorder: Qt.rgba(0.42, 0.47, 0.55, 0.22)
    readonly property color glassSheen:  Qt.rgba(1, 1, 1, 0.08)

    // ── дизайн-система ──
    // радиусы: L — поверхность, M — карточки/кнопки, S — чипы/ряды
    readonly property int radiusL: 22
    readonly property int radiusM: 14
    readonly property int radiusS: 10

    // типографика: заголовок / тело / подпись / мелочь (минимум 10 по HIG)
    readonly property real fsTitle:   13
    readonly property real fsBody:    11
    readonly property real fsSmall:   10
    readonly property real fsCaption: 10

    // мягкая заливка акцентом (активные чипы, выделение)
    readonly property color accentSoft: Qt.alpha(accent, 0.14)

    readonly property string font: "JetBrainsMono Nerd Font"

    // ── утилиты вывода цвета ──
    function clamp(v) { return Math.max(0, Math.min(1, v)); }
    function tint(base, kr, kg, kb) {
        return Qt.rgba(clamp(base.r * kr), clamp(base.g * kg), clamp(base.b * kb), 1);
    }

    function setTheme(bgHex, textHex, accentHex) {
        root.bg = bgHex;
        root.text = textHex;
        root.accent = accentHex;
        store.writeAdapter();
    }

    function resetTheme() {
        setTheme(root.bgDefault, root.textDefault, root.accentDefault);
    }

    // ── персист темы: отдельная папка бара в кэше ──
    readonly property string cacheBase:
        Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string storeDir: cacheBase + "/bar"
    readonly property string storePath: storeDir + "/theme.json"

    Component.onCompleted: mkStore.running = true

    // папка под файлы бара + разовый перенос старого файла
    // (~/.cache/bar-theme.json) — после переезда можно убрать перенос
    Process {
        id: mkStore
        command: ["sh", "-c",
            "mkdir -p '" + root.storeDir + "'; "
            + "[ -f '" + root.cacheBase + "/bar-theme.json' ] && mv -n '"
            + root.cacheBase + "/bar-theme.json' '" + root.storePath + "'; true"]
        onExited: store.reload()
    }

    FileView {
        id: store
        path: root.storePath
        watchChanges: false
        blockLoading: true
        onLoaded: {
            if (typeof json.bg === "string" && json.bg.length) root.bg = json.bg;
            if (typeof json.text === "string" && json.text.length) root.text = json.text;
            if (typeof json.accent === "string" && json.accent.length) root.accent = json.accent;
        }

        JsonAdapter {
            id: json
            property string bg: root.bg.toString().substring(0, 7)
            property string text: root.text.toString().substring(0, 7)
            property string accent: root.accent.toString().substring(0, 7)
        }
    }
}
