pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Настройка темы пилюли: цвет фона, текста и акцента.
 * Живой предпросмотр, пресеты акцента, сохранение в ~/.cache/bar/theme.json.
 */
PillSurface {
    id: root

    w: 396
    h: 356
    wantsKeys: true

    // ── пресеты акцента (Tokyo Night и друзья) ──
    readonly property var accentPresets: [
        "#7aa2f7", "#bb9af7", "#7dcfff", "#9ece6a",
        "#e0af68", "#ff9e64", "#f7768e", "#c0caf5"
    ]
    // ── пресеты фона ──
    readonly property var bgPresets: [
        "#111318", "#1a1b26", "#0f0f17", "#16161e",
        "#1f2335", "#24283b", "#0c0e14", "#2b2d42"
    ]

    component ColorRow: Rectangle {
        id: colorRow

        property string label: ""
        property color value: "#000000"
        signal commit(string hex)

        width: parent.width
        height: 40 * root.s
        radius: Theme.radiusS * root.s
        color: Theme.veil

        Rectangle {
            id: swatch
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 24 * root.s
            height: 24 * root.s
            radius: 8 * root.s
            color: colorRow.value
            border.width: 1
            border.color: Theme.glassBorder
        }

        Text {
            anchors.left: swatch.right
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: colorRow.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11.5 * root.s
        }

        TextInput {
            id: hexInput
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 82 * root.s
            text: colorRow.value.toString().substring(0, 7)
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: "#111318"
            font.family: Theme.font
            font.pixelSize: 11.5 * root.s
            horizontalAlignment: TextInput.AlignRight
            cursorVisible: activeFocus
            selectByMouse: true

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -3 * root.s
                height: 1
                color: hexInput.activeFocus ? Theme.accent : Theme.hair
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            onEditingFinished: {
                var v = text.trim();
                if (/^#[0-9a-fA-F]{6}$/.test(v) || /^#[0-9a-fA-F]{3}$/.test(v))
                    colorRow.commit(v);
                else
                    text = colorRow.value.toString().substring(0, 7);
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !hexInput.activeFocus
            onClicked: hexInput.forceActiveFocus()
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16 * root.s
        spacing: 10 * root.s

        // ── заголовок ──
        Item {
            width: parent.width
            height: 26 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Тема"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fsTitle * root.s
                font.weight: Font.DemiBold
            }

            IconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                icon: "reboot"
                tint: Theme.faint
                activeTint: Theme.text
                onClicked: Theme.resetTheme()
            }
        }

        // ── предпросмотр пилюли ──
        Rectangle {
            width: parent.width
            height: 46 * root.s
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.glassTop }
                GradientStop { position: 1.0; color: Theme.glassBot }
            }
            border.width: 1
            border.color: Theme.glassBorder

            Row {
                anchors.centerIn: parent
                spacing: 10 * root.s

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10 * root.s
                    height: 10 * root.s
                    radius: width / 2
                    color: Theme.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(new Date(), "HH:mm")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14 * root.s
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "предпросмотр"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
            }
        }

        // ── цвета ──
        ColorRow {
            label: "Фон пилюли"
            value: Theme.bg
            onCommit: (hex) => Theme.setTheme(hex, Theme.text.toString().substring(0, 7), Theme.accent.toString().substring(0, 7))
        }
        ColorRow {
            label: "Текст"
            value: Theme.text
            onCommit: (hex) => Theme.setTheme(Theme.bg.toString().substring(0, 7), hex, Theme.accent.toString().substring(0, 7))
        }
        ColorRow {
            label: "Акцент"
            value: Theme.accent
            onCommit: (hex) => Theme.setTheme(Theme.bg.toString().substring(0, 7), Theme.text.toString().substring(0, 7), hex)
        }

        // ── пресеты акцента ──
        Column {
            width: parent.width
            spacing: 6 * root.s

            Text {
                text: "Акцент — пресеты"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.letterSpacing: 0.6
            }

            Row {
                spacing: 8 * root.s

                Repeater {
                    model: root.accentPresets

                    Rectangle {
                        id: accDot

                        required property var modelData

                        width: 22 * root.s
                        height: 22 * root.s
                        radius: width / 2
                        color: accDot.modelData
                        border.width: Theme.accent.toString().substring(0, 7).toUpperCase() === accDot.modelData.toUpperCase() ? 2 : 1
                        border.color: Theme.accent.toString().substring(0, 7).toUpperCase() === accDot.modelData.toUpperCase()
                                      ? Theme.text : Theme.glassBorder
                        scale: accArea.pressed ? 0.85 : 1
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        MouseArea {
                            id: accArea
                            anchors.fill: parent
                            anchors.margins: -4 * root.s
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setTheme(Theme.bg.toString().substring(0, 7), Theme.text.toString().substring(0, 7), accDot.modelData)
                        }
                    }
                }
            }
        }

        // ── пресеты фона ──
        Column {
            width: parent.width
            spacing: 6 * root.s

            Text {
                text: "Фон — пресеты"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.letterSpacing: 0.6
            }

            Row {
                spacing: 8 * root.s

                Repeater {
                    model: root.bgPresets

                    Rectangle {
                        id: bgDot

                        required property var modelData

                        width: 22 * root.s
                        height: 22 * root.s
                        radius: 7 * root.s
                        color: bgDot.modelData
                        border.width: Theme.bg.toString().substring(0, 7).toUpperCase() === bgDot.modelData.toUpperCase() ? 2 : 1
                        border.color: Theme.bg.toString().substring(0, 7).toUpperCase() === bgDot.modelData.toUpperCase()
                                      ? Theme.text : Theme.glassBorder
                        scale: bgArea.pressed ? 0.85 : 1
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        MouseArea {
                            id: bgArea
                            anchors.fill: parent
                            anchors.margins: -4 * root.s
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setTheme(bgDot.modelData, Theme.text.toString().substring(0, 7), Theme.accent.toString().substring(0, 7))
                        }
                    }
                }
            }
        }
    }
}
