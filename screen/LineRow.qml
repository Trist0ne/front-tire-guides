import QtQuick 2.0
import HmiGui 1.0
import HmiGuiFramework 1.0
import HmiGuiFramework.Controls 1.0
import Hmi.Ford 1.0
import Hmi.Ford.Controls 1.0

// "Line Brightness" and "Line Transparency" on the Front Camera settings page: one percentage each, on Ford's own
// slider with arrow buttons (IndicatorSettingBar, as "Lift Offset" beside them). What the row is for is set by the
// Loader that brings it in (title, key, range, the value with no file), then start() reads the stored value.
// The choice is kept in /fs/rwdata/frontguides/<key>.json ({"brightness": 95}), which the program reads once a
// second and hands to the drawing; no file means the default.
// A file of its own, brought in by a Loader in our block of Ford's page, so a fault here cannot blank that page.
Item {
    id: row
    objectName: "RVCSettings_frontGuidesLineRow_" + key
    width: parent ? parent.width : 722
    height: 154

    property string title: ""
    property string key: ""                // "brightness" or "transparency": the file's name and the name in it
    property real min: 0
    property real max: 100
    property real step: 5
    property real def: 0                   // the value with no file
    property string minText: ""            // the ends of the scale
    property string maxText: ""
    property real value: 0                 // per cent
    property bool loaded: false            // nothing is written before the stored value has been read
    readonly property string _url: "file:///fs/rwdata/frontguides/" + key + ".json"
    function _snap(v) { return Math.max(min, Math.min(max, Math.round(v / step) * step)); }
    function start() { if (key !== "") _read(); }
    function _read() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            // (read by pattern, not as JSON: a file caught while it is being rewritten can have a stray tail)
            var m = new RegExp('"' + row.key + '"\\s*:\\s*([0-9.]+)').exec(x.responseText || ""), v = m ? Number(m[1]) : NaN;
            row.value = row._snap(v >= row.min && v <= row.max ? v : row.def);
            bar.value = row.value; row.loaded = true;
        };
        try { x.open("GET", _url); x.send(); } catch (e) { row.value = row._snap(row.def); bar.value = row.value; row.loaded = true; }
    }
    function _write() {
        try {
            var o = {}; o[key] = value;
            var x = new XMLHttpRequest();
            x.open("PUT", _url);
            x.send(JSON.stringify(o) + "    ");   // (padded: a shorter text must cover a longer one)
        } catch (e) {}
    }
    Timer { id: save; interval: 300; onTriggered: row._write() }
    onVisibleChanged: if (visible && loaded) _read()

    ButtonTextLabel {
        objectName: "RVCSettings_frontGuidesLineTitle_" + row.key
        x: 36; y: 10
        variation: HmiGui.BigLabelVariation
        text: row.title
    }
    IndicatorSettingBar {
        id: bar
        objectName: "RVCSettings_frontGuidesLineBar_" + row.key
        anchors.horizontalCenter: parent.horizontalCenter
        y: 72                              // (8 lower than Lift Offset's: a low value's number sits under a long title)
        minimumValue: row.min
        maximumValue: row.max
        stepSize: row.step
        showProgress: true
        onValueChanged: {
            var v = row._snap(value);
            if (!row.loaded || v === row.value) return;
            row.value = v;
            save.restart();   // one write, once the handle has rested (as Lift Offset)
        }
    }
    // the chosen number above the handle (the slider's groove runs between the two arrow buttons)
    TextLabel {
        id: now
        objectName: "RVCSettings_frontGuidesLineValue_" + row.key
        readonly property real grooveX: bar.x + bar.slider.x
        x: grooveX + (bar.slider.width - 16) * (row.value - row.min) / Math.max(1, row.max - row.min) + 8 - width / 2
        y: bar.y - height + 6
        text: Math.round(row.value) + "%"
    }
    TextLabel {
        objectName: "RVCSettings_frontGuidesLineMin_" + row.key
        x: now.grooveX
        y: bar.y + bar.height + 2
        text: row.minText
    }
    TextLabel {
        objectName: "RVCSettings_frontGuidesLineMax_" + row.key
        x: now.grooveX + bar.slider.width - width
        y: bar.y + bar.height + 2
        text: row.maxText
    }
}
