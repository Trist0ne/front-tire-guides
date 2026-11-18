.pragma library
// Tire paths on the front camera picture: where each front tire will roll at this
// steering, as points on the ground, and where those points fall on the camera picture. Pure maths, no drawing:
// the same arithmetic as the screen overlay's shaders and program/tirepath.c; used here by the calibration tool.
//
// Ground frame: metres, origin on the ground under
// the middle of the front axle, x to the passenger side, z forward. Steering in degrees at the wheel, + = left.

// ---- the truck (2021 Bronco Sport Badlands; ui_geo.c) -------------------------------------------------------------
var L = 2.670, TF = 1.610, TR = 1.595, TW = 0.235, FO = 0.856, LOCK = 501, TW0 = TW, TF0 = TF;
var DLOCK = (function () {   // road-wheel angle at full lock, from the 11.40 m curb-to-curb turning circle
    var Rc = 11.40 / 2 - TW / 2, Rro = Math.sqrt(Rc * Rc - L * L), R = Rro - TR / 2;
    return Math.atan(L / R) * 180 / Math.PI;
})();

function roadWheel(sw) { return DLOCK * Math.max(-1, Math.min(1, sw / LOCK)); }

function steerGeo(sw) {
    var d = roadWheel(sw);
    if (Math.abs(d) < 0.15) return { d: 0, R: 0, sg: 0, Rf: 0 };
    var R = L / Math.tan(Math.abs(d) * Math.PI / 180);
    return { d: d, R: R, sg: d > 0 ? 1 : -1, Rf: Math.sqrt(R * R + L * L) };
}

// The point that starts at p0 = [x, z], after the truck has moved s metres (measured at the front axle's middle).
function pathPt(p0, g, s) {
    if (!g.sg) return [p0[0], p0[1] + s];
    var cx = -g.sg * g.R, cz = -L, th = g.sg * s / g.Rf, vx = p0[0] - cx, vz = p0[1] - cz;
    return [cx + vx * Math.cos(th) - vz * Math.sin(th), cz + vx * Math.sin(th) + vz * Math.cos(th)];
}

// One tire's track on the ground: its inner and outer edge as rows of [x, z], from the tire's contact patch
// (s = 0) to `ahead` metres on, a point every `step`. side: -1 driver's (left), +1 passenger's.
function track(sw, side, ahead, step, width) {
    var g = steerGeo(sw), w = width === undefined ? TW : width, x0 = side * TF / 2;
    var a = [], b = [], c = [];
    for (var s = 0; s <= ahead + 1e-9; s += step) {
        a.push(pathPt([x0 - w / 2, 0], g, s));
        b.push(pathPt([x0 + w / 2, 0], g, s));
        c.push(pathPt([x0, 0], g, s));
    }
    return { left: a, right: b, centre: c, geo: g };
}

// A bar across one tire's track s metres ahead of the tire: its two ends.
function bar(sw, side, s, width) {
    var g = steerGeo(sw), w = width === undefined ? TW : width, x0 = side * TF / 2;
    return [pathPt([x0 - w / 2, 0], g, s), pathPt([x0 + w / 2, 0], g, s)];
}

// ---- the camera -----------------------------------------------------------------------------------------------
// A general wide-angle model (Kannala-Brandt): a ray at angle t from the lens axis lands f * (t + k1 t^3 + k2 t^5)
// pixels from the picture's centre. With k1 = 1/3, k2 = 2/15 that is close to an ordinary (rectilinear) picture; with
// k1 = k2 = 0 a pure fisheye. So one set of numbers fits whichever view the camera module sends (its "normal" view is
// already straightened by the module to an unknown degree), and they come from marks on the ground (fit below).
//   h      lens height above the ground (m)            z0    lens ahead of the front axle (m)
//   x0     lens to the passenger side of centre (m)    pitch lens axis below level (deg)
//   yaw    axis towards the passenger side (deg)       roll  picture turned clockwise (deg)
//   f      pixels per radian at the centre             cx,cy the lens axis on the picture (px)
//   k1,k2  the lens curve                              sx    sideways stretch of the picture (1 = square pixels)
// model: 'rect' for a flat (rectilinear) view, as each pane of the front split view is: a ray lands
// f * tan(t) * (1 + k1 tan^2 t) from the centre; k2 unused.
var NAMES = ['h', 'z0', 'x0', 'pitch', 'yaw', 'roll', 'f', 'cx', 'cy', 'k1', 'k2', 'sx'];

