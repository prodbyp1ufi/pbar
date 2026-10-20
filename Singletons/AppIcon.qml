pragma Singleton
import QtQuick
import Quickshell

/**
 * Преобразует класс активного окна (HyprInfo.activeClass) в путь к иконке
 * через DesktopEntries, с запасным вариантом по имени класса.
 */
Singleton {
    property string cls: HyprInfo.activeClass
    property string iconPath: ""

    function resolve(c) {
        if (!c || c.length === 0) {
            iconPath = "";
            return;
        }

        var e = null;
        // 1) точный совпадение по id
        try { e = DesktopEntries.byId(c); } catch (err) { e = null; }

        // 2) эвристический поиск (если поддерживается)
        if (!e && typeof DesktopEntries.heuristicLookup === "function") {
            try { e = DesktopEntries.heuristicLookup(c); } catch (err2) { e = null; }
        }

        var ic = "";
        if (e && e.icon && e.icon.length > 0)
            ic = e.icon;
        else if (c.length > 0)
            ic = c.toLowerCase(); // надеемся, что имя класса совпадает с именем иконки

        if (ic.length > 0 && Quickshell.hasThemeIcon(ic))
            iconPath = Quickshell.iconPath(ic);
        else
            iconPath = "";
    }

    onClsChanged: resolve(cls)
}