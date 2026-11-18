import QtQuick 2.0

// The front tires' guides over the front camera picture, in the style of the 2025 Bronco Sport's Trail View.
//
// Drawn on SYNC's graphics chip, as Ford's own screens are. For each tire there is a strip of ground along its path:
// a mesh whose corners the vertex shader carries along the steering's arc and through the camera model (the same
// arithmetic as program/tirepath.c, with the numbers from the program's look.json), and a fragment shader that
// colours the strip: blocks with saw-tooth ends, the rail beside them, and the part under the bumper in orange.
// Per frame the script hands over one number, the steering. Nothing is painted on the processor.
//
// It fills the camera picture's rectangle. The split view is the same three times, each clipped to its pane.
Item {
    id: tp
    property var look: null                // the program's look.json: truck, look, cameras ({k, L, lock, ..., cams: [...]})
    // The last steering values, in a ring the layer fills in place: st.ring[0..3] = {t, sw}, st.at the newest, st.n
    // how many hold (seq goes up by one with each new value). Nothing is made per value or per frame: SYNC's script
    // engine stops the whole screen while it clears away objects that scripts have made and dropped.
    property var st: null
    property int seq: 0
    property real clock: 0                 // this clock (Date.now()) minus the program's
    property int tview: 8                  // the view showing: 9 the split view, else the normal one
    property real delay: 50                // ms shown behind the program's clock: a value every 33 ms, a look every 33
    property bool shown: true
    // An off-white the ground shows through, and the part under the bumper (which the camera cannot see) the same
    // shapes in a muted orange.
    // "Line Brightness" and "Line Transparency" on the Front Camera settings page come in the look (bright, ink).
    // The standard is 95 % of white at 15 % see-through (until 11-17 a fixed off-white, 91 %, at 28 %: a little dim
    // in sunlight), with room above (white, solid) and below.
    readonly property real ink: look && look.ink !== undefined ? look.ink : 0.85            // the guides' opacity
    readonly property real bright: look && look.bright !== undefined ? look.bright : 0.95   // of white
    property color colour: "#FFFFFF"       // times bright
    property color xrayColour: "#D9793F"   // the part under the bumper
    readonly property real xrayFill: Math.min(1, 0.42 * ink / 0.75)   // as see-through as the rest, in proportion
    readonly property real xrayBright: Math.min(1, bright / 0.95)     // the orange as it is at the standard, dimmer below

    property real sw: 0                    // the steering drawn, set on every frame of the screen
    property bool have: false              // a steering value has come
    property bool resting: false           // the newest value is drawn as it is: nothing to do until the next

    onSeqChanged: { if (!have) have = true; resting = false; if (!beat.running) step(); }
    onShownChanged: resting = false

    // the screen's frames: an animation's value changes once for every frame drawn
    property real frame: 0
    NumberAnimation on frame { id: beat; from: 0; to: 1; duration: 1000; loops: Animation.Infinite; running: tp.shown && tp.visible }
    onFrameChanged: if (!resting) step()

    // The steering at this frame's moment: between the two values around it; past the newest, carried on along the
    // last two for 250 ms at most.
    function step() {
        var q = st;
        if (!q || q.n < 1 || !shown) return;
        var r = q.ring, i = q.at, s = r[i], v = s.sw, t0 = Date.now();
        if (q.n > 1 && r[(i + 3) % 4].sw !== s.sw) {
            var at = t0 - clock - delay, b = s, a = r[(i + 3) % 4], back = 1, newest = true;
            while (back < q.n - 1 && a.t > at) { b = a; back++; a = r[(i + 4 - back) % 4]; newest = false; }
            var f = (at - a.t) / (b.t - a.t);
            if (f < 0) f = 0;
            if (newest && f > 1) {
                var most = 1 + 250 / (b.t - a.t);
                if (f >= most) { f = most; resting = true; }
            }
            v = a.sw + (b.sw - a.sw) * f;
        } else resting = true;
        if (v !== sw) sw = v;
    }

    // The strips: one for each tire in the normal view, and one for each tire in each pane of the split view.
    property var guides: []
    property bool warm: false
    Timer { id: warmth; interval: 1500; onTriggered: tp.warm = false }
    onLookChanged: {
        var L = look, list = [], D = Math.PI / 180;
        if (!L || !L.cams || !L.cams.length) { guides = list; return; }
        function cam(c, split, lo, hi) {
            for (var side = -1; side <= 1; side += 2)
                list.push({ split: split, lo: lo, hi: hi, side: side, c: c,
                            cp: Math.cos(c.pitch * D), sp: Math.sin(c.pitch * D), cyw: Math.cos(c.yaw * D), syw: Math.sin(c.yaw * D),
                            cr: Math.cos(c.roll * D), sr: Math.sin(c.roll * D) });
        }
        cam(L.cams[0], false, 0, L.w);
        if (L.split && L.cams.length >= 4) {
            cam(L.cams[1], true, 0, L.div[0]);
            cam(L.cams[2], true, L.div[0], L.div[1]);
            cam(L.cams[3], true, L.div[1], L.w);
        }
        guides = list;
        warm = true; warmth.restart();
    }
    // The mesh's columns, across one tire's strip from left to right: a margin, the tire's edge, every corner of the
    // blocks' saw-tooth edges, the other edge, the rail's two edges and a margin beyond it (the rail is on the tire's
    // outer side). Each column knows how far the near and the far teeth reach there, so the fragment shader gets
    // them ready-made: between two corners a tooth's edge is straight, which is what the chip does between two
    // columns. Per-pixel work is what limits the frame rate on SYNC's chip, so the fragment shader is kept to a
    // floor and a few clamps.
    function columns(side) {
        var L = look, tw = L.tw, xs = [], list = [], i;
        function at(pts, x) {
            for (var j = 1; j < pts.length; j++)
                if (x <= pts[j][0]) return pts[j][0] > pts[j - 1][0] ? pts[j - 1][1] + (pts[j][1] - pts[j - 1][1]) * (x - pts[j - 1][0]) / (pts[j][0] - pts[j - 1][0]) : pts[j][1];
            return pts[pts.length - 1][1];
        }
        for (i = 0; i < L.near.length; i++) xs.push(L.near[i][0]);
        for (i = 0; i < L.far.length; i++) xs.push(L.far[i][0]);
        xs.push(0); xs.push(1);
        xs.sort(function (a, b) { return a - b; });
        for (i = 0; i < xs.length; i++)
            if (i === 0 || xs[i] - xs[i - 1] > 0.0005) list.push({ d: -tw / 2 + tw * xs[i], n: at(L.near, xs[i]), f: at(L.far, xs[i]) });
        var e0 = { n: at(L.near, 0), f: at(L.far, 0) }, e1 = { n: at(L.near, 1), f: at(L.far, 1) };
        var inner = side > 0 ? e0 : e1, outerE = side > 0 ? e1 : e0, o = tw / 2 + L.railgap;
        list.push({ d: -side * (tw / 2 + 0.03), n: inner.n, f: inner.f });
        list.push({ d: side * o, n: outerE.n, f: outerE.f });
        list.push({ d: side * (o + L.rail), n: outerE.n, f: outerE.f });
        list.push({ d: side * (o + L.rail + 0.03), n: outerE.n, f: outerE.f });
        list.sort(function (a, b) { return a.d - b.d; });
        return list;
    }
    readonly property int meshCols: look ? columns(1).length - 1 : 8
    function columnsText(side) {
        var c = columns(side), n = c.length - 1, t = "highp vec3 col(highp float x) {\n    highp float k = floor(x * " + n.toFixed(1) + " + 0.5);\n";
        for (var i = 0; i < n; i++)
            t += "    if (k < " + (i + 0.5).toFixed(1) + ") return vec3(" + c[i].d.toFixed(5) + ", " + c[i].n.toFixed(5) + ", " + c[i].f.toFixed(5) + ");\n";
        return t + "    return vec3(" + c[n].d.toFixed(5) + ", " + c[n].n.toFixed(5) + ", " + c[n].f.toFixed(5) + ");\n}\n";
    }
    readonly property string fragText: "
        varying highp vec2 g;
        varying highp vec2 pxs;
        varying highp float ok;
        uniform lowp float qt_Opacity;
        uniform highp float tw;
        uniform highp vec4 blk;
        uniform highp vec4 rl;
        uniform highp vec2 ends;
        uniform lowp vec4 inkA;
        uniform lowp vec4 inkB;
        varying highp vec2 pf;
        highp float edge(highp float m, highp float px) { return clamp(m * px + 0.5, 0.0, 1.0); }
        void main() {
            if (ok < 0.999) discard;
            highp float d = g.x;
            highp float s = g.y;
            highp float cov = 0.0;
            highp float back = 0.0;
            // the block this place is in, and the far teeth of the block before it, which reach a little into
            // this one's stretch (a block's near edge never starts before its own stretch)
            highp float i = floor((s - blk.x) / blk.y);
            highp float sa = blk.x + i * blk.y;
            highp float fp = pf.y;
            if (i >= -blk.w && i <= rl.w - 1.0) {
                cov = edge(s - sa - pf.x, pxs.y) * edge(sa + blk.z + fp - s, pxs.y);
                back = i < 0.0 ? 1.0 : 0.0;
            }
            if (i - 1.0 >= -blk.w && i - 1.0 <= rl.w - 1.0) {
                highp float c = edge(sa - blk.y + blk.z + fp - s, pxs.y);
                if (c > cov) { cov = c; back = i - 1.0 < 0.0 ? 1.0 : 0.0; }
            }
            cov = cov * edge(tw * 0.5 - abs(d), pxs.x);
            highp float rd = rl.z * d;
            highp float rc = edge(rd - rl.x, pxs.x) * edge(rl.y - rd, pxs.x) * edge(s - ends.x, pxs.y) * edge(ends.y - s, pxs.y);
            if (rc > cov) { cov = rc; back = s < blk.x ? 1.0 : 0.0; }
            gl_FragColor = (back > 0.5 ? inkB : inkA) * (cov * qt_Opacity);
        }"
    readonly property string vertL: look ? vertFor(-1) : ""
    readonly property string vertR: look ? vertFor(1) : ""
    function vertFor(side) { return vertHead + columnsText(side) + vertBody; }
    readonly property string vertHead: "
        uniform highp mat4 qt_Matrix;
        attribute highp vec4 qt_Vertex;
        attribute highp vec2 qt_MultiTexCoord0;
        uniform highp float sw;
        uniform highp float live;
        uniform highp vec3 truck;
        uniform highp float xt;
        uniform highp vec4 rng;
        uniform highp vec3 camPos;
        uniform highp vec4 rot;
        uniform highp vec2 rol;
        uniform highp vec4 lens;
        uniform highp vec3 dist;
        varying highp vec2 g;
        varying highp vec2 pxs;
        varying highp float ok;
        varying highp vec2 pf;
        "
    readonly property string vertBody: "
        highp vec3 proj(highp vec2 p) {
            highp float X = p.x - camPos.x;
            highp float Y = camPos.y;
            highp float Z = p.y - camPos.z;
            highp float x1 = X * rot.z - Z * rot.w;
            highp float z1 = X * rot.w + Z * rot.z;
            highp float y2 = Y * rot.x - z1 * rot.y;
            highp float z2 = Y * rot.y + z1 * rot.x;
            highp float x3 = x1 * rol.x + y2 * rol.y;
            highp float y3 = y2 * rol.x - x1 * rol.y;
            highp float rxy = sqrt(x3 * x3 + y3 * y3);
            if (dist.z > 0.5) {
                highp float good = z2 < 0.34 * sqrt(rxy * rxy + z2 * z2) ? 0.0 : 1.0;
                highp float zz = max(z2, 0.05);
                highp float tx = clamp(x3 / zz, -4.0, 4.0);
                highp float ty = clamp(y3 / zz, -4.0, 4.0);
                highp float dd = 1.0 + dist.x * (tx * tx + ty * ty);
                return vec3(lens.y + lens.w * lens.x * tx * dd, lens.z + lens.x * ty * dd, good);
            }
            highp float t = atan(rxy, z2);
            highp float r = lens.x * (t + dist.x * t * t * t + dist.y * t * t * t * t * t);
            highp float inv = rxy > 0.000001 ? 1.0 / rxy : 0.0;
            return vec3(lens.y + lens.w * r * x3 * inv, lens.z + r * y3 * inv, t > 1.75 ? 0.0 : 1.0);
        }
        highp vec2 pathpt(highp float px, highp float s, highp float sg, highp float R, highp float Rf) {
            if (sg == 0.0) return vec2(px, s);
            highp float cx = -sg * R;
            highp float th = sg * s / Rf;
            highp float vx = px - cx;
            highp float c = cos(th);
            highp float sn = sin(th);
            return vec2(cx + vx * c - truck.x * sn, vx * sn + truck.x * c - truck.x);
        }
        void main() {
            highp float d = truck.z * clamp(sw / truck.y, -1.0, 1.0);
            highp float sg = 0.0;
            highp float R = 0.0;
            highp float Rf = 1.0;
            if (abs(d) >= 0.15) {
                R = truck.x / tan(abs(d) * 0.017453292519943295);
                sg = d > 0.0 ? 1.0 : -1.0;
                Rf = sqrt(R * R + truck.x * truck.x);
            }
            highp vec3 cl = col(qt_MultiTexCoord0.x);
            highp float across = cl.x;
            pf = cl.yz;
            highp float along = mix(rng.z, rng.w, qt_MultiTexCoord0.y);
            highp vec3 a = proj(pathpt(xt + across, along, sg, R, Rf));
            highp vec3 b = proj(pathpt(xt + across + 0.01, along, sg, R, Rf));
            highp vec3 c = proj(pathpt(xt + across, along + 0.01, sg, R, Rf));
            g = vec2(across, along);
            pxs = vec2(length(b.xy - a.xy), length(c.xy - a.xy)) * 100.0;
            ok = a.z * b.z * c.z;
            gl_Position = live > 0.5 ? qt_Matrix * vec4(a.x, a.y, 0.0, 1.0) : vec4(2.0, 2.0, 0.0, 1.0);
        }"

    Repeater {
        model: tp.guides.length
        Item {
            id: pane
            readonly property var e: tp.guides[index]
            readonly property var k: tp.look
            x: e.lo; width: e.hi - e.lo; height: tp.height
            clip: e.split
            // on: this strip belongs to the view showing. While `warm` (the first moments after the look is read)
            // every strip is in the scene with nowhere to draw (live 0: all its corners at one point off the picture),
            // so the graphics chip builds all the shaders then, and not at the first turn of the wheel or the first
            // change to the split view, where the pause would show.
            readonly property bool on: tp.shown && tp.have && e.split === (tp.tview === 9)
            visible: on || tp.warm
            ShaderEffect {
                id: fx
                x: -pane.x; width: tp.width; height: tp.height
                mesh: GridMesh { resolution: Qt.size(tp.meshCols, 96) }
                // the steering, the truck (wheelbase, the wheel's lock, the road wheels' lock), this tire's middle
                property real sw: tp.sw
                property real live: pane.on ? 1 : 0
                property vector3d truck: Qt.vector3d(pane.k.L, pane.k.lock, pane.k.dlock)
                property real xt: pane.e.side * pane.k.tf / 2
                // the strip: across the tire from 3 cm inside it to 3 cm past the rail, along from the first block
                // under the bumper to the last block's end
                readonly property real pitch: pane.k.block + pane.k.gap
                readonly property real s0: pane.k.fo + pane.k.start
                readonly property real sEnd: s0 + pane.k.blocks * pitch - pane.k.gap
                readonly property real outer: pane.k.tw / 2 + pane.k.railgap + pane.k.rail + 0.03
                readonly property real inner: -pane.k.tw / 2 - 0.03
                property vector4d rng: Qt.vector4d(pane.e.side > 0 ? inner : -outer, pane.e.side > 0 ? outer : -inner,
                                                   s0 - pane.k.nb * pitch - pane.k.lead - 0.05, sEnd + 0.05)
                // the camera
                property vector3d camPos: Qt.vector3d(pane.e.c.x0, pane.e.c.h, pane.e.c.z0)
                property vector4d rot: Qt.vector4d(pane.e.cp, pane.e.sp, pane.e.cyw, pane.e.syw)
                property point rol: Qt.point(pane.e.cr, pane.e.sr)
                property vector4d lens: Qt.vector4d(pane.e.c.f, pane.e.c.cx, pane.e.c.cy, pane.e.c.sx)
                property vector3d dist: Qt.vector3d(pane.e.c.k1, pane.e.c.k2, pane.e.c.model)
                // the look
                property real tw: pane.k.tw
                property vector4d blk: Qt.vector4d(s0, pitch, pane.k.block, pane.k.nb)
                property vector4d rl: Qt.vector4d(pane.k.tw / 2 + pane.k.railgap, pane.k.tw / 2 + pane.k.railgap + pane.k.rail, pane.e.side, pane.k.blocks)
                property point ends: Qt.point(s0 - pane.k.nb * pitch - pane.k.lead, sEnd)
                property vector4d inkA: Qt.vector4d(tp.colour.r * tp.bright * tp.ink, tp.colour.g * tp.bright * tp.ink, tp.colour.b * tp.bright * tp.ink, tp.ink)
                property vector4d inkB: Qt.vector4d(tp.xrayColour.r * tp.xrayBright * tp.xrayFill, tp.xrayColour.g * tp.xrayBright * tp.xrayFill, tp.xrayColour.b * tp.xrayBright * tp.xrayFill, tp.xrayFill)
                vertexShader: pane.e.side > 0 ? tp.vertR : tp.vertL
                fragmentShader: tp.fragText
            }
        }
    }
}