function defaults(w, h) {   // a starting guess for an 800 x 480 picture: grille camera, tipped down, about 110 deg across
    return { h: 0.80, z0: FO, x0: 0, pitch: 22, yaw: 0, roll: 0, f: (w || 800) / 1.9, cx: (w || 800) / 2, cy: (h || 480) / 2,
             k1: 0, k2: 0, sx: 1 };
}

// Ground point [x, z] -> picture [u, v], or null when it is behind the lens.
function project(cam, p) {
    var D = Math.PI / 180, X = p[0] - cam.x0, Y = cam.h, Z = p[1] - cam.z0;   // camera axes: X right, Y down, Z ahead
    var cp = Math.cos(cam.pitch * D), sp = Math.sin(cam.pitch * D), cyw = Math.cos(cam.yaw * D), syw = Math.sin(cam.yaw * D);
    var cr = Math.cos(cam.roll * D), sr = Math.sin(cam.roll * D);
    var x1 = X * cyw - Z * syw, z1 = X * syw + Z * cyw;          // yaw about the vertical
    var y2 = Y * cp - z1 * sp, z2 = Y * sp + z1 * cp;            // pitch down
    var x3 = x1 * cr + y2 * sr, y3 = -x1 * sr + y2 * cr;         // roll about the axis
    if (z2 <= 1e-6 && x3 * x3 + y3 * y3 < 1e-12) return null;
    if (cam.model === 'rect') {                                   // a flat view: nothing at or behind its sideways plane
        // nothing more than 70 deg off its axis: a pane shows far less, and nearer 90 deg a point lands anywhere
        //
        if (z2 < 0.34 * Math.sqrt(x3 * x3 + y3 * y3 + z2 * z2)) return null;
        var tx = x3 / z2, ty = y3 / z2, d = 1 + cam.k1 * (tx * tx + ty * ty);
        return [cam.cx + cam.sx * cam.f * tx * d, cam.cy + cam.f * ty * d];
    }
    var rxy = Math.sqrt(x3 * x3 + y3 * y3), t = Math.atan2(rxy, z2);
    if (t > 1.75) return null;                                    // more than 100 deg off the axis: not in any picture
    var r = cam.f * (t + cam.k1 * t * t * t + cam.k2 * t * t * t * t * t);
    if (rxy < 1e-12) return [cam.cx, cam.cy];
    return [cam.cx + cam.sx * r * x3 / rxy, cam.cy + r * y3 / rxy];
}

function projectRow(cam, pts) {
    var out = [];
    for (var i = 0; i < pts.length; i++) out.push(project(cam, pts[i]));
    return out;
}

// ---- the fit --------------------------------------------------------------------------------------------------
// marks: [{x, z, u, v}]: a mark's place on the ground (measured with a tape) and on the picture (read off a photo
// of the screen). free: the names to solve for (the rest stay as given in `start`). Levenberg-Marquardt on the
// picture error with a numeric slope. Returns {cam, rms (px), worst (px), iterations}.
function copyCam(c) { var o = {}; for (var key in c) o[key] = c[key]; return o; }

