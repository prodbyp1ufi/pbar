pragma ComponentBehavior: Bound

import QtQuick
import "../Singletons"
import "../components"

/**
 * Мониторинг ресурсов в карточках: процессор со спарклайном, память,
 * диск, сеть. Данные из Res (2-секундный опрос). Все значения якорные
 * («подпись слева / значение справа») — ничего не вылезает за пилюлю.
 */
PillSurface {
    id: root

    w: 380
    h: 440

    function fmtGB(bytes) {
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " ГБ";
    }

    function fmtRate(kbps) {
        return kbps >= 1024 ? (kbps / 1024).toFixed(1) + " МБ/с"
                            : Math.round(kbps) + " КБ/с";
    }

    function fmtMB(mb) {
        return mb >= 1024 ? (mb / 1024).toFixed(1) + " ГБ" : Math.round(mb) + " МБ";
    }

    function tempColor() {
        if (Res.temp <= 0) return Theme.faint;
        if (Res.temp < 70) return Theme.ok;
        if (Res.temp < 85) return Theme.warn;
        return Theme.danger;
    }

    // карточка метрики: стеклянная подложка + внутренние отступы
    component MetricCard: Rectangle {
        id: cardRoot

        default property alias content: cardCol.data
        property real s: 1

        radius: Theme.radiusM * cardRoot.s
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.cardTop }
            GradientStop { position: 1.0; color: Theme.cardBot }
        }
        border.width: 1
        border.color: Theme.border

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1 * cardRoot.s
            anchors.left: parent.left
            anchors.leftMargin: 10 * cardRoot.s
            anchors.right: parent.right
            anchors.rightMargin: 10 * cardRoot.s
            height: 1
            color: Theme.glassSheen
        }

        Column {
            id: cardCol
            anchors.fill: parent
            anchors.margins: 11 * cardRoot.s
            spacing: 8 * cardRoot.s
        }
    }

    // строка «подпись слева / значение справа»
    component KVRow: Item {
        id: kv

        property real s: 1
        property string label: ""
        property string value: ""
        property color valColor: Theme.dim
        property real valSize: 10.5
        property bool valBold: false

        width: parent.width
        height: Math.max(lab.implicitHeight, val.implicitHeight)

        Text {
            id: lab
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, kv.width * 0.55)
            text: kv.label
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * kv.s
            elide: Text.ElideRight
        }

        Text {
            id: val
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, kv.width * 0.72)
            text: kv.value
            color: kv.valColor
            font.family: Theme.font
            font.pixelSize: kv.valSize * kv.s
            font.weight: kv.valBold ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14 * root.s
        spacing: 10 * root.s

        // ── заголовок ──
        Item {
            width: parent.width
            height: 20 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Мониторинг"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fsTitle * root.s
                font.weight: Font.DemiBold
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Res.uptime.length ? Res.uptime : ""
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Theme.fsSmall * root.s
            }
        }

        // ── процессор ──
        MetricCard {
            width: parent.width
            height: 132 * root.s
            s: root.s

            Item {
                width: parent.width
                height: Math.max(cpuL.implicitHeight, cpuV.implicitHeight)

                Text {
                    id: cpuL
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Процессор"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                }

                Text {
                    id: cpuV
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(Res.cpu * 100) + "%"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 16 * root.s
                    font.weight: Font.DemiBold
                }
            }

            Canvas {
                id: spark
                width: parent.width
                height: 56 * root.s

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var w = width, h = height;
                    var hist = Res.cpuHist;

                    // сетка: базовая линия и линия 50%
                    ctx.strokeStyle = String(Theme.faint);
                    ctx.lineWidth = 1;
                    ctx.globalAlpha = 0.35;
                    ctx.beginPath();
                    ctx.moveTo(0, h - 0.5);
                    ctx.lineTo(w, h - 0.5);
                    ctx.moveTo(0, h / 2 + 0.5);
                    ctx.lineTo(w, h / 2 + 0.5);
                    ctx.stroke();
                    ctx.globalAlpha = 1;

                    if (hist.length < 2) return;

                    var step = w / 59;
                    ctx.strokeStyle = String(Theme.accent);
                    ctx.lineWidth = 1.8;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    var lastX = 0, lastY = 0;
                    for (var i = 0; i < hist.length; i++) {
                        var x = w - (hist.length - 1 - i) * step;
                        var y = h - 2 - hist[i] * (h - 6);
                        if (i === 0) ctx.moveTo(x, y);
                        else ctx.lineTo(x, y);
                        lastX = x; lastY = y;
                    }
                    ctx.stroke();

                    // заливка под линией
                    ctx.lineTo(w, h - 2);
                    ctx.lineTo(w - (hist.length - 1) * step, h - 2);
                    ctx.closePath();
                    ctx.fillStyle = String(Qt.alpha(Theme.accent, 0.14));
                    ctx.fill();

                    // точка текущего значения
                    ctx.beginPath();
                    ctx.arc(lastX, lastY, 2.2, 0, 2 * Math.PI);
                    ctx.fillStyle = String(Theme.accent);
                    ctx.fill();
                }

                Connections {
                    target: Res
                    function onCpuHistChanged() { spark.requestPaint(); }
                }
            }

            KVRow {
                s: root.s
                label: "Температура"
                value: Res.temp > 0 ? Res.temp.toFixed(1) + "°C" : "—"
                valColor: root.tempColor()
                valBold: true
            }
        }

        // ── память ──
        MetricCard {
            width: parent.width
            height: 76 * root.s
            s: root.s

            Item {
                width: parent.width
                height: Math.max(memL.implicitHeight, memV.implicitHeight)

                Text {
                    id: memL
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Память"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                }

                Text {
                    id: memV
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 110 * root.s)
                    text: root.fmtMB(Res.memUsed) + " / " + root.fmtMB(Res.memTotal)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    elide: Text.ElideRight
                }
            }

            Fader {
                width: parent.width
                s: root.s
                interactive: false
                value: Res.mem
            }
        }

        // ── диск ──
        MetricCard {
            width: parent.width
            height: 76 * root.s
            s: root.s

            Item {
                width: parent.width
                height: Math.max(dskL.implicitHeight, dskV.implicitHeight)

                Text {
                    id: dskL
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Диск /"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                }

                Text {
                    id: dskV
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 110 * root.s)
                    text: root.fmtGB(Res.diskUsed) + " / " + root.fmtGB(Res.diskTotal)
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    elide: Text.ElideRight
                }
            }

            Fader {
                width: parent.width
                s: root.s
                interactive: false
                value: Res.diskTotal > 0 ? Res.diskUsed / Res.diskTotal : 0
                fillColor: Theme.warn
            }
        }

        // ── сеть ──
        MetricCard {
            width: parent.width
            height: 44 * root.s
            s: root.s

            Item {
                width: parent.width
                height: Math.max(netL.implicitHeight, netR.implicitHeight)

                Text {
                    id: netL
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Сеть"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                }

                Row {
                    id: netR
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↓ " + root.fmtRate(Res.netDown)
                        color: Theme.ok
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↑ " + root.fmtRate(Res.netUp)
                        color: Theme.warn
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                    }
                }
            }
        }

        // ── нагрузка ──
        KVRow {
            s: root.s
            label: "Нагрузка"
            value: Res.loadavg
        }
    }
}
