pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import "../Singletons"
import "../components"

/**
 * Микшер: фейдеры вывода и входа с мьютом, ниже — списки устройств с
 * выбором устройства по умолчанию (wpctl set-default, id = id ноды PipeWire).
 * Все строки якорные — фейдер растягивается между левой границей и
 * кнопкой мьюта, проценты прижаты к правому краю, ничего не вылезает.
 */
PillSurface {
    id: root

    w: 380
    h: 430

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // громкость/мьют/дефолт — через wpctl (Audio): ноды quickshell в этой сборке
    // не привязаны к реестру, запись и чтение через них не работают.
    // id нод читается нормально — он же используется в wpctl set-default.
    readonly property int sinkId: (sink && sink.id !== undefined && sink.id !== null) ? sink.id : -1
    readonly property int srcId: (source && source.id !== undefined && source.id !== null) ? source.id : -1

    readonly property var sinks: {
        var all = Pipewire.nodes.values;
        var out = [];
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.isSink && n.audio && n.name && n.name.indexOf(".monitor") < 0)
                out.push(n);
        }
        return out;
    }

    readonly property var sources: {
        var all = Pipewire.nodes.values;
        var out = [];
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && !n.isSink && n.audio && n.name && n.name.indexOf(".monitor") < 0)
                out.push(n);
        }
        return out;
    }

    function nodeLabel(n) {
        if (!n) return "";
        return (n.description && n.description.length) ? n.description : (n.name || "");
    }

    Flickable {
        id: mixFlick
        anchors.fill: parent
        anchors.margins: 16 * root.s
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 12 * root.s

            // ── заголовок вывода ──
            Item {
                width: parent.width
                height: 24 * root.s

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.s
                        height: 18 * root.s
                        name: "volume"
                        level: Audio.sinkMute ? -1 : Audio.sinkVol
                        color: Theme.dim
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Вывод"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.fsTitle * root.s
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width * 0.55)
                    text: root.nodeLabel(root.sink)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
            }

            // ── фейдер вывода ──
            Item {
                width: parent.width
                height: 30 * root.s

                Fader {
                    anchors.left: parent.left
                    anchors.right: muteOut.left
                    anchors.rightMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    value: Audio.sinkVol
                    muted: Audio.sinkMute
                    onMoved: (v) => Audio.setSinkVolume(v)
                }

                Rectangle {
                    id: muteOut
                    anchors.right: pctOut.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30 * root.s
                    height: 30 * root.s
                    radius: 9 * root.s
                    color: muteOutArea.containsMouse || Audio.sinkMute ? Theme.veilHover : Theme.veil

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 14 * root.s
                        height: 14 * root.s
                        name: Audio.sinkMute ? "x" : "volume"
                        level: Audio.sinkMute ? -1 : Audio.sinkVol
                        color: Audio.sinkMute ? Theme.danger : Theme.dim
                    }

                    MouseArea {
                        id: muteOutArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.toggleSinkMute()
                    }
                }

                Text {
                    id: pctOut
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34 * root.s
                    text: Math.round(Audio.sinkVol * 100) + "%"
                    color: Audio.sinkMute ? Theme.faint : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignRight
                }
            }

            // устройства вывода
            Repeater {
                model: root.sinks.slice(0, 4)

                delegate: Rectangle {
                    id: devRow

                    required property var modelData

                    width: body.width
                    height: 30 * root.s
                    radius: Theme.radiusS * root.s
                    color: devArea.containsMouse ? Theme.veilHover : "transparent"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.s
                        height: 9 * root.s
                        radius: width / 2
                        color: devRow.modelData.id === root.sinkId ? Theme.accent : "transparent"
                        border.width: 1
                        border.color: devRow.modelData.id === root.sinkId ? Theme.accent : Theme.faint
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 24 * root.s
                        anchors.right: parent.right
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.nodeLabel(devRow.modelData)
                        color: devRow.modelData.id === root.sinkId ? Theme.text : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: devArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.setDefaultSink(devRow.modelData.id)
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.hair }

            // ── заголовок входа ──
            Item {
                width: parent.width
                height: 24 * root.s

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.s
                        height: 18 * root.s
                        name: "mic"
                        color: Audio.srcMute ? Theme.danger : Theme.dim
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Вход"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.fsTitle * root.s
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width * 0.55)
                    text: root.nodeLabel(root.source)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
            }

            // ── фейдер входа ──
            Item {
                width: parent.width
                height: 30 * root.s

                Fader {
                    anchors.left: parent.left
                    anchors.right: muteIn.left
                    anchors.rightMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    value: Audio.srcVol
                    muted: Audio.srcMute
                    fillColor: Audio.srcMute ? Theme.faint : Theme.warn
                    onMoved: (v) => Audio.setSrcVolume(v)
                }

                Rectangle {
                    id: muteIn
                    anchors.right: pctIn.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30 * root.s
                    height: 30 * root.s
                    radius: 9 * root.s
                    color: muteInArea.containsMouse || Audio.srcMute ? Theme.veilHover : Theme.veil

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 14 * root.s
                        height: 14 * root.s
                        name: Audio.srcMute ? "x" : "mic"
                        color: Audio.srcMute ? Theme.danger : Theme.dim
                    }

                    MouseArea {
                        id: muteInArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.toggleSrcMute()
                    }
                }

                Text {
                    id: pctIn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34 * root.s
                    text: Math.round(Audio.srcVol * 100) + "%"
                    color: Audio.srcMute ? Theme.faint : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignRight
                }
            }

            Repeater {
                model: root.sources.slice(0, 3)

                delegate: Rectangle {
                    id: srcRow

                    required property var modelData

                    width: body.width
                    height: 30 * root.s
                    radius: Theme.radiusS * root.s
                    color: srcArea.containsMouse ? Theme.veilHover : "transparent"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.s
                        height: 9 * root.s
                        radius: width / 2
                        color: srcRow.modelData.id === root.srcId ? Theme.warn : "transparent"
                        border.width: 1
                        border.color: srcRow.modelData.id === root.srcId ? Theme.warn : Theme.faint
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 24 * root.s
                        anchors.right: parent.right
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.nodeLabel(srcRow.modelData)
                        color: srcRow.modelData.id === root.srcId ? Theme.text : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: srcArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.setDefaultSource(srcRow.modelData.id)
                    }
                }
            }
        }
    }

    SlimScroll {
        flick: mixFlick
        s: root.s
        anchors.right: mixFlick.right
        anchors.top: mixFlick.top
        anchors.bottom: mixFlick.bottom
    }
}