function fit(marks, start, free) {
    var cam = copyCam(start), i, j, k;
    var n = free.length, step = { h: 1e-3, z0: 1e-3, x0: 1e-3, pitch: 1e-2, yaw: 1e-2, roll: 1e-2, f: 0.1, cx: 0.1, cy: 0.1, k1: 1e-4, k2: 1e-4, sx: 1e-4 };
    function resid(c) {
        var r = [];
        for (var m = 0; m < marks.length; m++) {
            if (marks[m].line) { var lq = nearestOnLine(c, marks[m]); if (!lq) { r.push(1e3); r.push(1e3); } else { r.push(lq[0] - marks[m].u); r.push(lq[1] - marks[m].v); } continue; }
            var q = project(c, [marks[m].x, marks[m].z]);
            if (!q) { r.push(1e3); r.push(1e3); continue; }
            r.push(q[0] - marks[m].u); r.push(q[1] - marks[m].v);
        }
        return r;
    }
    function sum2(r) { var s = 0; for (var a = 0; a < r.length; a++) s += r[a] * r[a]; return s; }
    var lam = 1e-2, r = resid(cam), cost = sum2(r), it = 0;
    for (it = 0; it < 4000; it++) {
        var J = [];
        for (j = 0; j < n; j++) {
            var c2 = copyCam(cam);
            c2[free[j]] += step[free[j]];
            var r2 = resid(c2), col = [];
            for (k = 0; k < r.length; k++) col.push((r2[k] - r[k]) / step[free[j]]);
            J.push(col);
        }
        var A = [], g = [];
        for (j = 0; j < n; j++) {
            A.push([]);
            var gj = 0;
            for (k = 0; k < r.length; k++) gj += J[j][k] * r[k];
            g.push(-gj);
            for (i = 0; i < n; i++) {
                var s = 0;
                for (k = 0; k < r.length; k++) s += J[j][k] * J[i][k];
                A[j].push(s);
            }
        }
        var better = false;
        for (var tries = 0; tries < 12 && !better; tries++) {
            var M = [], d;
            for (j = 0; j < n; j++) { M.push(A[j].slice()); M[j][j] *= 1 + lam; M[j].push(g[j]); }
            d = solve(M, n);
            if (d) {
                var c3 = copyCam(cam);
                for (j = 0; j < n; j++) c3[free[j]] += d[j];
                var r3 = resid(c3), cost3 = sum2(r3);
                if (cost3 < cost) {
                    var gain = cost - cost3;
                    cam = c3; r = r3; cost = cost3; lam = Math.max(lam / 4, 1e-9); better = true;
                    if (gain < 1e-10) { it = 1e9; }
                    continue;
                }
            }
            lam *= 6;
        }
        if (!better || it >= 1e9) break;
    }
    var worst = 0;
    for (k = 0; k < r.length; k += 2) worst = Math.max(worst, Math.sqrt(r[k] * r[k] + r[k + 1] * r[k + 1]));
    return { cam: cam, rms: Math.sqrt(cost / (r.length / 2)), worst: worst };
}

// A line mark: a straight line on the ground whose position is measured (two points, [x, z] each: a painted
// line, say) and one picture point (u, v) somewhere on it. Its error is the distance from that point to where the
// camera shows the line: the point on the drawn line nearest to it.
function nearestOnLine(c, m) {
    var a = m.line[0], b = m.line[1], L = Math.hypot(b[0] - a[0], b[1] - a[1]), ux = (b[0] - a[0]) / L, uz = (b[1] - a[1]) / L;
    var best = null, k;
    function at(t) { return project(c, [a[0] + t * ux, a[1] + t * uz]); }   // t: metres along the line from its first point
    function d2(t) { var q = at(t); return q ? (q[0] - m.u) * (q[0] - m.u) + (q[1] - m.v) * (q[1] - m.v) : 1e12; }
    for (k = 0; k <= 120; k++) { var t = -30 + k * 0.5, e = d2(t); if (!best || e < best[1]) best = [t, e]; }
    var t1 = best[0] - 0.5, t2 = best[0] + 0.5;
    for (k = 0; k < 40; k++) {   // golden-section search between the neighbours of the best sample
        var p1 = t2 - (t2 - t1) * 0.618, p2 = t1 + (t2 - t1) * 0.618;
        if (d2(p1) < d2(p2)) t2 = p2; else t1 = p1;
    }
    return at((t1 + t2) / 2);
}

