pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Снимок экрана (область / весь экран / окно кликом — сразу в файл и в
 * буфер) и запись экрана gpu-screen-recorder'ом: монитор, окно или
 * область, системный звук и/или микрофон, с таймером и кнопкой стоп.
 */
PillSurface {
    id: root

    w: 360

    h: 396

    property int tick: 0

    Timer {
        interval: 1000
        running: Shot.recording
        repeat: true
        onTriggered: root.tick++
    }

    function recLabel() {
        void root.tick;
        var sec = Math.floor((Date.now() - Shot.recStart) / 1000);
        var m = Math.floor(sec / 60);
        var s = sec % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16 * root.s
        spacing: 9 * root.s

        Text {
            text: "Снимок экрана"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.fsTitle * root.s
            font.weight: Font.DemiBold
        }

        // ── три кнопки снимков ──
        Row {
            width: parent.width
            spacing: 8 * root.s

            Repeater {
                model: [
                    { label: "Область", icon: "crop", act: "region" },
                    { label: "Экран", icon: "monitor", act: "screen" },
                    { label: "Окно", icon: "window", act: "window" }
                ]

                delegate: Rectangle {
                    id: shotBtn

                    required property var modelData

                    width: (parent.width - 2 * 8 * root.s) / 3
                    height: 62 * root.s
                    radius: Theme.radiusM * root.s
                    color: shotBtnArea.containsMouse ? Theme.veilHover : Theme.veil
                    border.width: 1
                    border.color: shotBtnArea.containsMouse ? Theme.accentDim : Theme.border
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 5 * root.s

                        GlyphIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 17 * root.s
                            height: 17 * root.s
                            name: shotBtn.modelData.icon
                            color: shotBtnArea.containsMouse ? Theme.text : Theme.dim
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: shotBtn.modelData.label
                            color: shotBtnArea.containsMouse ? Theme.text : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                        }
                    }

                    MouseArea {
                        id: shotBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (shotBtn.modelData.act === "region") Shot.shotRegion();
                            else if (shotBtn.modelData.act === "window") Shot.shotWindow();
                            else Shot.shotScreen();
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: Shot.lastShot.length > 0
            text: Shot.lastShot.replace(Shot.home, "~")
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            elide: Text.ElideMiddle
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        // ── запись ──
        Row {
            width: parent.width
            spacing: 7 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Запись экрана"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fsTitle * root.s
                font.weight: Font.DemiBold
            }

            Item { width: parent.width - 230 * root.s; height: 1 }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: Shot.recording
                width: 9 * root.s
                height: 9 * root.s
                radius: width / 2
                color: Theme.danger

                SequentialAnimation on opacity {
                    running: Shot.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.2; duration: 600 }
                    NumberAnimation { to: 1; duration: 600 }
                }
            }
        }

        Row {
            width: parent.width
            spacing: 8 * root.s

            Repeater {
                model: [
                    { key: "mon", icon: "monitor", label: "Экран" },
                    { key: "win", icon: "window", label: "Окно" },
                    { key: "region", icon: "crop", label: "Область" }
                ]



                delegate: Rectangle {

                    id: scopeChip



                    required property var modelData



                    property bool on: Shot.recScope === scopeChip.modelData.key



                    width: (parent.width - 2 * 8 * root.s) / 3

                    height: 62 * root.s

                    radius: Theme.radiusM * root.s

                    color: scopeChip.on ? Theme.accent : (scopeArea.containsMouse ? Theme.veilHover : Theme.veil)

                    border.width: 1

                    border.color: scopeChip.on ? Theme.accent : (scopeArea.containsMouse ? Theme.accentDim : Theme.border)

                    Behavior on color { ColorAnimation { duration: Motion.fast } }



                    Column {

                        anchors.centerIn: parent

                        spacing: 5 * root.s

                        GlyphIcon {

                            anchors.horizontalCenter: parent.horizontalCenter

                            width: 17 * root.s
                            height: 17 * root.s
                            name: scopeChip.modelData.icon

                            color: scopeChip.on ? "#111318" : (scopeArea.containsMouse ? Theme.text : Theme.dim)

                        }

                        Text {

                            anchors.horizontalCenter: parent.horizontalCenter

                            text: scopeChip.modelData.label

                            color: scopeChip.on ? "#111318" : (scopeArea.containsMouse ? Theme.text : Theme.dim)

                            font.family: Theme.font

                            font.pixelSize: 10 * root.s

                        }

                    }



                    MouseArea {

                        id: scopeArea

                        hoverEnabled: true

                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: Shot.recScope = scopeChip.modelData.key

                    }

                }
            }
        }

        Row {
            width: parent.width
            spacing: 8 * root.s

            Repeater {
                model: [
                    { key: "recSysAudio", icon: "volume", label: "Звук ПК" },
                    { key: "recMic", icon: "mic", label: "Микрофон" }
                ]



                delegate: Rectangle {

                    id: optChip



                    required property var modelData



                    property bool on: Shot[optChip.modelData.key]



                    width: (parent.width - 8 * root.s) / 2

                    height: 48 * root.s

                    radius: Theme.radiusM * root.s

                    color: optChip.on ? Theme.accent : (optArea.containsMouse ? Theme.veilHover : Theme.veil)

                    border.width: 1

                    border.color: optChip.on ? Theme.accent : (optArea.containsMouse ? Theme.accentDim : Theme.border)

                    Behavior on color { ColorAnimation { duration: Motion.fast } }



                    Column {

                        anchors.centerIn: parent

                        spacing: 5 * root.s

                        GlyphIcon {

                            anchors.horizontalCenter: parent.horizontalCenter

                            width: 17 * root.s
                            height: 17 * root.s
                            name: optChip.modelData.icon

                            color: optChip.on ? "#111318" : (optArea.containsMouse ? Theme.text : Theme.dim)

                        }

                        Text {

                            anchors.horizontalCenter: parent.horizontalCenter

                            text: optChip.modelData.label

                            color: optChip.on ? "#111318" : (optArea.containsMouse ? Theme.text : Theme.dim)

                            font.family: Theme.font

                            font.pixelSize: 10 * root.s

                        }

                    }



                    MouseArea {

                        id: optArea

                        hoverEnabled: true

                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: Shot[optChip.modelData.key] = !Shot[optChip.modelData.key]

                    }

                }
            }
        }

        // ── главная кнопка записи ──
        Rectangle {
            width: parent.width
            height: 42 * root.s
            radius: Theme.radiusM * root.s
            color: Shot.recording ? Theme.danger : Theme.accent

            Row {
                anchors.centerIn: parent
                spacing: 8 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15 * root.s
                    height: 15 * root.s
                    name: Shot.recording ? "stop" : "play"
                    color: "#111318"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Shot.recording ? ("Остановить  " + root.recLabel()) : "Начать запись"
                    color: "#111318"
                    font.family: Theme.font
                    font.pixelSize: 11.5 * root.s
                    font.weight: Font.DemiBold
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (Shot.recording) Shot.stopRec();
                    else if (Shot.recScope === "region") Shot.startRecRegion();
                    else if (Shot.recScope === "win") Shot.startRecWindow();
                    else Shot.startRec("");
                }
            }
        }

        Text {
            width: parent.width
            visible: Shot.lastError.length > 0
            text: Shot.lastError
            color: Theme.danger
            font.family: Theme.font
            font.pixelSize: 10 * root.s
        }

        // ── папки ──
        Row {
            width: parent.width
            spacing: 6 * root.s

            Rectangle {
                width: (parent.width - 6 * root.s) / 2
                height: 26 * root.s
                radius: 9 * root.s
                color: f1.containsMouse ? Theme.veilHover : Theme.veil

                Row {
                    anchors.centerIn: parent
                    spacing: 6 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12 * root.s
                        height: 12 * root.s
                        name: "folder"
                        color: f1.containsMouse ? Theme.text : Theme.dim
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Снимки"
                        color: f1.containsMouse ? Theme.text : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }
                }

                MouseArea {
                    id: f1
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Shot.openFolder(Shot.shotDir)
                }
            }

            Rectangle {
                width: (parent.width - 6 * root.s) / 2
                height: 26 * root.s
                radius: 9 * root.s
                color: f2.containsMouse ? Theme.veilHover : Theme.veil

                Row {
                    anchors.centerIn: parent
                    spacing: 6 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12 * root.s
                        height: 12 * root.s
                        name: "folder"
                        color: f2.containsMouse ? Theme.text : Theme.dim
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Записи"
                        color: f2.containsMouse ? Theme.text : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                    }
                }

                MouseArea {
                    id: f2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Shot.openFolder(Shot.recDir)
                }
            }
        }
    }
}
