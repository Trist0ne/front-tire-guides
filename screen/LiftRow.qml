import QtQuick 2.0
import HmiGui 1.0
import HmiGuiFramework 1.0
import HmiGuiFramework.Controls 1.0
import Hmi.Ford 1.0
import Hmi.Ford.Controls 1.0

// "Lift Offset" on the Front Camera settings page: how much higher than stock the truck sits, so one camera
// calibration serves every height. It is Ford's own slider with arrow buttons (IndicatorSettingBar, as on SYNC's
// ambient-light page): Stock at the left, +4 inches at the right, a quarter inch a step, with the chosen number above
// the handle. The choice is kept in /fs/rwdata/frontguides/lift.json ({"lift": 1.75}), which the program reads once a
// second; no file means Stock.
// A file of its own, brought in by a Loader in our block of Ford's page, so a fault here cannot blank that page.
Item {
    id: lift
    objectName: "RVCSettings_frontGuidesLiftRow"
    width: parent ? parent.width : 722
    height: 146

    property real value: 0                 // inches
    property bool loaded: false            // nothing is written before the stored value has been read
    readonly property string _url: "file:///fs/rwdata/frontguides/lift.json"
    function _snap(v) { return Math.max(0, Math.min(4, Math.round(v * 4) / 4)); }
    function label(v) { return v <= 0 ? "Stock" : "+" + (Math.round(v * 100) / 100) + " in"; }
    function _get(url, done) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            var v = NaN;
            // (read by pattern, not as JSON: a file caught while it is being rewritten can have a stray tail)
            var m = /"lift"\s*:\s*([0-9.]+)/.exec(x.responseText || "");
            if (m) v = Number(m[1]);
            done(v >= 0 && v <= 4 ? v : NaN);
        };
        try { x.open("GET", url); x.send(); } catch (e) { done(NaN); }
    }
    function _read() {
        _get(_url, function(v) {
            if (!isNaN(v)) { lift.value = _snap(v); bar.value = lift.value; lift.loaded = true; return; }
            lift.value = 0; bar.value = 0; lift.loaded = true;   // no setting yet: stock
        });
    }
    function _write() {
        try {
            var x = new XMLHttpRequest();
            x.open("PUT", _url);
            x.send(JSON.stringify({ lift: value }));
        } catch (e) {}
    }
    Timer { id: save; interval: 300; onTriggered: lift._write() }
    Component.onCompleted: _read()
    onVisibleChanged: if (visible) _read()

    ButtonTextLabel {
        id: title
        objectName: "RVCSettings_frontGuidesLiftTitle"
        x: 36; y: 10
        variation: HmiGui.BigLabelVariation
        text: "Lift Offset"
    }
    IndicatorSettingBar {
        id: bar
        objectName: "RVCSettings_frontGuidesLiftBar"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 64
        minimumValue: 0
        maximumValue: 4
        stepSize: 0.25
        showProgress: true
        onValueChanged: {
            var v = lift._snap(value);
            if (!lift.loaded || v === lift.value) return;
            lift.value = v;
            save.restart();   // one write, once the handle has rested: held arrows would queue a write a step,
                              // and writes to a file do not finish in the order they were started
        }
    }
    // the chosen number above the handle (the slider's groove runs between the two arrow buttons)
    TextLabel {
        id: now
        objectName: "RVCSettings_frontGuidesLiftValue"
        readonly property real grooveX: bar.x + bar.slider.x
        x: grooveX + (bar.slider.width - 16) * lift.value / 4 + 8 - width / 2
        y: bar.y - height + 6
        text: lift.label(lift.value)
    }
    // the ends of the scale, under the ends of the groove
    TextLabel {
        objectName: "RVCSettings_frontGuidesLiftMin"
        x: now.grooveX
        y: bar.y + bar.height + 2
        text: "Stock"
    }
    TextLabel {
        objectName: "RVCSettings_frontGuidesLiftMax"
        x: now.grooveX + bar.slider.width - width
        y: bar.y + bar.height + 2
        text: "+4 inches"
    }
}
