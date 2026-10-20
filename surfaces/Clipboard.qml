pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Спотлайт истории буфера (cliphist): поиск по текстовым записям,
 * Enter/клик — вернуть в буфер, Backspace при пустой строке поиска —
 * удалить выбранную запись, Delete — очистить историю целиком.
 * Картинки показываются только когда поиск пуст.
 */
PillSurface {
    id: root

    w: 600
    readonly property int rowH: 44
    readonly property int maxVisible: 9
    // геометрия как у лаунчера; высота всегда на максимум — не меняется ни при поиске, ни от числа записей
    h: 55 + 12 + maxVisible * (rowH + 2) + 12

    scale: open ? 1 : 0.96
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    property string query: ""

    function reset() {
        query = "";
        input.clear();
        list.currentIndex = 0;
        Clip.refresh();
        input.forceActiveFocus();
    }
    onOpenChanged: if (open) reset()
    Component.onCompleted: if (open) reset()

    readonly property string q: query.trim().toLowerCase()

    // при непустом запросе ищем подстроку в текстовых записях
    readonly property var rows: {
        if (q.length === 0) return Clip.entries;
        var out = [];
        var src = Clip.entries;
        for (var i = 0; i < src.length; i++) {
            var e = src[i];
            if (e.image) continue;
            if (String(e.preview).toLowerCase().indexOf(q) >= 0) out.push(e);
        }
        return out;
    }

    function typeLabel(t) {
        if (t.indexOf("image/png") === 0) return "PNG";
        if (t.indexOf("image/jpeg") === 0) return "JPEG";
        if (t.indexOf("image/") === 0) return t.substring(6);
        return "";
    }

    function pick(entry) {
        if (!entry) return;
        Clip.copyBack(entry);
        UIState.close();
    }

    function removeAt(i) {
        var e = root.rows[i];
        if (e) Clip.remove(e.id);
    }

    SpotCard {
        anchors.fill: parent
        s: root.s
    }

    Column {
        anchors.fill: parent

        // ── строка поиска ──
        Item {
            width: parent.width
            height: 54 * root.s

            Row {
                anchors.fill: parent
                anchors.leftMargin: 20 * root.s
                anchors.rightMargin: 20 * root.s
                spacing: 12 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17 * root.s
                    height: 17 * root.s
                    name: "search"
                    color: input.activeFocus ? Theme.accent : Theme.dim
                    stroke: 2.2
                }

                TextInput {
                    id: input
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30 * root.s
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14 * root.s
                    clip: true
                    cursorVisible: activeFocus
                    selectionColor: Theme.accentDim
                    verticalAlignment: TextInput.AlignVCenter

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text.length === 0
                        text: "Поиск по истории буфера…"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 14 * root.s
                    }

                    onTextChanged: {
                        root.query = text;
                        list.currentIndex = 0;
                    }
                    onAccepted: root.pick(root.rows[list.currentIndex])
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onPressed: (event) => {
                        // у Keys нет onBackspacePressed — ловим общий onPressed;
                        // при пустом поиске Backspace удаляет выбранную запись,
                        // иначе не вмешиваемся — обычное редактирование строки
                        if (event.key !== Qt.Key_Backspace) return;
                        if (root.query.length === 0 && root.rows.length > 0) {
                            root.removeAt(list.currentIndex);
                            event.accepted = true;
                        }
                    }
                    Keys.onDeletePressed: {
                        if (root.query.length === 0 && Clip.entries.length > 0) {
                            Clip.wipe();
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        // ── список ──
        Item {
            width: parent.width
            height: parent.height - 55 * root.s

            ListView {
                id: list
                anchors.fill: parent
                anchors.topMargin: 6 * root.s
                anchors.bottomMargin: 6 * root.s
                clip: true
                spacing: 2 * root.s
                model: root.rows
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: 0
                onCountChanged: currentIndex = Math.max(0, Math.min(currentIndex < 0 ? 0 : currentIndex, count - 1))

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: 44 * root.s

                readonly property bool isActive: list.currentIndex === index

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusS * root.s
                    color: rowArea.containsMouse || row.isActive ? Theme.veilHover : "transparent"
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3 * root.s
                    height: parent.height * 0.5
                    radius: width / 2
                    color: Theme.accent
                    opacity: row.isActive ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                // превью картинки (путь появляется асинхронно после декода)
                Rectangle {
                    id: thumb
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32 * root.s
                    height: 32 * root.s
                    radius: 8 * root.s
                    color: Theme.veil
                    clip: true

                    Image {
                        anchors.fill: parent
                        visible: row.modelData.image
                                 && Clip.previews[row.modelData.id] !== undefined
                        source: row.modelData.image
                                ? (Clip.previews[row.modelData.id] || "") : ""
                        sourceSize.width: 80
                        sourceSize.height: 80
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                    }

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 15 * root.s
                        height: 15 * root.s
                        name: row.modelData.image ? "image" : "clipboard"
                        color: Theme.faint
                        visible: row.modelData.image
                                 ? Clip.previews[row.modelData.id] === undefined : true
                    }
                }

                Text {
                    anchors.left: thumb.right
                    anchors.leftMargin: 11 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (row.modelData.image ? 200 : 130) * root.s
                    text: row.modelData.image
                          ? "Изображение" + (dims.length ? "   " + dims : "")
                          : (String(row.modelData.preview).split("\n")[0] || "(пусто)")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12.5 * root.s
                    elide: Text.ElideRight
                    maximumLineCount: 1

                    readonly property string dims: {
                        var m = String(row.modelData.preview).match(/(\d+)x(\d+)/);
                        return m ? m[1] + "×" + m[2] : "";
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80 * root.s
                    visible: row.modelData.image
                    text: root.typeLabel(row.modelData.type)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    horizontalAlignment: Text.AlignRight
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pick(row.modelData)
                    onContainsMouseChanged: if (containsMouse) list.currentIndex = row.index
                }
            }

            }

            SlimScroll {
                flick: list
                s: root.s
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }

            EmptyState {
                anchors.centerIn: parent
                visible: root.rows.length === 0
                s: root.s
                icon: root.q.length ? "search" : "clipboard"
                title: root.q.length ? "Ничего не найдено" : "История пуста"
                hint: root.q.length ? "попробуй другой запрос" : "скопируй что-нибудь"
            }
        }
    }
}
