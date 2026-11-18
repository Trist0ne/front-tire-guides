import QtQuick 2.0
import HmiGui 1.0
import HmiGuiFramework 1.0
import HmiGuiFramework.Controls 1.0
import Hmi.Ford 1.0
import Hmi.Ford.Controls 1.0
import Hmi.Ford.Controls.Settings 1.0
import HmiSettings 1.0
import "front_camera.js" as FrontCamera

// The "Front Camera" row in SYNC's Driver Assistance menu. Shared by Front Tire Guides and Enhanced Camera Control:
// whichever is installed first puts it in, and it goes with the last of them.
// A file of its own, brought in by a Loader in our block of Ford's menu, so that a fault in it leaves one row missing
// and not the whole Driver Assistance page.
ArrowButton {
    id: frontCameraRow
    objectName: "DriverAssistSettingsMenu_frontCamera"

    property string lines: ""          // "Tire Guides On" / "Off" when Front Tire Guides is installed
    function _read() {
        var h = new XMLHttpRequest();   // is Front Tire Guides on SYNC at all?
        h.onreadystatechange = function() {
            if (h.readyState !== XMLHttpRequest.DONE) return;
            if (!h.responseText) { frontCameraRow.lines = ""; return; }
            var x = new XMLHttpRequest();
            x.onreadystatechange = function() {
                if (x.readyState !== XMLHttpRequest.DONE) return;
                frontCameraRow.lines = /"guides"\s*:\s*false/.test(x.responseText || "") ? "Tire Guides Off" : "Tire Guides On";
            };
            try { x.open("GET", "file:///fs/rwdata/frontguides/switch.json"); x.send(); } catch (e) { frontCameraRow.lines = "Tire Guides On"; }
        };
        try { h.open("GET", "file:///fs/mp/fordhmi/qml/hmirvc/frontguides/GuidesLayer.qml"); h.send(); } catch (e) {}
    }
    Component.onCompleted: _read()
    onVisibleChanged: if (visible) _read()

    onClicked: {
        FrontCamera.front = true;
        _hmiSettings.controller.requestTransition(HmiSettingsController.ToRVCSettingsPage);
    }
    infoButtonVisible: false
    buttonIconVisible: true            // the camera picture Ford's own Rear View Camera row has
    buttonIconId: "DAT/icon_rear_camera_view"
    text: "Front Camera"
    secondaryText: lines
}