function solve(M, n) {   // Gauss elimination with pivoting on the n x (n+1) rows of M; null when singular
    for (var c = 0; c < n; c++) {
        var p = c;
        for (var r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
        if (Math.abs(M[p][c]) < 1e-14) return null;
        var t = M[c]; M[c] = M[p]; M[p] = t;
        for (r = c + 1; r < n; r++) {
            var f = M[r][c] / M[c][c];
            for (var k = c; k <= n; k++) M[r][k] -= f * M[c][k];
        }
    }
    var x = [];
    for (c = n - 1; c >= 0; c--) {
        var s = M[c][n];
        for (var k2 = c + 1; k2 < n; k2++) s -= M[c][k2] * x[k2];
        x[c] = s / M[c][c];
    }
    return x;
}

// The whole calibration: nothing about the lens known beforehand. A single fit can settle in a poor answer (the
// lens curve, the stretch and the focal length trade against each other), so it is run in stages (the big things
// first) from several starting guesses, and the best is kept.
// lensHeight (m, optional): the lens's measured height above the ground, held instead of fitted. Marks that all lie in
// a strip ahead of the tires (a driveway, say) can't tell a higher camera from a longer lens: the fit was as good
// at 0.65 m as at 1.1 m, and the tracks drawn when turning differed by up to 120 px. With the height given they agree.
// lensAhead (m, optional): the lens's distance ahead of the front axle, held too. With a measured line far out to the
// side (a road edge, say) a free lens place went 0.4 m ahead of the bumper to shave a pixel off the fit.
function calibrate(marks, w, h, lensHeight, lensAhead) {
    var best = null, pitches = [12, 22, 32, 42], fs = [0.35, 0.55, 0.8], curves = [0, 0.33];
    var H = lensHeight > 0 ? [] : ['h'], Z = lensAhead > 0 ? [] : ['z0'];
    function free(list) { return list.filter(function (n) { return n !== 'z0' || Z.length; }).concat(H); }
    for (var a = 0; a < pitches.length; a++)
        for (var b = 0; b < fs.length; b++)
            for (var c = 0; c < curves.length; c++) {
                var s = defaults(w, h);
                s.pitch = pitches[a]; s.f = (w || 800) * fs[b]; s.k1 = curves[c];
                if (lensHeight > 0) s.h = lensHeight;
                if (lensAhead > 0) s.z0 = lensAhead;
                var r = fit(marks, s, free(['pitch', 'f']));
                r = fit(marks, r.cam, free(['pitch', 'f', 'cx', 'cy', 'yaw', 'roll']));
                r = fit(marks, r.cam, free(['pitch', 'f', 'cx', 'cy', 'yaw', 'roll', 'k1', 'sx']));
                r = fit(marks, r.cam, free(['pitch', 'f', 'cx', 'cy', 'yaw', 'roll', 'k1', 'sx', 'z0', 'k2', 'x0']));
                if (!best || r.rms < best.rms) best = r;
            }
    return best;
}

// ---- the front split view ----------------------------------------------------
// Three panes side by side, each a flat slice of the same lens: one camera each, at the real camera's place (h, z0,
// x0 from the normal view's calibration), with its own direction, focal length, centre and a little curve.
// div: the two dividers' x on the 800 px screen (read off the split-view photo; Ford's how-to video puts them near
// the thirds).
var DIV = [267, 533];

function paneOf(u, div) { return u < div[0] ? 0 : u < div[1] ? 1 : 2; }

// marks: [{x, z, u, v}] read off a photo of the split view; base: the normal view's calibrated camera.
// Returns {div, panes: [{cam, rms, worst, n}], rms, worst}, or null when a pane has fewer than 6 marks.
function calibrateSplit(marks, base, div, w) {
    div = div || DIV;
    var W = w || 800, bounds = [[0, div[0]], [div[0], div[1]], [div[1], W]], yaws = [[-75, -55, -35], [-15, 0, 15], [35, 55, 75]];
    var res = { div: div, panes: [], rms: 0, worst: 0 }, sum2 = 0, n2 = 0;
    for (var p = 0; p < 3; p++) {
        var mk = marks.filter(function (m) { return paneOf(m.u, div) === p; });
        if (mk.length < 6) return null;
        var best = null, mid = (bounds[p][0] + bounds[p][1]) / 2, pw = bounds[p][1] - bounds[p][0];
        for (var a = 0; a < 3; a++)
            for (var b = 0; b < 3; b++)
                for (var c = 0; c < 2; c++) {
                    var s = { model: 'rect', h: base.h, z0: base.z0, x0: base.x0, pitch: [20, 35, 50][b], yaw: yaws[p][a], roll: 0,
                              f: pw * [0.8, 1.3][c], cx: mid, cy: 240, k1: 0, k2: 0, sx: base.sx > 0 ? base.sx : 1 };
                    var r = fit(mk, s, ['yaw', 'pitch', 'f']);
                    r = fit(mk, r.cam, ['yaw', 'pitch', 'f', 'cx', 'cy', 'roll']);
                    r = fit(mk, r.cam, ['yaw', 'pitch', 'f', 'cx', 'cy', 'roll', 'k1'].concat(mk.length >= 8 ? ['sx'] : []));
                    if (!best || r.rms < best.rms) best = r;
                }
        best.n = mk.length;
        res.panes.push(best);
        sum2 += best.rms * best.rms * mk.length; n2 += mk.length;
        res.worst = Math.max(res.worst, best.worst);
    }
    res.rms = Math.sqrt(sum2 / n2);
    return res;
}

// Clip an outline to bounds lo <= u <= hi (Sutherland-Hodgman, two vertical edges).
function clipX(poly, lo, hi) {
    function edge(pts, x, keepAbove) {
        var o = [];
        for (var i = 0; i < pts.length; i++) {
            var a = pts[i], b = pts[(i + 1) % pts.length], ina = keepAbove ? a[0] >= x : a[0] <= x, inb = keepAbove ? b[0] >= x : b[0] <= x;
            if (ina) o.push(a);
            if (ina !== inb) { var t = (x - a[0]) / (b[0] - a[0]); o.push([x, a[1] + t * (b[1] - a[1])]); }
        }
        return o;
    }
    var r = edge(poly, lo, true);
    return r.length ? edge(r, hi, false) : r;
}

// ---- the picture: the 2025 Bronco Sport's Trail View tracks -------------------------------------------------------
// Each front tire's track as that screen draws it: a column of
// solid tread blocks as wide as the tire, parted by narrow stepped gaps, and one thin rail along the outboard side.
// All sizes in metres on the ground, so the picture is right at any distance and in any view once the camera is.
var LOOK = {
    start: 0.30,     // the first block begins this far ahead of the bumper
    blocks: 12,
    block: 0.27,     // a block's length along the track
    gap: 0.028,      // between blocks
    // A block is a rectangle, square across the tire, with two small triangle teeth along its edges, as on the 2025
    // screen. Each tooth rises gently away from the truck and drops back sharply; the next block's near edge
    // follows it, a little deeper, so the gap shows a small dark triangle at each tooth. The same on both tracks.
    // [across the tire 0..1 from the driver side, metres along the track]
    near: [[0, 0], [0.16, 0], [0.38, 0.024], [0.42, 0], [0.60, 0], [0.82, 0.024], [0.86, 0], [1, 0]],
    far:  [[0, 0], [0.16, 0], [0.40, 0.034], [0.42, 0], [0.60, 0], [0.84, 0.034], [0.86, 0], [1, 0]],
    lead: 0,         // how far the edge reaches back towards the truck: none, the rail begins with the first block
    railGap: 0.04,   // from the blocks' outboard edge to the rail (the 2025 rail is about a quarter of a block wide,
    rail: 0.065      // the rail's width                            nearer the blocks than its own width: frames 03, 06)
};

// The tracks for steering sw as closed outlines on the picture: {blocks: [[ [u,v], ... ], ...], rails: [...]}.
// An outline with a point outside what the lens sees is left out.
// The blocks' two long edges are the tire's own edges: cam.tw is the tire's measured width (sidewall to sidewall)
// and cam.tf the measured distance between the two front tires' middles, both written by the calibration from a
// tape measure on this truck. Without them the catalogue figures are used (235 mm, 1610 mm).
function overlay(sw, cam, look) {
    var k = look || LOOK, g = steerGeo(sw), out = { blocks: [], rails: [] };
    var TW = cam.tw > 0 ? cam.tw : TW0, TF = cam.tf > 0 ? cam.tf : TF0;
    // Where the tracks begin, when the calibration says so:
    //   start  the first block's near edge, metres ahead of the bumper: where the ground comes into view (Ford's 2025
    //          tracks begin at the bumper)
    //   back   how far back the tracks go on under the bumper (negative: behind the bumper's front). Those blocks are
    //          listed apart, in out.xray: ground the camera cannot see, drawn differently by the overlay
    //   vis    for this view or pane, where the ground comes into view if not at `start` (the split view's side panes
    //          see round the bumper's corners); a block boundary, so blocks line up across the panes
    var start = typeof cam.start === 'number' ? cam.start : k.start, vis = typeof cam.vis === 'number' ? cam.vis : start;
    var hasBack = typeof cam.back === 'number' && cam.back < start, pitch = k.block + k.gap;
    var nb = hasBack ? Math.ceil((start - cam.back) / pitch - 1e-9) : 0;
    if (hasBack) out.xray = [];
    function gp(x0, a, s) { return pathPt([x0 + a, 0], g, s); }
    function put(list, ground) {
        var px = projectRow(cam, ground);
        for (var i = 0; i < px.length; i++) if (!px[i]) return;
        list.push(px);
    }
    for (var side = -1; side <= 1; side += 2) {
        var x0 = side * TF / 2, s0 = FO + start, i, j;
        for (i = -nb; i < k.blocks; i++) {
            var sa = s0 + i * pitch, sb = sa + k.block, poly = [];
            for (j = 0; j < k.near.length; j++) poly.push(gp(x0, -TW / 2 + TW * k.near[j][0], sa + k.near[j][1]));
            for (j = k.far.length - 1; j >= 0; j--) poly.push(gp(x0, -TW / 2 + TW * k.far[j][0], sb + k.far[j][1]));
            put(sa - FO < vis - 1e-6 ? out.xray || [] : out.blocks, poly);
        }
        var end = s0 + k.blocks * pitch - k.gap, lead = k.lead, inner = side * (TW / 2 + k.railGap), outer = side * (TW / 2 + k.railGap + k.rail);
        function rail(list, from, to) {
            var n = Math.ceil((to - from) / 0.15), near = [], far = [];
            for (var q = 0; q <= n; q++) {
                var s = from + (to - from) * q / n;
                near.push(gp(x0, inner, s)); far.push(gp(x0, outer, s));
            }
            put(list, near.concat(far.reverse()));
        }
        rail(out.rails, FO + vis - lead, end);
        if (hasBack && vis > start - nb * pitch + 1e-6) rail(out.xray, s0 - nb * pitch - lead, FO + vis - lead);
    }
    return out;
}

// The calibration for a truck at another height (0 = stock on
// 235/65R17, up to 4 in by quarters). cam.lift is the lift (inches) the camera was measured at; a lift raises the
// lens by that much and changes nothing else (levelling is not modelled). No cam.lift or no setting: cam as it is.
function lifted(cam, liftIn) {
    if (!cam || typeof cam.lift !== 'number' || typeof liftIn !== 'number' || isNaN(liftIn)) return cam;
    var want = Math.max(0, Math.min(4, Math.round(liftIn * 4) / 4)), d = (want - cam.lift) * 0.0254;
    if (Math.abs(d) < 1e-9) return cam;
    var c = copyCam(cam);
    c.h = cam.h + d;
    if (cam.split && cam.split.panes) {
        c.split = { div: cam.split.div, rms: cam.split.rms, panes: [] };
        for (var p = 0; p < cam.split.panes.length; p++) { var q = copyCam(cam.split.panes[p]); q.h = cam.split.panes[p].h + d; c.split.panes.push(q); }
    }
    return c;
}

// The tracks for the view the camera module shows (its "camera showing" number: 8 front normal, 9 front split, 7 front
// 360, 1 front): {blocks, rails}, or null where there's nothing to draw (no split calibration yet, not a front view).
function overlayView(sw, cam, view, look) {
    if (view === 9) {
        if (!cam.split || !cam.split.panes || cam.split.panes.length !== 3) return null;
        var div = cam.split.div || DIV, W = (cam.size && cam.size[0]) || 800, b = [[0, div[0]], [div[0], div[1]], [div[1], W]];
        var all = { blocks: [], rails: [] }, kinds = ['blocks', 'rails'];
        if (typeof cam.back === 'number') { all.xray = []; kinds.push('xray'); }
        for (var p = 0; p < 3; p++) {
            var pc = copyCam(cam.split.panes[p]);
            pc.tw = cam.tw; pc.tf = cam.tf;
            if (typeof cam.start === 'number') pc.start = cam.start;
            if (typeof cam.back === 'number') pc.back = cam.back;
            var o = overlay(sw, pc, look);
            for (var k = 0; k < kinds.length; k++)
                for (var i = 0; i < (o[kinds[k]] || []).length; i++) {
                    var c = clipX(o[kinds[k]][i], b[p][0], b[p][1]);
                    if (c.length >= 3) all[kinds[k]].push(c);
                }
        }
        return all;
    }
    if (view === 8 || view === 7 || view === 1) return overlay(sw, cam, look);
    return null;
}
