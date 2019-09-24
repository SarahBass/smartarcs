/*
    This file is part of SmartArcs Origin watch face.
    https://github.com/okdar/smartarcs

    SmartArcs Origin is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SmartArcs Origin is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with SmartArcs Origin. If not, see <https://www.gnu.org/licenses/gpl.html>.
*/

using Toybox.Activity;
using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SmartArcsView extends WatchUi.WatchFace {

    var isAwake = false;
    var partialUpdatesAllowed = false;
    var curClip;
    var fullScreenRefresh;
    var offscreenBuffer;
    var offSettingFlag = -999;
    var font = Graphics.FONT_TINY;
    var precompute;
    var lastMeasuredHR;

    //variables for pre-computation
    var screenWidth;
    var screenRadius;
    var arcRadius;
    var twoPI = Math.PI * 2;
    var dualTimeLocationY;
    var dualTimeTimeY;
    var dualTimeAmPmY;
    var dualTimeOneLinerY;
    var dualTimeOneLinerAmPmY;
    var eventNameY;
    var dateAt6Y;
    var ticks;
    var showTicks;
    var hourHandLength;
    var minuteHandLength;
    var secondHandLength;
    var handsTailLength;
    var fontHeight;

    //user settings
    var bgColor;
    var handsColor;
    var handsOutlineColor;
    var secondHandColor;
    var hourHandWidth;
    var minuteHandWidth;
    var showSecondHand;
    var secondHandWidth;
    var battery100Color;
    var battery30Color;
    var battery15Color;
    var notificationColor;
    var bluetoothColor;
    var dndColor;
    var alarmColor;
    var eventColor;
    var dualTimeColor;
    var dateColor;
    var ticksColor;
    var ticks1MinWidth;
    var ticks5MinWidth;
    var ticks15MinWidth;
    var eventName;
    var eventDate;
    var dualTimeOffset;
    var dualTimeLocation;
    var useBatterySecondHandColor;
    var oneColor;
    var handsOnTop;
    var showBatteryIndicator;
    var datePosition;
    var dateFormat;
    var arcsStyle;
    var arcPenWidth;
    var hrColor;
    var hrRefreshInterval;

    function initialize() {
        loadUserSettings();
        WatchFace.initialize();
        fullScreenRefresh = true;
        partialUpdatesAllowed = (Toybox.WatchUi.WatchFace has :onPartialUpdate);
    }

    //load resources here
    function onLayout(dc) {
        //if this device supports BufferedBitmap, allocate the buffers we use for drawing
        if (Toybox.Graphics has :BufferedBitmap) {
            // Allocate a full screen size buffer with a palette of only 4 colors to draw
            // the background image of the watchface.  This is used to facilitate blanking
            // the second hand during partial updates of the display
            offscreenBuffer = new Graphics.BufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            });
        } else {
            offscreenBuffer = null;
        }

        curClip = null;
    }

    //called when this View is brought to the foreground. Restore
    //the state of this View and prepare it to be shown. This includes
    //loading resources into memory.
    function onShow() {
    }

    //update the view
    function onUpdate(dc) {
        var deviceSettings = System.getDeviceSettings();

        //compute what does not need to be computed on each update
        if (precompute) {
            computeConstants(dc);
        }

        var today = Time.today();

        //we always want to refresh the full screen when we get a regular onUpdate call.
        fullScreenRefresh = true;

        var targetDc = null;
        if (offscreenBuffer != null) {
            dc.clearClip();
            curClip = null;
            //if we have an offscreen buffer that we are using to draw the background,
            //set the draw context of that buffer as our target.
            targetDc = offscreenBuffer.getDc();
        } else {
            targetDc = dc;
        }

        //clear the screen
        targetDc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        targetDc.fillCircle(screenRadius, screenRadius, screenRadius + 2);

        if (showBatteryIndicator) {
            drawBattery(targetDc);
        }
        if (notificationColor != offSettingFlag) {
            drawNotifications(targetDc, deviceSettings.notificationCount);
        }
        if (bluetoothColor != offSettingFlag) {
            drawBluetooth(targetDc, deviceSettings.phoneConnected);
        }
        if (dndColor != offSettingFlag) {
            drawDoNotDisturb(targetDc, deviceSettings.doNotDisturb);
        }
        if (alarmColor != offSettingFlag) {
            drawAlarms(targetDc, deviceSettings.alarmCount);
        }

        if (showTicks) {
            drawTicks(targetDc);
        }

        if (!handsOnTop) {
            drawHands(targetDc, System.getClockTime());
        }

        if (eventColor != offSettingFlag) {
            //compute days to event
            var eventDateMoment = new Time.Moment(eventDate);
            var daysToEvent = (eventDateMoment.value() - today.value()) / Gregorian.SECONDS_PER_DAY.toFloat();

            if (daysToEvent < 0) {
                //hide event when it is over
                eventColor = offSettingFlag;
                Application.getApp().setProperty("eventColor", offSettingFlag);
            } else {
                drawEvent(targetDc, eventName, daysToEvent.toNumber());
            }
        }

        if (dualTimeColor != offSettingFlag) {
            drawDualTime(targetDc, System.getClockTime(), dualTimeOffset, dualTimeLocation, deviceSettings.is24Hour);
        }

        if (dateColor != offSettingFlag) {
            drawDate(targetDc, today);
        }

        if (handsOnTop) {
            drawHands(targetDc, System.getClockTime());
        }

        if (isAwake && showSecondHand == 1) {
            drawSecondHand(targetDc, System.getClockTime());
        }

        //output the offscreen buffers to the main display if required.
        drawBackground(dc);

        if (partialUpdatesAllowed && (hrColor != offSettingFlag || showSecondHand == 2)) {
            onPartialUpdate(dc);
        }

        fullScreenRefresh = false;
    }

    //called when this View is removed from the screen. Save the state
    //of this View here. This includes freeing resources from memory.
    function onHide() {
    }

    //the user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() {
        isAwake = true;
    }

    //terminate any active timers and prepare for slow updates.
    function onEnterSleep() {
        isAwake = false;
        requestUpdate();
    }

    function loadUserSettings() {
        var app = Application.getApp();

        oneColor = app.getProperty("oneColor");
        if (oneColor == offSettingFlag) {
            battery100Color = app.getProperty("battery100Color");
            battery30Color = app.getProperty("battery30Color");
            battery15Color = app.getProperty("battery15Color");
            notificationColor = app.getProperty("notificationColor");
            bluetoothColor = app.getProperty("bluetoothColor");
            dndColor = app.getProperty("dndColor");
            alarmColor = app.getProperty("alarmColor");
            secondHandColor = app.getProperty("secondHandColor");
        } else {
            notificationColor = oneColor;
            bluetoothColor = oneColor;
            dndColor = oneColor;
            alarmColor = oneColor;
            secondHandColor = oneColor;
        }
        bgColor = app.getProperty("bgColor");
        ticksColor = app.getProperty("ticksColor");
        if (ticksColor != offSettingFlag) {
            ticks1MinWidth = app.getProperty("ticks1MinWidth");
            ticks5MinWidth = app.getProperty("ticks5MinWidth");
            ticks15MinWidth = app.getProperty("ticks15MinWidth");
        }
        handsColor = app.getProperty("handsColor");
        handsOutlineColor = app.getProperty("handsOutlineColor");
        hourHandWidth = app.getProperty("hourHandWidth");
        minuteHandWidth = app.getProperty("minuteHandWidth");
        showSecondHand = app.getProperty("showSecondHand");
        if (showSecondHand > 0) {
            secondHandWidth = app.getProperty("secondHandWidth");
        }
        eventColor = app.getProperty("eventColor");
        dualTimeColor = app.getProperty("dualTimeColor");
        dateColor = app.getProperty("dateColor");
        hrColor = app.getProperty("hrColor");
        arcsStyle = app.getProperty("arcsStyle");

        useBatterySecondHandColor = app.getProperty("useBatterySecondHandColor");

        if (eventColor != offSettingFlag) {
            eventName = app.getProperty("eventName");
            eventDate = app.getProperty("eventDate");
        }

        if (dualTimeColor != offSettingFlag) {
            dualTimeOffset = app.getProperty("dualTimeOffset");
            dualTimeLocation = app.getProperty("dualTimeLocation");
        }

        if (dateColor != offSettingFlag) {
            datePosition = app.getProperty("datePosition");
            dateFormat = app.getProperty("dateFormat");
        }

        if (hrColor != offSettingFlag) {
            hrRefreshInterval = app.getProperty("hrRefreshInterval");
            if (datePosition == 9) {
                datePosition = 3;
            }
        }

        handsOnTop = app.getProperty("handsOnTop");

        showBatteryIndicator = app.getProperty("showBatteryIndicator");

        //ensure that constants will be pre-computed
        precompute = true;
    }

    //pre-compute values which don't need to be computed on each update
    function computeConstants(dc) {
        screenWidth = dc.getWidth();
        screenRadius = screenWidth / 2;

        //computes hand lenght for watches with different screen resolution than 240x240
        var handLengthCorrection = screenWidth / 240.0;
        hourHandLength = (60 * handLengthCorrection).toNumber();
        minuteHandLength = (90 * handLengthCorrection).toNumber();
        secondHandLength = (100 * handLengthCorrection).toNumber();
        handsTailLength = (15 * handLengthCorrection).toNumber();

        showTicks = ((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0)) ? false : true;
        if (showTicks) {
            //array of ticks coordinates
            computeTicks();
        }

        //Y coordinates of time infos
        var fontAscent = Graphics.getFontAscent(font);
        fontHeight = Graphics.getFontHeight(font);
        dualTimeLocationY = screenWidth - (2 * fontHeight) - 32;
        dualTimeTimeY = screenWidth - (2 * fontHeight) - 30 + fontAscent;
        dualTimeAmPmY = screenWidth - fontHeight - 30 + fontAscent - Graphics.getFontHeight(Graphics.FONT_XTINY) - 1;
        dualTimeOneLinerY = screenWidth - fontHeight - 70;
        dualTimeOneLinerAmPmY = screenWidth - 70 - Graphics.getFontHeight(Graphics.FONT_XTINY) - 1;
        eventNameY = 35 + fontAscent;
        dateAt6Y = screenWidth - fontHeight - 30;

        if (arcsStyle == 2) {
            arcPenWidth = screenRadius;
        } else {
            arcPenWidth = 10;
        }
        arcRadius = screenRadius - (arcPenWidth / 2);

        //constants pre-computed, doesn't need to be computed again
        precompute = false;
    }

    function computeTicks() {
        var angle;
        ticks = new [31];
        //to save the memory compute only half of the ticks, second half will be mirrored.
        //I believe it will still save some CPU utilization
        for (var i = 0; i < 31; i++) {
            angle = i * twoPI / 60.0;
            if ((i % 15) == 0) { //quarter tick
                if (ticks15MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, 20, ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, 20, ticks5MinWidth);
                }
            } else if (ticks1MinWidth > 0) { //1-minute tick
                ticks[i] = computeTickRectangle(angle, 10, ticks1MinWidth);
            }
        }
    }

    function computeTickRectangle(angle, length, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, screenRadius], [-halfWidth, screenRadius - length], [halfWidth, screenRadius - length], [halfWidth, screenRadius]];
        return computeRectangle(coords, angle);
    }

    function computeRectangle(coords, angle) {
        var rect = new [4];
        var x;
        var y;
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        //transform coordinates
        for (var i = 0; i < 4; i++) {
            x = (coords[i][0] * cos) - (coords[i][1] * sin) + 0.5;
            y = (coords[i][0] * sin) + (coords[i][1] * cos) + 0.5;
            rect[i] = [screenRadius + x, screenRadius + y];
        }

        return rect;
    }

    function drawBattery(dc) {
        var batStat = System.getSystemStats().battery;
        dc.setPenWidth(arcPenWidth);
        if (oneColor != offSettingFlag) {
            dc.setColor(oneColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
        } else {
            if (batStat > 30) {
                dc.setColor(battery100Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                dc.setColor(battery30Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 153);
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 166.5);
            } else if (batStat <= 30 && batStat > 15){
                dc.setColor(battery30Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 166.5);
            } else {
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
            }
        }
    }

    function drawNotifications(dc, notifications) {
        if (notifications > 0) {
            drawItems(dc, notifications, 90, notificationColor);
        }
    }

    function drawBluetooth(dc, phoneConnected) {
        if (phoneConnected) {
            dc.setColor(bluetoothColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(arcPenWidth);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 0, -30);
        }
    }

    function drawDoNotDisturb(dc, doNotDisturb) {
        if (doNotDisturb) {
            dc.setColor(dndColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(arcPenWidth);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_COUNTER_CLOCKWISE, 270, -60);
        }
    }

    function drawAlarms(dc, alarms) {
        if (alarms > 0) {
            drawItems(dc, alarms, 270, alarmColor);
        }
    }

    function drawItems(dc, count, angle, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(arcPenWidth);
        if (count < 11) {
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, angle, angle - 30 - ((count - 1) * 6));
        } else {
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, angle, angle - 90);
        }
    }

    function drawTicks(dc) {
        var coord = new [4];
        dc.setColor(ticksColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 31; i++) {
            if (ticks[i] != null) {
                dc.fillPolygon(ticks[i]);
            }

            //mirror pre-computed ticks from the left side to the right side
            if (i > 0 && i <30 && ticks[i] != null) {
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], ticks[i][j][1]];
                }
                dc.fillPolygon(coord);
            }
        }
    }

    function drawHands(dc, clockTime) {
        var hourAngle, minAngle;

        //draw hour hand
        hourAngle = ((clockTime.hour % 12) * 60.0) + clockTime.min;
        hourAngle = hourAngle / (12 * 60.0) * twoPI;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + 2, handsTailLength + 2, hourHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * twoPI;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(minAngle, minuteHandLength + 2, handsTailLength + 2, minuteHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(minAngle, minuteHandLength, handsTailLength, minuteHandWidth));

        //draw bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        if (showSecondHand == 2) {
            dc.setPenWidth(secondHandWidth);
            dc.setColor(getSecondHandColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
        } else {
            dc.setPenWidth(bulletRadius);
            dc.setColor(handsColor,Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
        }
    }

    function drawSecondHand(dc, clockTime) {
        var secAngle;
        var secondHandColor = getSecondHandColor();

        //if we are out of sleep mode, draw the second hand directly in the full update method.
        secAngle = (clockTime.sec / 60.0) *  twoPI;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(secAngle, secondHandLength + 2, handsTailLength + 2, secondHandWidth + 4));
        }
        drawHand(dc, secondHandColor, computeHandRectangle(secAngle, secondHandLength, handsTailLength, secondHandWidth));

        //draw center bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        dc.setPenWidth(secondHandWidth);
        dc.setColor(secondHandColor, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
    }

    function drawHand(dc, color, coords) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(coords);
    }

    function computeHandRectangle(angle, handLength, tailLength, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, tailLength], [-halfWidth, -handLength], [halfWidth, -handLength], [halfWidth, tailLength]];
        return computeRectangle(coords, angle);
    }

    function getSecondHandColor() {
        var color;
        if (oneColor != offSettingFlag) {
            color = oneColor;
        } else if (useBatterySecondHandColor) {
            var batStat = System.getSystemStats().battery;
            if (batStat > 30) {
                color = battery100Color;
            } else if (batStat <= 30 && batStat > 15) {
                color = battery30Color;
            } else {
                color = battery15Color;
            }
        } else {
            color = secondHandColor;
        }

        return color;
    }

    //Handle the partial update event
    function onPartialUpdate(dc) {
        var refreshHR = false;
        var clockSeconds = System.getClockTime().sec;

        //should be HR refreshed?
        if (hrColor != offSettingFlag) {
            if (hrRefreshInterval == 1) {
                refreshHR = true;
            } else if (clockSeconds % hrRefreshInterval == 0) {
                refreshHR = true;
            }
        }

        //if we're not doing a full screen refresh we need to re-draw the background
        //before drawing the updated second hand position. Note this will only re-draw
        //the background in the area specified by the previously computed clipping region.
        if(!fullScreenRefresh) {
            drawBackground(dc);
        }

        if (showSecondHand == 2) {
            var secAngle = (clockSeconds / 60.0) * Math.PI * 2;
            var secondHandPoints = computeHandRectangle(secAngle, secondHandLength, handsTailLength, secondHandWidth);

            //update the cliping rectangle to the new location of the second hand.
            curClip = getBoundingBox(secondHandPoints);

            var bboxWidth = curClip[1][0] - curClip[0][0] + 1;
            var bboxHeight = curClip[1][1] - curClip[0][1] + 1;
            //merge clip boundaries with HR area
            if (hrColor != offSettingFlag) {
                if (curClip[0][0] > 30) {
                    bboxWidth = (curClip[0][0] - 30) + bboxWidth;
                    curClip[0][0] = 30;
                }
                if (curClip[0][1] > (screenRadius - (fontHeight / 2))) {
                    curClip[0][1] = screenRadius - (fontHeight / 2);
                    bboxHeight = curClip[1][1] - curClip[0][1];
                }
                if (curClip[1][1] < (screenRadius + (fontHeight / 2))) {
                    bboxHeight = (screenRadius + (fontHeight / 2)) - curClip[0][1];
                }
            }
            dc.setClip(curClip[0][0], curClip[0][1], bboxWidth, bboxHeight);

            if (hrColor != offSettingFlag) {
                drawHR(dc, refreshHR);
            }

            //draw the second hand to the screen.
            dc.setColor(getSecondHandColor(), Graphics.COLOR_TRANSPARENT);
            //debug rectangle
            //dc.drawRectangle(curClip[0][0], curClip[0][1], bboxWidth, bboxHeight);
            dc.fillPolygon(secondHandPoints);

            //draw center bullet
            var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
            dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        }

        //draw HR
        if (hrColor != offSettingFlag && showSecondHand != 2) {
            drawHR(dc, refreshHR);
        }
    }

    //Draw the watch face background
    //onUpdate uses this method to transfer newly rendered Buffered Bitmaps
    //to the main display.
    //onPartialUpdate uses this to blank the second hand from the previous
    //second before outputing the new one.
    function drawBackground(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        //If we have an offscreen buffer that has been written to
        //draw it to the screen.
        if( null != offscreenBuffer ) {
            dc.drawBitmap(0, 0, offscreenBuffer);
        }
    }

    //Compute a bounding box from the passed in points
    function getBoundingBox( points ) {
        var min = [9999,9999];
        var max = [0,0];

        for (var i = 0; i < points.size(); ++i) {
            if(points[i][0] < min[0]) {
                min[0] = points[i][0];
            }
            if(points[i][1] < min[1]) {
                min[1] = points[i][1];
            }
            if(points[i][0] > max[0]) {
                max[0] = points[i][0];
            }
            if(points[i][1] > max[1]) {
                max[1] = points[i][1];
            }
        }

        return [min, max];
    }

    function drawEvent(dc, eventName, daysToEvent) {
        dc.setColor(eventColor, Graphics.COLOR_TRANSPARENT);
        if (daysToEvent > 0) {
            dc.drawText(screenRadius, 35, font, daysToEvent, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(screenRadius, eventNameY, font, eventName, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(screenRadius, eventNameY, font, eventName, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawDualTime(dc, clockTime, offset, location, is24Hour) {
        var dualTime;
        var suffix12Hour = "";
        var dayPrefix = "";
        var dualHour = clockTime.hour + offset;

        //compute dual hour
        if (dualHour > 23) {
            dualHour = dualHour - 24;
            dayPrefix = "+";
        } else if (dualHour < 0) {
            dualHour = dualHour + 24;
            dayPrefix = "-";
        }

        //12-hour format conversion
        if (!is24Hour) {
            if (dualHour > 12) {
                dualHour = dualHour - 12;
                suffix12Hour = " PM";
            } else if (dualHour == 12) {
                suffix12Hour = " PM";
            } else {
                suffix12Hour = " AM";
            }
        }

        dc.setColor(dualTimeColor, Graphics.COLOR_TRANSPARENT);
        if (datePosition != 6 || dateColor == offSettingFlag) {
            //draw dual time at 6 position
            dc.drawText(screenRadius, dualTimeLocationY, font, location, Graphics.TEXT_JUSTIFY_CENTER);
            dualTime = Lang.format("$1$$2$:$3$", [dayPrefix, dualHour, clockTime.min.format("%02d")]);
            if (is24Hour) {
                dc.drawText(screenRadius, dualTimeTimeY, font, dualTime, Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                //X position fine tuning for 12-hour format
                var xShift = 50;
                if (dualHour < 10 && dayPrefix.equals("")) {
                    xShift = 38;
                } else if ((dualHour >= 10 && dayPrefix.equals("")) || (dualHour < 10 && !dayPrefix.equals(""))) {
                    xShift = 44;
                }
                dc.drawText(screenRadius - xShift, dualTimeTimeY, font, dualTime, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(screenRadius + xShift, dualTimeAmPmY, Graphics.FONT_XTINY, suffix12Hour, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        } else {
            if (is24Hour) {
                //24-hour format -> 6 characters for location
                location = location.substring(0, 6);
                dualTime = Lang.format("$1$$2$:$3$ $4$", [dayPrefix, dualHour, clockTime.min.format("%02d"), location]);
                dc.drawText(screenRadius, dualTimeOneLinerY, font, dualTime, Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                //12-hour format -> AM/PM position fine-tuning
                dualTime = Lang.format("$1$$2$:$3$", [dayPrefix, dualHour, clockTime.min.format("%02d")]);
                var loc = location.substring(0, 4);
                var xShift = 9;
                if (dualHour < 10 && dayPrefix.equals("")) {
                    xShift = 33;
                    loc = location.substring(0, 6);
                } else if ((dualHour >= 10 && dayPrefix.equals("")) || (dualHour < 10 && !dayPrefix.equals(""))) {
                    xShift = 21;
                    loc = location.substring(0, 5);
                }
                dc.drawText(43, dualTimeOneLinerY, font, dualTime, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(screenRadius - xShift, dualTimeOneLinerAmPmY, Graphics.FONT_XTINY, suffix12Hour, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(screenRadius + 77, dualTimeOneLinerY, font, loc, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }
    }

    function drawDate(dc, today) {
        var info = Gregorian.info(today, Time.FORMAT_MEDIUM);

        var dateString;
        switch (dateFormat) {
            case 0: dateString = info.day;
                    break;
            case 1: dateString = Lang.format("$1$ $2$", [info.day_of_week.substring(0, 3), info.day]);
                    break;
            case 2: dateString = Lang.format("$1$ $2$", [info.day, info.day_of_week.substring(0, 3)]);
                    break;
            case 3: dateString = Lang.format("$1$ $2$", [info.day, info.month.substring(0, 3)]);
                    break;
            case 4: dateString = Lang.format("$1$ $2$", [info.month.substring(0, 3), info.day]);
                    break;
        }
        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        switch (datePosition) {
            case 3: dc.drawText(screenWidth - 30, screenRadius, font, dateString, Graphics.TEXT_JUSTIFY_RIGHT|Graphics.TEXT_JUSTIFY_VCENTER);
                    break;
            case 6: dc.drawText(screenRadius, dateAt6Y, font, dateString, Graphics.TEXT_JUSTIFY_CENTER);
                    break;
            case 9: dc.drawText(30, screenRadius, font, dateString, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
                    break;
        }
    }

    function drawHR(dc, refreshHR) {
        var hr = 0;
        var hrText;
        var activityInfo;
        var hrTextDimension = dc.getTextDimensions("888", font); //to compute correct clip boundaries

        if (refreshHR) {
            activityInfo = Activity.getActivityInfo();
            if (activityInfo != null) {
                hr = activityInfo.currentHeartRate;
                lastMeasuredHR = hr;
            }
        } else {
            hr = lastMeasuredHR;
        }

        if (hr == null || hr == 0) {
            hrText = "";
        } else {
            hrText = hr.format("%i");
        }

        if (showSecondHand != 2) {
            dc.setClip(30, screenRadius - (hrTextDimension[1] / 2), hrTextDimension[0], hrTextDimension[1]);
        }

        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        //debug rectangle
        //dc.drawRectangle(30, screenRadius - (hrTextDimension[1] / 2), hrTextDimension[0], hrTextDimension[1]);
        dc.drawText(hrTextDimension[0] + 30, screenRadius, font, hrText, Graphics.TEXT_JUSTIFY_RIGHT|Graphics.TEXT_JUSTIFY_VCENTER);
    }

}
