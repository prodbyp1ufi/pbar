import QtQuick

/**
 * Векторные иконки на Canvas — рисуются в координатной сетке 24x24 и
 * масштабируются под размер элемента. Никаких зависимостей от иконочных
 * шрифтов: свой цвет, свой уровень сигнала/громкости, заливка батареи.
 *
 * Canvas рендерит текстуру в логических пикселях, поэтому при дробном
 * масштабе (scale 1.33) линии растягиваются и «мылятся». Обходим через
 * суперсэмплинг: внутренний холст 2x, ужатый scale 0.5 — чёткие края.
 */
Item {
    id: root

    property string name: ""
    property color color: "#eceff4"
    property real fill: -1      // 0..1 — заливка батареи
    property real level: -1     // 0..1 — уровни wifi/громкости; <0 — выкл
    property bool bolt: false   // молния на батарее (зарядка)
    property real stroke: 1.8

    width: 18
    height: 18

    onNameChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()
    onFillChanged: cv.requestPaint()
    onLevelChanged: cv.requestPaint()
    onBoltChanged: cv.requestPaint()
    onVisibleChanged: if (visible) cv.requestPaint()

    function muteX() {
        return root.level < 0 || (root.name === "volume" && root.level <= 0.001);
    }

    function roundRect(ctx, x, y, w, h, r) {
        ctx.beginPath();
        ctx.moveTo(x + r, y);
        ctx.lineTo(x + w - r, y);
        ctx.quadraticCurveTo(x + w, y, x + w, y + r);
        ctx.lineTo(x + w, y + h - r);
        ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
        ctx.lineTo(x + r, y + h);
        ctx.quadraticCurveTo(x, y + h, x, y + h - r);
        ctx.lineTo(x, y + r);
        ctx.quadraticCurveTo(x, y + r, x, y);
        ctx.closePath();
    }

    Canvas {
        id: cv
        anchors.centerIn: parent
        width: root.width * 2
        height: root.height * 2
        scale: 0.5
        antialiasing: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.scale(width / 24, height / 24);
        ctx.strokeStyle = String(root.color);
        ctx.fillStyle = String(root.color);
        ctx.lineWidth = root.stroke;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        var D = Math.PI / 180;

        switch (root.name) {
        case "grid":
            ctx.beginPath();
            ctx.arc(7, 7, 2.7, 0, 2 * Math.PI);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(17, 7, 2.7, 0, 2 * Math.PI);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(7, 17, 2.7, 0, 2 * Math.PI);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(17, 17, 2.7, 0, 2 * Math.PI);
            ctx.fill();
            break;

        case "wifi": {
            var arcs = root.level < 0 ? 1
                     : (root.level > 0.72 ? 4 : (root.level > 0.45 ? 3 : (root.level > 0.22 ? 2 : 1)));
            ctx.beginPath();
            ctx.arc(12, 19.5, 1.7, 0, 2 * Math.PI);
            ctx.fill();
            var radii = [4.8, 8.1, 11.4, 14.7];
            for (var i = 0; i < arcs; i++) {
                ctx.beginPath();
                ctx.arc(12, 19.5, radii[i], -135 * D, -45 * D);
                ctx.stroke();
            }
            if (root.level < 0) {
                ctx.beginPath();
                ctx.moveTo(16, 12);
                ctx.lineTo(21, 17);
                ctx.moveTo(21, 12);
                ctx.lineTo(16, 17);
                ctx.stroke();
            }
            break;
        }

        case "ether":
            ctx.beginPath();
            ctx.moveTo(7, 12);
            ctx.lineTo(7, 8);
            ctx.moveTo(12, 12);
            ctx.lineTo(12, 8);
            ctx.moveTo(17, 12);
            ctx.lineTo(17, 8);
            ctx.stroke();
            roundRect(ctx, 4, 12, 16, 7, 2);
            ctx.stroke();
            break;

        case "volume": {
            ctx.beginPath();
            ctx.moveTo(4, 10);
            ctx.lineTo(8.5, 10);
            ctx.lineTo(14, 5);
            ctx.lineTo(14, 19);
            ctx.lineTo(8.5, 14);
            ctx.lineTo(4, 14);
            ctx.closePath();
            ctx.stroke();
            if (root.muteX()) {
                ctx.beginPath();
                ctx.moveTo(16.5, 9.5);
                ctx.lineTo(21, 14.5);
                ctx.moveTo(21, 9.5);
                ctx.lineTo(16.5, 14.5);
                ctx.stroke();
            } else {
                ctx.beginPath();
                ctx.arc(14.5, 12, 4.5, -55 * D, 55 * D);
                ctx.stroke();
                if (root.level > 0.55) {
                    ctx.beginPath();
                    ctx.arc(14.5, 12, 7.5, -55 * D, 55 * D);
                    ctx.stroke();
                }
            }
            break;
        }

        case "battery": {
            roundRect(ctx, 3, 8, 17, 9, 2);
            ctx.stroke();
            ctx.beginPath();
            roundRect(ctx, 21, 10.6, 2.2, 3.8, 1);
            ctx.fill();
            if (root.fill > 0.02) {
                ctx.save();
                var w = Math.min(14, Math.max(2.2, 14 * root.fill));
                ctx.beginPath();
                roundRect(ctx, 4, 9, w, 7, 1.4);
                ctx.fill();
                ctx.restore();
            }
            if (root.bolt) {
                ctx.beginPath();
                ctx.moveTo(13, 9.2);
                ctx.lineTo(10.2, 13.2);
                ctx.lineTo(12.2, 13.2);
                ctx.lineTo(10.8, 15.8);
                ctx.stroke();
            }
            break;
        }

        case "bell":
            ctx.beginPath();
            ctx.arc(12, 10.5, 6.5, Math.PI, 0);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(5.5, 10.5);
            ctx.lineTo(5.5, 16.5);
            ctx.moveTo(18.5, 10.5);
            ctx.lineTo(18.5, 16.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(4, 16.5);
            ctx.lineTo(20, 16.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(12, 16.5, 2.2, 0, Math.PI);
            ctx.stroke();
            break;

        case "bell-off":
            // колокол без язычка + диагональное перечёркивание
            ctx.beginPath();
            ctx.arc(12, 10.5, 6.5, Math.PI, 0);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(5.5, 10.5);
            ctx.lineTo(5.5, 16.5);
            ctx.moveTo(18.5, 10.5);
            ctx.lineTo(18.5, 16.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(4, 16.5);
            ctx.lineTo(20, 16.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(4.5, 4);
            ctx.lineTo(19.5, 20);
            ctx.stroke();
            break;

        case "x":
            ctx.beginPath();
            ctx.moveTo(7, 7);
            ctx.lineTo(17, 17);
            ctx.moveTo(17, 7);
            ctx.lineTo(7, 17);
            ctx.stroke();
            break;

        case "share":
            // коробка с разрывом сверху + стрелка вверх (iOS-style поделиться)
            ctx.beginPath();
            ctx.moveTo(8, 10.5);
            ctx.lineTo(6, 10.5);
            ctx.lineTo(6, 20);
            ctx.lineTo(18, 20);
            ctx.lineTo(18, 10.5);
            ctx.lineTo(16, 10.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(12, 4);
            ctx.lineTo(12, 14);
            ctx.moveTo(8.5, 7.5);
            ctx.lineTo(12, 4);
            ctx.lineTo(15.5, 7.5);
            ctx.stroke();
            break;

        case "chevron-left":
            ctx.beginPath();
            ctx.moveTo(14.5, 6);
            ctx.lineTo(8.5, 12);
            ctx.lineTo(14.5, 18);
            ctx.stroke();
            break;

        case "chevron-right":
            ctx.beginPath();
            ctx.moveTo(9.5, 6);
            ctx.lineTo(15.5, 12);
            ctx.lineTo(9.5, 18);
            ctx.stroke();
            break;

        case "search":
            ctx.beginPath();
            ctx.arc(10.5, 10.5, 5.5, 0, 2 * Math.PI);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(14.8, 14.8);
            ctx.lineTo(19.5, 19.5);
            ctx.stroke();
            break;

        case "power":
            ctx.beginPath();
            ctx.arc(12, 13, 7.5, -55 * D, 235 * D);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(12, 3.5);
            ctx.lineTo(12, 11);
            ctx.stroke();
            break;

        case "lock":
            ctx.beginPath();
            ctx.arc(12, 11, 4.5, Math.PI, 0);
            ctx.stroke();
            roundRect(ctx, 6, 11, 12, 9, 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(12, 15.5, 1.4, 0, 2 * Math.PI);
            ctx.fill();
            break;

        case "logout":
            ctx.beginPath();
            ctx.moveTo(9, 4);
            ctx.lineTo(4, 4);
            ctx.lineTo(4, 20);
            ctx.lineTo(9, 20);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(10, 12);
            ctx.lineTo(19.5, 12);
            ctx.moveTo(15.5, 8);
            ctx.lineTo(19.5, 12);
            ctx.lineTo(15.5, 16);
            ctx.stroke();
            break;

        case "moon":
            // полумесяц контуром, в стиле остальных линейных иконок:
            // внешняя дуга слева + внутренняя дуга от рога к рогу
            ctx.beginPath();
            ctx.arc(12, 12, 7.8, 50 * D, 310 * D, false);
            ctx.arc(21, 12, 7.2, 236.3 * D, 123.7 * D, true);
            ctx.closePath();
            ctx.stroke();
            break;

        case "reboot":
            // дуга почти полный круг с разрывом справа-сверху,
            // наконечник стрелки сидит на конце дуги
            ctx.beginPath();
            ctx.arc(12, 12, 7.5, 320 * D, 285 * D, false);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(10.79, 5.32);
            ctx.lineTo(13.94, 4.76);
            ctx.lineTo(11.49, 2.70);
            ctx.stroke();
            break;

        case "play":
            ctx.beginPath();
            ctx.moveTo(9, 6.5);
            ctx.lineTo(17.5, 12);
            ctx.lineTo(9, 17.5);
            ctx.closePath();
            ctx.fill();
            break;

        case "pause":
            roundRect(ctx, 8, 6.5, 3, 11, 1.2);
            ctx.fill();
            roundRect(ctx, 13, 6.5, 3, 11, 1.2);
            ctx.fill();
            break;

        case "next":
            ctx.beginPath();
            ctx.moveTo(7.5, 6.5);
            ctx.lineTo(15, 12);
            ctx.lineTo(7.5, 17.5);
            ctx.closePath();
            ctx.fill();
            roundRect(ctx, 15.5, 6.5, 2.4, 11, 1);
            ctx.fill();
            break;

        case "prev":
            ctx.beginPath();
            ctx.moveTo(16.5, 6.5);
            ctx.lineTo(9, 12);
            ctx.lineTo(16.5, 17.5);
            ctx.closePath();
            ctx.fill();
            roundRect(ctx, 6.1, 6.5, 2.4, 11, 1);
            ctx.fill();
            break;

        case "mic":
            roundRect(ctx, 9.5, 3.5, 5, 10, 2.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(12, 15, 4.5, 0, Math.PI);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(12, 19.5);
            ctx.lineTo(12, 22);
            ctx.stroke();
            break;

        case "check":
            ctx.beginPath();
            ctx.moveTo(5, 12.5);
            ctx.lineTo(10, 17.5);
            ctx.lineTo(19, 7);
            ctx.stroke();
            break;

        case "note":
            ctx.beginPath();
            ctx.arc(9, 17, 3, 0, 2 * Math.PI);
            ctx.fill();
            ctx.beginPath();
            ctx.moveTo(12, 17);
            ctx.lineTo(12, 5);
            ctx.lineTo(17.5, 7);
            ctx.stroke();
            break;

        case "trash":
            ctx.beginPath();
            ctx.moveTo(5, 7);
            ctx.lineTo(19, 7);
            ctx.moveTo(9.5, 7);
            ctx.lineTo(9.5, 4.5);
            ctx.lineTo(14.5, 4.5);
            ctx.lineTo(14.5, 7);
            ctx.stroke();
            roundRect(ctx, 6.5, 7, 11, 12.5, 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(10, 10.5);
            ctx.lineTo(10, 16);
            ctx.moveTo(14, 10.5);
            ctx.lineTo(14, 16);
            ctx.stroke();
            break;

        case "eye":
            ctx.beginPath();
            ctx.moveTo(2.5, 12);
            ctx.bezierCurveTo(5.5, 6.8, 9, 5, 12, 5);
            ctx.bezierCurveTo(15, 5, 18.5, 6.8, 21.5, 12);
            ctx.bezierCurveTo(18.5, 17.2, 15, 19, 12, 19);
            ctx.bezierCurveTo(9, 19, 5.5, 17.2, 2.5, 12);
            ctx.closePath();
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(12, 12, 3.2, 0, 2 * Math.PI);
            ctx.stroke();
            break;

        case "eyeOff":
            ctx.beginPath();
            ctx.moveTo(2.5, 12);
            ctx.bezierCurveTo(5.5, 6.8, 9, 5, 12, 5);
            ctx.bezierCurveTo(15, 5, 18.5, 6.8, 21.5, 12);
            ctx.bezierCurveTo(20, 14.6, 18.1, 16.4, 16, 17.5);
            ctx.moveTo(12.6, 18.9);
            ctx.bezierCurveTo(9.3, 18.9, 5.4, 17.1, 2.5, 12);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(12, 12, 3.2, 0, 2 * Math.PI);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(4, 20);
            ctx.lineTo(20, 4);
            ctx.stroke();
            break;

        case "bt":
            // классический глиф bluetooth одной непрерывной линией
            ctx.beginPath();
            ctx.moveTo(6.5, 7);
            ctx.lineTo(17.5, 17);
            ctx.lineTo(12, 22);
            ctx.lineTo(12, 2);
            ctx.lineTo(17.5, 7);
            ctx.lineTo(6.5, 17);
            ctx.stroke();
            break;

        case "camera":
            roundRect(ctx, 3, 7, 18, 13, 2.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(8, 7);
            ctx.lineTo(9.5, 4.5);
            ctx.lineTo(14.5, 4.5);
            ctx.lineTo(16, 7);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(12, 13.5, 3.6, 0, 2 * Math.PI);
            ctx.stroke();
            break;

        case "image":
            roundRect(ctx, 3, 4.5, 18, 15, 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(8.5, 9.5, 1.7, 0, 2 * Math.PI);
            ctx.fill();
            ctx.beginPath();
            ctx.moveTo(5.5, 17.5);
            ctx.lineTo(10, 12);
            ctx.lineTo(13, 15.5);
            ctx.lineTo(15.5, 13);
            ctx.lineTo(18.5, 17.5);
            ctx.stroke();
            break;

        case "activity":
            ctx.beginPath();
            ctx.moveTo(3, 12);
            ctx.lineTo(7.5, 12);
            ctx.lineTo(9.5, 7.5);
            ctx.lineTo(12.5, 16.5);
            ctx.lineTo(14.5, 12);
            ctx.lineTo(21, 12);
            ctx.stroke();
            break;

        case "clipboard":
            roundRect(ctx, 6, 4.8, 12, 15.4, 2);
            ctx.stroke();
            roundRect(ctx, 9.3, 3.2, 5.4, 3.2, 1.4);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(9, 11.5);
            ctx.lineTo(15, 11.5);
            ctx.moveTo(9, 14.7);
            ctx.lineTo(15, 14.7);
            ctx.stroke();
            break;

        case "folder":
            ctx.beginPath();
            ctx.moveTo(3.5, 18.5);
            ctx.lineTo(3.5, 4.5);
            ctx.lineTo(9.5, 4.5);
            ctx.lineTo(11.5, 6.8);
            ctx.lineTo(20.5, 6.8);
            ctx.lineTo(20.5, 18.5);
            ctx.closePath();
            ctx.stroke();
            break;

        case "window":
            roundRect(ctx, 3, 5, 18, 14, 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(3, 9.2);
            ctx.lineTo(21, 9.2);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(5.6, 7.1, 0.9, 0, 2 * Math.PI);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(8.4, 7.1, 0.9, 0, 2 * Math.PI);
            ctx.fill();
            break;

        case "globe":
            // глобус: круг, меридиан и экватор
            ctx.beginPath();
            ctx.arc(12, 12, 8.2, 0, 2 * Math.PI);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(12, 3.8);
            ctx.bezierCurveTo(8.4, 6.2, 8.4, 17.8, 12, 20.2);
            ctx.bezierCurveTo(15.6, 17.8, 15.6, 6.2, 12, 3.8);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(3.8, 12);
            ctx.lineTo(20.2, 12);
            ctx.stroke();
            break;

        case "terminal":
            // окно терминала: шеврон и курсор
            roundRect(ctx, 3, 5, 18, 14, 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(6.8, 9.2);
            ctx.lineTo(10.4, 12);
            ctx.lineTo(6.8, 14.8);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(12.4, 15);
            ctx.lineTo(17.2, 15);
            ctx.stroke();
            break;

        case "cpu":
            // чип: корпус, ядро и ножки по четырём сторонам
            roundRect(ctx, 6, 6, 12, 12, 2);
            ctx.stroke();
            roundRect(ctx, 9.7, 9.7, 4.6, 4.6, 1);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(9, 6);  ctx.lineTo(9, 3);
            ctx.moveTo(15, 6); ctx.lineTo(15, 3);
            ctx.moveTo(9, 18);  ctx.lineTo(9, 21);
            ctx.moveTo(15, 18); ctx.lineTo(15, 21);
            ctx.moveTo(6, 9);  ctx.lineTo(3, 9);
            ctx.moveTo(6, 15); ctx.lineTo(3, 15);
            ctx.moveTo(18, 9);  ctx.lineTo(21, 9);
            ctx.moveTo(18, 15); ctx.lineTo(21, 15);
            ctx.stroke();
            break;

        case "ram":
            // планка памяти: чипы в ряд и контакты снизу
            roundRect(ctx, 3, 7.5, 18, 9, 1.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(7.5, 9.5);  ctx.lineTo(7.5, 14.5);
            ctx.moveTo(12, 9.5);   ctx.lineTo(12, 14.5);
            ctx.moveTo(16.5, 9.5); ctx.lineTo(16.5, 14.5);
            ctx.moveTo(6, 16.5);  ctx.lineTo(6, 18.5);
            ctx.moveTo(10, 16.5); ctx.lineTo(10, 18.5);
            ctx.moveTo(14, 16.5); ctx.lineTo(14, 18.5);
            ctx.moveTo(18, 16.5); ctx.lineTo(18, 18.5);
            ctx.stroke();
            break;

        case "drive":
            // накопитель: линия данных и индикатор в корпусе
            roundRect(ctx, 3, 8, 18, 9, 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(6, 12.5);
            ctx.lineTo(11.5, 12.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(16.5, 12.5, 1.4, 0, 2 * Math.PI);
            ctx.fill();
            break;

        case "monitor":
            roundRect(ctx, 3, 4.5, 18, 12.5, 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(12, 17);
            ctx.lineTo(12, 20);
            ctx.moveTo(8.5, 20);
            ctx.lineTo(15.5, 20);
            ctx.stroke();
            break;

        case "crop":
            ctx.beginPath();
            ctx.moveTo(7, 3.5);
            ctx.lineTo(7, 17);
            ctx.lineTo(20.5, 17);
            ctx.moveTo(3.5, 7);
            ctx.lineTo(17, 7);
            ctx.lineTo(17, 20.5);
            ctx.stroke();
            break;

        case "stop":
            roundRect(ctx, 8, 8, 8.5, 8.5, 1.5);
            ctx.fill();
            break;

        case "shuffle":
            ctx.beginPath();
            ctx.moveTo(3, 7); ctx.lineTo(7, 7);
            ctx.bezierCurveTo(12, 7, 12, 17, 17, 17); ctx.lineTo(20, 17);
            ctx.moveTo(3, 17); ctx.lineTo(7, 17);
            ctx.bezierCurveTo(10.2, 17, 11.2, 13.4, 12.6, 10.6);
            ctx.moveTo(12.6, 10.6);
            ctx.bezierCurveTo(14, 7.9, 15, 7, 17, 7); ctx.lineTo(20, 7);
            ctx.moveTo(17.8, 4.8); ctx.lineTo(20, 7); ctx.lineTo(17.8, 9.2);
            ctx.moveTo(17.8, 14.8); ctx.lineTo(20, 17); ctx.lineTo(17.8, 19.2);
            ctx.stroke();
            break;

        case "repeat":
            ctx.beginPath();
            ctx.moveTo(17, 2); ctx.lineTo(21, 6); ctx.lineTo(17, 10);
            ctx.moveTo(3, 11); ctx.lineTo(3, 10);
            ctx.arc(7, 10, 4, Math.PI, 1.5 * Math.PI);
            ctx.lineTo(21, 6);
            ctx.moveTo(7, 22); ctx.lineTo(3, 18); ctx.lineTo(7, 14);
            ctx.moveTo(21, 13); ctx.lineTo(21, 14);
            ctx.arc(17, 14, 4, 0, 0.5 * Math.PI);
            ctx.lineTo(3, 18);
            ctx.stroke();
            break;

        case "bolt":
            ctx.beginPath();
            ctx.moveTo(13, 2);
            ctx.lineTo(5.5, 13.5);
            ctx.lineTo(11, 13.5);
            ctx.lineTo(10, 22);
            ctx.lineTo(18.5, 10.5);
            ctx.lineTo(12.5, 10.5);
            ctx.closePath();
            ctx.stroke();
            break;

        case "gauge": {
            // полукруг со стрелкой по центру — баланс
            ctx.beginPath();
            ctx.arc(12, 16, 8, Math.PI, 2 * Math.PI);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(12, 16);
            ctx.lineTo(12, 9.5);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(12, 16, 1.6, 0, 2 * Math.PI);
            ctx.fill();
            break;
        }

        case "leaf": {
            ctx.beginPath();
            ctx.moveTo(5.5, 19);
            ctx.quadraticCurveTo(5, 8, 18.5, 5);
            ctx.quadraticCurveTo(19.5, 16.5, 5.5, 19);
            ctx.closePath();
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(7.5, 17);
            ctx.quadraticCurveTo(11, 12.5, 15.5, 8.5);
            ctx.stroke();
            break;
        }

        case "sun": {
            // диск + 8 лучей по кругу
            ctx.beginPath();
            ctx.arc(12, 12, 4.2, 0, 2 * Math.PI);
            ctx.stroke();
            var sr = 7.4;
            for (var ray = 0; ray < 8; ray++) {
                var a = ray * Math.PI / 4;
                ctx.beginPath();
                ctx.moveTo(12 + Math.cos(a) * sr, 12 + Math.sin(a) * sr);
                ctx.lineTo(12 + Math.cos(a) * (sr + 2.2), 12 + Math.sin(a) * (sr + 2.2));
                ctx.stroke();
            }
            break;
        }

        case "palette": {
            // палитра художника: капля-корпус с выемкой и три точки красок
            ctx.beginPath();
            ctx.arc(12, 12, 8.2, -0.6, Math.PI * 2 - 0.6, false);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(14.5, 15.5, 2.6, 0, Math.PI);
            ctx.stroke();
            var dots = [[8.4, 9.6], [12, 8.2], [15.4, 9.8]];
            for (var d = 0; d < dots.length; d++) {
                ctx.beginPath();
                ctx.arc(dots[d][0], dots[d][1], 1.15, 0, 2 * Math.PI);
                ctx.fill();
            }
            break;
        }
        }
    }
    }
}
