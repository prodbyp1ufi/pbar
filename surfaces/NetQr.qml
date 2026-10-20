pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * «Поделиться сетью»: пилюля отрастает в карточку с QR-кодом Wi-Fi.
 * Открывается кнопкой share в меню Wi-Fi; клик/Esc — закрыть.
 */
PillSurface {
    id: root

    w: 246
    h: 254

    // пароль мог не дойти (нет сохранённых секретов) — молча показываем QR без него
    readonly property string ssid: Net._qrSsid
    readonly property bool ready: Net.qrFile.length > 0

    Item {
        anchors.fill: parent
        anchors.margins: 16 * root.s

        // шапка: иконка + имя сети
        Row {
            id: head

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8 * root.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * root.s
                height: 14 * root.s
                name: "wifi"
                level: 1
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 170 * root.s
                text: root.ssid
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        // QR + пароль — центр в зоне под шапкой, без наложения
        Item {
            anchors.top: head.bottom
            anchors.topMargin: 10 * root.s
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: 166 * root.s

            Column {
                anchors.centerIn: parent
                spacing: 10 * root.s

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 166 * root.s
                    height: 166 * root.s
                    visible: root.ready
                    source: Net.qrFile
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    asynchronous: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !root.ready
                    text: "Генерация QR…"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11.5 * root.s
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Net.wifiPw.length > 0
                    text: Net.wifiPw
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    elide: Text.ElideRight
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.requestClose()
    }
}
