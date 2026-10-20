pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../Singletons"
import "../components"

/**
 * Питание: 5 плиток — блокировка, выход, сон, перезагрузка, выключение.
 * Опасные действия требуют второго клика-подтверждения (3 с на раздумья).
 */
PillSurface {
    id: root

    w: 430
    h: 158

    property string confirmKey: ""
    onConfirmKeyChanged: if (confirmKey.length) confirmReset.restart()

    Timer {
        id: confirmReset
        interval: 3000
        onTriggered: root.confirmKey = ""
    }

    readonly property var actions: [
        { key: "lock",     glyph: "lock",   label: "Замок",  confirm: false, argv: ["sh", "-c",
                "command -v hyprlock >/dev/null 2>&1 && exec hyprlock; "
                + "command -v swaylock >/dev/null 2>&1 && exec swaylock; "
                + "loginctl lock-session"] },
        { key: "logout",   glyph: "logout", label: "Выход",  confirm: false, dispatch: "exit", argv: [] },
        { key: "suspend",  glyph: "moon",   label: "Сон",    confirm: false, argv: ["systemctl", "suspend"] },
        { key: "reboot",   glyph: "reboot", label: "Ребут",  confirm: true,  argv: ["systemctl", "reboot"] },
        { key: "shutdown", glyph: "power",  label: "Выключить", confirm: true, argv: ["systemctl", "poweroff"] }
    ]

    Process {
        id: actionProc
    }

    function run(a) {
        if (a.dispatch && a.dispatch.length) {
            Hyprland.dispatch(a.dispatch);
            UIState.close();
            return;
        }
        if (a.argv.length) {
            actionProc.command = a.argv;
            actionProc.running = true;
            UIState.close();
        }
    }

    function press(a) {
        if (a.confirm && root.confirmKey !== a.key) {
            root.confirmKey = a.key;
            return;
        }
        root.confirmKey = "";
        root.run(a);
    }

    Row {
        anchors.centerIn: parent
        spacing: 10 * root.s

        Repeater {
            model: root.actions

            delegate: Rectangle {
                id: tile

                required property var modelData

                readonly property bool confirming: root.confirmKey === modelData.key
                readonly property bool hovered: tileArea.containsMouse
                readonly property bool destructive: modelData.key === "reboot" || modelData.key === "shutdown"

                width: 72 * root.s
                height: 92 * root.s
                radius: 16 * root.s

                color: confirming ? Theme.danger
                     : (hovered ? Theme.veilHover : Theme.veil)
                border.width: 1
                border.color: confirming ? Theme.danger : Theme.border

                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Column {
                    anchors.centerIn: parent
                    spacing: 7 * root.s

                    GlyphIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 24 * root.s
                        height: 24 * root.s
                        name: tile.confirming ? "x" : tile.modelData.glyph
                        color: tile.confirming ? "#111318"
                             : tile.hovered ? (tile.destructive ? Theme.danger : Theme.text)
                             : Theme.dim
                        stroke: 2
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.confirming ? "Точно?" : tile.modelData.label
                        color: tile.confirming ? "#111318" : (tile.hovered ? Theme.text : Theme.dim)
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: tile.confirming ? Font.DemiBold : Font.Normal
                    }
                }

                MouseArea {
                    id: tileArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.press(tile.modelData)
                }
            }
        }
    }
}
