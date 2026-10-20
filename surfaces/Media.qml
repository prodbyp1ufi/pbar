pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Медиа: обложка, титулы, прогресс с перемоткой, play/pause/prev/next
 * и переключение источников при нескольких плеерах.
 */
PillSurface {
    id: root

    w: 600
    h: 316

    readonly property var p: Players.active
    readonly property bool has: Players.has

    readonly property real posSec: has && p.positionSupported ? p.position : 0
    property real dragFrac: -1

    // MPRIS не пушит позицию сама — подтягиваем раз в секунду
    Timer {
        interval: 1000
        running: root.open && root.has && root.p && root.p.isPlaying
        repeat: true
        onTriggered: if (root.p) root.p.positionChanged()
    }

    function fmt(sec) {
        sec = Math.max(0, Math.floor(sec));
        var m = Math.floor(sec / 60);
        var s = sec % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Row {
        anchors.fill: parent
        anchors.margins: 20 * root.s
        spacing: 18 * root.s

        // ── обложка ──
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 140 * root.s
            height: 140 * root.s
            radius: Theme.radiusM * root.s
            color: Theme.veil
            border.width: 1
            border.color: Theme.glassBorder
            clip: true

            Image {
                anchors.fill: parent
                visible: root.artOk
                source: root.has ? Players.artUrl : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
            }

            GlyphIcon {
                anchors.centerIn: parent
                visible: !root.artOk
                width: 46 * root.s
                height: 46 * root.s
                name: "note"
                color: Theme.faint
                stroke: 2
            }
        }

        // ── инфо и управление ──
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 158 * root.s
            spacing: 9 * root.s

            Text {
                width: parent.width
                text: root.has ? Players.source : ""
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
                font.letterSpacing: 1
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.has ? Players.title : "Ничего не играет"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 17 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.has ? Players.artist : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                elide: Text.ElideRight
            }

            // ── прогресс ──
            Fader {
                width: parent.width
                s: root.s
                interactive: root.has && root.p && root.p.canSeek && root.p.positionSupported
                             && Players.lengthSec > 0 && !Players.live
                value: Players.lengthSec > 0 && !Players.live
                       ? (root.dragFrac >= 0 ? root.dragFrac : root.posSec / Players.lengthSec)
                       : 0
                onMoved: (v) => { root.dragFrac = v }
                onCommitted: (v) => {
                    if (root.has && root.p && Players.lengthSec > 0) {
                        var target = Math.max(0, Math.min(Players.lengthSec - 0.5, v * Players.lengthSec));
                        if (typeof root.p.setPosition === "function") root.p.setPosition(target);
                        else if (typeof root.p.seek === "function") root.p.seek(target - root.posSec);
                    }
                    root.dragFrac = -1
                }
                fillColor: Theme.accent
            }

            Item {
                width: parent.width
                height: 17 * root.s

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fmt(root.dragFrac >= 0 ? root.dragFrac * Players.lengthSec : root.posSec)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Players.live ? "LIVE" : root.fmt(Players.lengthSec)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                }
            }

            // ── управление ──
            Row {
                id: ctrlRow
                width: parent.width
                spacing: 8 * root.s

                Rectangle {
                    id: prevBtn
                    width: 44 * root.s
                    height: 44 * root.s
                    radius: 13 * root.s
                    color: prevArea.containsMouse && root.canPrev ? Theme.veilHover : Theme.veil
                    opacity: root.canPrev ? 1 : 0.35

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 19 * root.s
                        height: 19 * root.s
                        name: "prev"
                        color: Theme.text
                    }

                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.canPrev
                        onClicked: { if (root.p) root.p.previous(); root.dragFrac = -1 }
                    }
                }

                Rectangle {
                    id: playBtn
                    width: 54 * root.s
                    height: 54 * root.s
                    radius: 16 * root.s
                    color: root.has && root.p && root.p.isPlaying ? Theme.accentDim : Theme.accent

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 24 * root.s
                        height: 24 * root.s
                        name: root.has && root.p && root.p.isPlaying ? "pause" : "play"
                        color: "#111318"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.canToggle
                        onClicked: { if (root.p) root.p.togglePlaying(); root.dragFrac = -1 }
                    }
                }

                Rectangle {
                    id: nextBtn
                    width: 44 * root.s
                    height: 44 * root.s
                    radius: 13 * root.s
                    color: nextArea.containsMouse && root.canNext ? Theme.veilHover : Theme.veil
                    opacity: root.canNext ? 1 : 0.35

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 19 * root.s
                        height: 19 * root.s
                        name: "next"
                        color: Theme.text
                    }

                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.canNext
                        onClicked: { if (root.p) root.p.next(); root.dragFrac = -1 }
                    }
                }

                Rectangle {
                    id: shuffleBtn
                    width: 40 * root.s
                    height: 40 * root.s
                    radius: 13 * root.s
                    color: shufArea.containsMouse ? Theme.veilHover : Theme.veil
                    opacity: root.canShuffle ? 1 : 0.35

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 17 * root.s
                        height: 17 * root.s
                        name: "shuffle"
                        color: root.shuffling ? Theme.accent : (shufArea.containsMouse ? Theme.text : Theme.dim)
                    }

                    MouseArea {
                        id: shufArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.canShuffle
                        onClicked: { if (root.p) root.p.shuffle = !root.p.shuffle }
                    }
                }

                Rectangle {
                    id: repeatBtn
                    width: 40 * root.s
                    height: 40 * root.s
                    radius: 13 * root.s
                    color: repArea.containsMouse ? Theme.veilHover : Theme.veil
                    opacity: root.canLoop ? 1 : 0.35

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 17 * root.s
                        height: 17 * root.s
                        name: "repeat"
                        color: root.loopMode > 0 ? Theme.accent : (repArea.containsMouse ? Theme.text : Theme.dim)
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 5 * root.s
                        anchors.bottomMargin: 3 * root.s
                        visible: root.loopMode === 1
                        text: "1"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 8 * root.s
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: repArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.canLoop
                        onClicked: { if (root.p) root.p.loopState = (root.loopMode + 1) % 3 }
                    }
                }

                Item { height: 1; width: Math.max(0, ctrlRow.width - 254 * root.s - chipsRow.width) }

                // переключение источников
                Row {
                    id: chipsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * root.s

                    Repeater {
                        model: Players.list.length > 1 ? Players.list : []

                        delegate: Rectangle {
                            id: srcChip

                            required property var modelData

                            width: Math.min(70 * root.s, srcText.implicitWidth + 16 * root.s)
                            height: 24 * root.s
                            radius: height / 2
                            color: srcArea.containsMouse || srcChip.modelData === root.p ? Theme.veilHover : Theme.veil
                            border.width: 1
                            border.color: srcChip.modelData === root.p ? Theme.accentDim : "transparent"

                            Text {
                                id: srcText
                                anchors.centerIn: parent
                                text: Players.labelOf(srcChip.modelData).substring(0, 10)
                                color: srcChip.modelData === root.p ? Theme.text : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                            }

                            MouseArea {
                                id: srcArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Players.select(srcChip.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property bool artOk: has && Players.artUrl.length > 0
    readonly property bool canPrev: has && p && p.canGoPrevious
    readonly property bool canNext: has && p && p.canGoNext
    readonly property bool canToggle: has && p && p.canTogglePlaying
    readonly property bool canShuffle: has && p && p.shuffleSupported === true
    readonly property bool shuffling: has && p && p.shuffle === true
    readonly property bool canLoop: has && p && p.loopSupported === true
    readonly property int loopMode: has && p && p.loopState !== undefined ? p.loopState : 0

    onOpenChanged: if (!open) dragFrac = -1
}
