pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Singletons"
import "../components"

/**
 * Календарь: часы с секундами, полная дата на русском, сетка месяца
 * с навигацией. Сегодняшний день выделен акцентом.
 */
PillSurface {
    id: root

    w: 312
    h: 404

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14 * root.s
        spacing: 12 * root.s

        // ── часы ──
        Item {
            width: parent.width
            height: 44 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm:ss")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 26 * root.s
                font.weight: Font.DemiBold
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: clock.date.toLocaleDateString(Qt.locale("ru_RU"), "dddd\nd MMMM yyyy")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        // ── заголовок месяца ──
        Item {
            width: parent.width
            height: 24 * root.s

            GlyphIcon {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-left"
                color: navArea1.containsMouse ? Theme.text : Theme.dim
                stroke: 2.2

                MouseArea {
                    id: navArea1
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: grid.prevMonth()
                }
            }

            Text {
                anchors.centerIn: parent
                text: grid.monthTitle
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
            }

            GlyphIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-right"
                color: navArea2.containsMouse ? Theme.text : Theme.dim
                stroke: 2.2

                MouseArea {
                    id: navArea2
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: grid.nextMonth()
                }
            }
        }

        // ── сетка ──
        GridLayout {
            id: grid
            width: parent.width

            columns: 7
            rowSpacing: 3 * root.s
            columnSpacing: 3 * root.s

            property date viewDate: new Date()
            property date today: new Date()

            readonly property var ruLocale: Qt.locale("ru_RU")
            readonly property var dayNames: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

            readonly property string monthTitle: {
                var s = ruLocale.toString(viewDate, "MMMM yyyy");
                return s.charAt(0).toUpperCase() + s.slice(1);
            }

            function daysInMonth(d) {
                return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
            }

            function firstWeekday(d) {
                var js = new Date(d.getFullYear(), d.getMonth(), 1).getDay();
                return (js + 6) % 7; // 0 = Пн
            }

            function prevMonth() {
                var d = new Date(viewDate);
                d.setDate(1);
                d.setMonth(d.getMonth() - 1);
                viewDate = d;
            }

            function nextMonth() {
                var d = new Date(viewDate);
                d.setDate(1);
                d.setMonth(d.getMonth() + 1);
                viewDate = d;
            }

            function isToday(day) {
                return day === today.getDate()
                    && viewDate.getMonth() === today.getMonth()
                    && viewDate.getFullYear() === today.getFullYear();
            }

            Repeater {
                model: grid.dayNames

                Text {
                    required property string modelData

                    Layout.preferredWidth: (grid.width - 6 * 3 * root.s) / 7
                    Layout.preferredHeight: 18 * root.s
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                }
            }

            Repeater {
                model: grid.firstWeekday(grid.viewDate)

                Item {
                    Layout.preferredWidth: (grid.width - 6 * 3 * root.s) / 7
                    Layout.preferredHeight: 30 * root.s
                }
            }

            Repeater {
                model: grid.daysInMonth(grid.viewDate)

                Item {
                    id: dayCell

                    required property int index

                    Layout.preferredWidth: (grid.width - 6 * 3 * root.s) / 7
                    Layout.preferredHeight: 30 * root.s

                    readonly property bool today: grid.isToday(index + 1)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26 * root.s
                        height: 26 * root.s
                        radius: width / 2
                        color: dayCell.today ? Theme.accent
                             : (dayArea.containsMouse ? Theme.veilHover : "transparent")
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: index + 1
                        color: dayCell.today ? "#111318" : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: dayCell.today ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: dayArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }
}
