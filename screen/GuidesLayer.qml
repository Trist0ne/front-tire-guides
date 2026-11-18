import QtQuick 2.0
import AL2HMIBridge 1.0 as AL2HMIBridge

// Front Tire Guides: the layer in Ford's camera popup (one Loader in fordhmi/qml/hmirvc/RVCPopup.qml, added by the
// installer and removed by the uninstaller). The camera itself opens and closes as stock.
//
// This layer draws the guides and nothing else. What to draw comes from the program (guidesd: calibration, lift
// setting and steering are its business), in /fs/tmpfs/frontguides:
//   look.json                truck, look and cameras, about 1 kB, read once (again when its id changes)
//   sw.pbm, st.pbm, sf.pbm   the steering to show, the Tire Guides switch and the look's id, as the sizes of pictures
// The overlay (GuidesOverlay) draws on SYNC's graphics chip: on every frame of the screen it is handed the steering
// at that frame's moment (between the last values, 50 ms behind the program's clock), one number.
// No look or steering from the program (camera not calibrated, program not running): nothing is drawn.
Item {
    id: th
    anchors.fill: parent

    readonly property int view: AL2HMIBridge.rvcSource.multicameraShowing
    readonly property bool reverse: AL2HMIBridge.globalSource.transmissionStatus === AL2HMIBridge.GlobalSource.TransmissionStatusReverse
    readonly property bool front: view === AL2HMIBridge.RVCSource.IPMBFrontNormal || view === AL2HMIBridge.RVCSource.IPMBFront
                                  || view === AL2HMIBridge.RVCSource.IPMBFrontSplit || view === AL2HMIBridge.RVCSource.IPMBFront360
    readonly property bool split: view === AL2HMIBridge.RVCSource.IPMBFrontSplit
    // the Tire Guides switch (Ford's view row and the Front Camera settings page): off = no guides
    property bool switchOn: true
    // the program's steering: the last four values in a ring filled in place (st)
    property var st: ({ ring: [{ t: 0, sw: 0 }, { t: 0, sw: 0 }, { t: 0, sw: 0 }, { t: 0, sw: 0 }], at: 0, n: 0 })
    property int seq: 0                    // up by one with each new value
    property int curView: -1               // the view the program's steering is for
    property real clock: 0                 // this layer's clock minus the program's: the quickest a value has got here
    property real shapesAt: 0
    property bool live: false              // a new value within the last 4 s (a still wheel is rewritten twice a second)
    property int lookK: 0                  // the id of the look held
    property var look: null
    property bool reading: false
    property bool lookTried: false         // the look was asked for once before any steering came
    readonly property int tview: split ? 9 : 8
    readonly property bool guidesOn: switchOn && front && !reverse && live && curView === tview

    // Nothing is made and dropped while a front view is up, as far as a script can help it. SYNC's script engine
    // (Qt 5.6) stops the whole screen for about a tenth of a second while it clears away objects that scripts have
    // dropped, and all of Ford's screens share that one engine with us: every object we drop brings the next stop
    // nearer. A file read through a request (XMLHttpRequest) costs the engine several kB, whatever the script does
    // with the answer, so none is made while a front view is up: the steering, the Tire Guides switch and the look's
    // id come as the sizes of pictures (below), and the last values are kept in a ring filled in place.
    Component.onCompleted: readLook()

    // The steering, 30 times a second: the program writes it as the sizes of two empty pictures (sw.pbm's width is the
    // steering, st.pbm's the time, their heights a count that must agree, and the split view), and a picture's size
    // comes to a script as plain numbers. A picture is read again when its address changes, so each look names the
    // same file in the other of two spellings. A third picture, looked at six times a second, carries the Tire
    // Guides switch (the program reads the switch's file for us) and the look's id, so a new look is noticed.
    Image { id: picS; visible: false; cache: false; asynchronous: false }
    Image { id: picT; visible: false; cache: false; asynchronous: false }
    Image { id: picF; visible: false; cache: false; asynchronous: false }
    property int misses: 0                 // looks that found no picture since the camera opened
    property bool flipF: false
    property int lookCode: -1              // the look's id as the third picture gives it (% 2048)
    // (the addresses as one list made once: read from a text property, each reading would make a new text for the
    // engine to clear away, 60 a second)
    property var urls: ["file:///fs/tmpfs/frontguides/sw.pbm", "file:///fs/tmpfs/frontguides/./sw.pbm", "file:///fs/tmpfs/frontguides/st.pbm", "file:///fs/tmpfs/frontguides/./st.pbm",
                        "file:///fs/tmpfs/frontguides/sf.pbm", "file:///fs/tmpfs/frontguides/./sf.pbm"]
    property bool flip: false
    property int lastS: 0                  // the sizes last taken: the same again is no new value
    property int lastT: 0
    property int lastH: 0
    property real tFull: 0                 // the program's time in full: the pictures give it modulo 4096 ms
    property int wait: 0                   // looks to sit out after a picture was not there (the program not writing)
    property int beat: 0
    Timer {
        // Looked at as often as the program writes (a value every 33 ms on its own steady clock): the overlay
        // glides between the values and past the newest, on the screen's own frames.
        interval: 33; repeat: true; running: th.front
        onRunningChanged: { if (!running) { th.live = false; picS.source = ""; picT.source = ""; picF.source = ""; th.lastS = 0; }
                            th.wait = 0; th.misses = 0; }
        onTriggered: {
            if (th.live && Date.now() - th.shapesAt > 4000) th.live = false;
            if (th.wait > 0) { th.wait--; return; }
            if (++th.beat % 5 === 0) {         // six times a second: the switch and the look's id
                th.flipF = !th.flipF;
                picF.source = th.urls[th.flipF ? 4 : 5];
                if (picF.status === Image.Ready) {
                    var fl = picF.implicitWidth - 1, on = fl % 2 === 0, code = (fl - fl % 2) / 2;
                    if (on !== th.switchOn) th.switchOn = on;
                    if (code !== th.lookCode) { th.lookCode = code; th.lookK = 0; th.lookTried = false; th.readLook(); }
                    else if (!th.lookTried && !th.reading && (th.look === null || th.lookK % 2048 !== code)) th.readLook();   // (not got yet: again)
                }
            }
            th.flip = !th.flip;
            var u = th.urls;
            picS.source = u[th.flip ? 0 : 1];
            picT.source = u[th.flip ? 2 : 3];
            // not there. Just after the camera opens the program's first picture can be a moment behind this
            // first look: again in a tenth of a second, for two seconds; after that (the program not running)
            // only every two seconds. (Until 11-17 one early look cost the guides two seconds.)
            if (picS.status !== Image.Ready || picT.status !== Image.Ready) { th.wait = th.misses++ < 20 ? 2 : 60; return; }
            th.misses = 0;
            th.took(picS.implicitWidth, picS.implicitHeight, picT.implicitWidth, picT.implicitHeight);
        }
    }
    function took(wS, hS, wT, hT) {
        var split = hT > 4;
        if (hS < 1 || (hS - 1) % 4 !== (hT - 1) % 4) return;               // not a pair: one of them is the next already
        if (wS === lastS && wT === lastT && hT === lastH) return;           // the same value as last time
        lastS = wS; lastT = wT; lastH = hT;
        var now = Date.now(), sw = (wS - 1) / 8 - 600, v = split ? 9 : 8, code = wT - 1, q = st, r = q.ring, newest = r[q.at];
        // the time in full: forward from the last by the difference of the codes (values come at most half a second
        // apart while the program writes); afresh after a silence
        var tt = (shapesAt > 0 && now - shapesAt < 3000) ? tFull + ((code - (tFull % 4096) + 4096) % 4096) : code;
        if (tt <= tFull && shapesAt > 0 && now - shapesAt < 3000) tt = tFull + 1;
        var afresh = !(shapesAt > 0 && now - shapesAt < 3000);
        tFull = tt;
        var c = now - tt;
        // the program's clock against ours: the least delay seen, let rise slowly (clocks drift), taken afresh
        // after a jump or a silence
        clock = afresh || Math.abs(c - clock) > 500 ? c : Math.min(clock + 0.05, c);
        if (afresh || q.n < 1 || curView !== v || tt <= newest.t) {         // nothing to glide from
            q.at = 0; q.n = 1; r[0].t = tt; r[0].sw = sw;
        } else if (tt - newest.t > 200) {                                   // after a still wheel: it was at rest there until one beat ago
            var was = newest.sw;
            r[0].t = tt - 34; r[0].sw = was; r[1].t = tt; r[1].sw = sw; q.at = 1; q.n = 2;
        } else {
            q.at = (q.at + 1) % 4; r[q.at].t = tt; r[q.at].sw = sw;
            if (q.n < 4) q.n++;
        }
        if (curView !== v) curView = v;
        shapesAt = now;
        seq++;
        if (!live) live = true;
    }
    // The look: read when the layer is made (whatever is there, so the strips are ready before the first steering)
    // and when the third picture says its id has changed (a new lift setting or calibration, or the program started).
    function readLook() {
        if (reading || lookTried) return;
        lookTried = true;
        var x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            th.reading = false;
            var t = x.responseText || "", e = null;
            if (t.charAt(t.length - 1) === "\n") { try { e = JSON.parse(t); } catch (err) { e = null; } }
            if (!e || !e.cams) { th.lookTried = false; return; }     // not whole (or not there yet): again when asked
            if (th.lookCode >= 0 && e.k % 2048 !== th.lookCode) th.lookTried = false;   // an older one than the picture names: again
            th.look = e; th.lookK = e.k;
        };
        try { reading = true; x.open("GET", "file:///fs/tmpfs/frontguides/look.json"); x.send(); } catch (err) { reading = false; lookTried = false; }
    }
    GuidesOverlay {
        id: overlay
        anchors.fill: parent
        shown: th.guidesOn
        st: th.st
        seq: th.seq
        clock: th.clock
        look: th.look
        tview: th.tview
    }
}
