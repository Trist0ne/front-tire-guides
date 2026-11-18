#!/usr/bin/env node
// Front camera calibration: ground marks -> frontcam.json (the numbers the guides are drawn with).
//   node calibrate.js marks.txt [frontcam.json] --tire <m> --outer <m> [--height <m>] [--size 800x480]
// --height: the lens's height above the ground (tape measure). Needed when the marks only cover the strip between the
// guides: they can't tell the camera's height from its lens, and the turning tracks depend on it.
// --lens-ahead: the lens's distance ahead of the front axle (m), held as well; give it with line marks far to the side.
// A marks-file line "line <x> <ahead> <x> <ahead> <u> <v>" is a measured straight line on the ground (two points on it)
// and one picture point on it (a painted road edge): it counts as a line, not as one of the 12 marks.
// --tire: one front tire's width, sidewall to sidewall, in metres. --outer: from the outer sidewall of one front tire
// to the outer sidewall of the other, wheels straight. Both with a tape on this truck: the tracks' edges are drawn
// from them, so they are the tires' real edges and not the catalogue's.
// marks.txt, one mark a line (# starts a comment):
//   <metres to the passenger side of the truck's centreline, driver side negative>
//   <metres ahead of the front bumper's foremost point>
//   <the mark's x on the screen picture, pixels from the left>  <its y, pixels from the top>
// Screen pixels are those of SYNC's 800 x 480 screen (read them off a straight-on photo of the screen scaled to
// 800 x 480, or off a screenshot). At least 12 marks, spread over the whole area the tracks cover: near (0.5 m) to
// far (6 m+), centre and both sides. Prints each mark's error; writes the file only if the fit is good.
//
// The front split view, after the normal view is done:
//   node calibrate.js --split marks_split.txt frontcam.json
// The same marks, read off a photo of the split view; a line "div <x> <x>" gives the two
// dividers. Needs 6 marks in each pane. Adds the three panes to frontcam.json; the normal view's numbers stay.
var fs = require('fs');
function say(s) { process.stdout.write(s + '\n'); }
var src = fs.readFileSync(__dirname + '/tirepath.js', 'utf8').replace('.pragma library', '');
var T = {};
new Function('exports', src + '\n["calibrate","project","FO","NAMES","nearestOnLine"].forEach(function(n){exports[n]=eval(n);});')(T);
var args = process.argv.slice(2), size = [800, 480], files = [], tire = 0, outer = 0, split = false, lensH = 0, lensZ = 0;
new Function('exports', src + '\n["calibrateSplit","paneOf","DIV"].forEach(function(n){exports[n]=eval(n);});')(T);
for (var i = 0; i < args.length; i++) {
    if (args[i] === '--split') split = true;
    else if (args[i] === '--size') size = args[++i].split('x').map(Number);
    else if (args[i] === '--tire') tire = Number(args[++i]);
    else if (args[i] === '--outer') outer = Number(args[++i]);
    else if (args[i] === '--height') lensH = Number(args[++i]);
    else if (args[i] === '--lens-ahead') lensZ = Number(args[++i]);
    else files.push(args[i]);
}
if (!files.length) { console.error('usage: node calibrate.js marks.txt [frontcam.json] --tire <m> --outer <m> [--size 800x480]'); process.exit(2); }
if (split) { splitMain(); process.exit(0); }
if (files[1] && !(tire > 0.15 && tire < 0.40 && outer > 1.5 && outer < 2.3 && outer > 4 * tire)) {
    console.error('give the measured --tire width (0.15 to 0.40 m) and --outer distance across both front tires (1.5 to 2.3 m)'); process.exit(2);
}
function pad(t, n) { while (t.length < n) t += ' '; return t; }

function splitMain() {
    if (files.length < 2) { console.error('usage: node calibrate.js --split marks_split.txt frontcam.json'); process.exit(2); }
    var base;
    try { base = JSON.parse(fs.readFileSync(files[1], 'utf8')); } catch (e) { console.error('the normal view first: ' + files[1] + ' not readable'); process.exit(2); }
    if (!(base.f > 0 && base.h > 0)) { console.error(files[1] + ' has no normal-view camera: calibrate the normal view first'); process.exit(2); }
    var m = [], div = T.DIV.slice();
    fs.readFileSync(files[0], 'utf8').split('\n').forEach(function (l, n) {
        l = l.replace(/#.*/, '').trim();
        if (!l) return;
        if (l.search(/^div\b/) === 0) { div = l.split(/[\s,]+/).slice(1, 3).map(Number); return; }
        if (l.search(/^line\b/) === 0) {   // a measured straight line and one picture point on it, as for the normal view
            var q = l.split(/[\s,]+/).slice(1).map(Number);
            if (q.length < 6 || q.some(isNaN)) { console.error('line ' + (n + 1) + ': a line mark needs 6 numbers'); process.exit(2); }
            m.push({ line: [[q[0], T.FO + q[1]], [q[2], T.FO + q[3]]], u: q[4], v: q[5] });
            return;
        }
        var f = l.split(/[\s,]+/).map(Number);
        if (f.length < 4 || f.some(isNaN)) { console.error('line ' + (n + 1) + ': need 4 numbers'); process.exit(2); }
        m.push({ x: f[0], z: T.FO + f[1], u: f[2], v: f[3], ahead: f[1] });
    });
    if (!(div[0] > 100 && div[1] > div[0] + 100 && div[1] < size[0] - 100)) { console.error('dividers ' + div + ' are not believable'); process.exit(2); }
    var counts = [0, 1, 2].map(function (p) { return m.filter(function (k) { return T.paneOf(k.u, div) === p; }).length; });
    say('marks in the panes (left, centre, right): ' + counts.join(', '));
    var r = T.calibrateSplit(m, base, div, size[0]);
    if (!r) { say('NOT written: each pane needs 6 marks. Lay out more near the front corners.'); process.exit(1); }
    say('pane     marks  typical  worst  looks (deg)');
    ['left', 'centre', 'right'].forEach(function (nm, p) {
        var q = r.panes[p];
        say(pad(nm, 9) + pad(String(q.n), 7) + pad(q.rms.toFixed(2), 9) + pad(q.worst.toFixed(2), 7) + q.cam.yaw.toFixed(0) + ' sideways, ' + q.cam.pitch.toFixed(0) + ' down');
    });
    m.forEach(function (k) {
        var p = T.paneOf(k.u, div), c = r.panes[p].cam, q = k.line ? T.nearestOnLine(c, k) : T.project(c, [k.x, k.z]);
        var e = q ? Math.hypot(q[0] - k.u, q[1] - k.v) : 999;
        if (e > 6) say('  ' + (k.line ? 'line point ' + k.u.toFixed(0) + ',' + k.v.toFixed(0) : k.x.toFixed(2) + ', ' + k.ahead.toFixed(2)) + ' off by ' + e.toFixed(1) + ' px   <-- check this mark');
    });
    var good = r.rms <= 3 && r.worst <= 8;
    if (!good) { say('NOT written: the fit is poor. Check the marks flagged above.'); process.exit(1); }
    base.split = { div: div, rms: +r.rms.toFixed(2), panes: r.panes.map(function (q) {
        var o = { model: 'rect' };
        T.NAMES.forEach(function (n) { o[n] = +q.cam[n].toFixed(5); });
        return o;
    }) };
    fs.writeFileSync(files[1], JSON.stringify(base) + '\n');
    say('written: the split view added to ' + files[1] + '  (copy to /fs/rwdata/frontguides/frontcam.json on SYNC)');
}
var marks = [];
fs.readFileSync(files[0], 'utf8').split('\n').forEach(function (l, n) {
    l = l.replace(/#.*/, '').trim();
    if (!l) return;
    if (l.search(/^line\b/) === 0) {   // line <x> <ahead> <x> <ahead> <u> <v>: a measured straight line, one picture point on it
        var q = l.split(/[\s,]+/).slice(1).map(Number);
        if (q.length < 6 || q.some(isNaN)) { console.error('line ' + (n + 1) + ': a line mark needs 6 numbers'); process.exit(2); }
        marks.push({ line: [[q[0], T.FO + q[1]], [q[2], T.FO + q[3]]], u: q[4], v: q[5] });
        return;
    }
    var f = l.split(/[\s,]+/).map(Number);
    if (f.length < 4 || f.some(isNaN)) { console.error('line ' + (n + 1) + ': need 4 numbers'); process.exit(2); }
    marks.push({ x: f[0], z: T.FO + f[1], u: f[2], v: f[3], ahead: f[1] });
});
var points = marks.filter(function (m) { return !m.line; }).length;
if (points < 12) { console.error('only ' + points + ' marks: at least 12 are needed'); process.exit(2); }
if (lensH && !(lensH > 0.3 && lensH < 1.6)) { console.error('--height is the lens above the ground in metres (0.3 to 1.6)'); process.exit(2); }
if (lensZ && !(lensZ > 0.2 && lensZ < 1.5)) { console.error('--lens-ahead is metres ahead of the front axle (0.2 to 1.5)'); process.exit(2); }
var r = T.calibrate(marks, size[0], size[1], lensH, lensZ);
say('mark (side m, ahead m)   picture px     fitted px      off by');
marks.forEach(function (m) {
    if (m.line) {
        var lp = T.nearestOnLine(r.cam, m), le = Math.hypot(lp[0] - m.u, lp[1] - m.v);
        say(pad('  on a measured line', 25) + pad(m.u.toFixed(0) + ',' + m.v.toFixed(0), 15) + pad(lp[0].toFixed(1) + ',' + lp[1].toFixed(1), 15) + le.toFixed(1) + (le > 6 ? '   <-- check this mark' : ''));
        return;
    }
    var p = T.project(r.cam, [m.x, m.z]), e = Math.hypot(p[0] - m.u, p[1] - m.v);
    say(pad('  ' + m.x.toFixed(2) + ', ' + m.ahead.toFixed(2), 25) + pad(m.u.toFixed(0) + ',' + m.v.toFixed(0), 15) +
                pad(p[0].toFixed(1) + ',' + p[1].toFixed(1), 15) + e.toFixed(1) + (e > 6 ? '   <-- check this mark' : ''));
});
say('\nfit: ' + r.rms.toFixed(2) + ' px typical, ' + r.worst.toFixed(2) + ' px worst over ' + marks.length + ' marks');
say('camera: ' + r.cam.h.toFixed(2) + ' m above the ground, ' + (r.cam.z0 - T.FO).toFixed(2) + ' m ahead of the bumper line (negative = behind it), tipped down ' +
            r.cam.pitch.toFixed(1) + ' deg');
var good = r.rms <= 3 && r.worst <= 8 && r.cam.h > 0.3 && r.cam.h < 1.6 && r.cam.pitch > 0 && r.cam.pitch < 70;
if (!good) { say('NOT written: the fit is poor or the camera it found is not believable. Check the marks flagged above.'); process.exit(1); }
if (files[1]) {
    var o = { size: size, marks: marks.length, rms: +r.rms.toFixed(2) };
    T.NAMES.forEach(function (n) { o[n] = +r.cam[n].toFixed(5); });
    o.tw = +tire.toFixed(4); o.tf = +(outer - tire).toFixed(4);
    fs.writeFileSync(files[1], JSON.stringify(o) + '\n');
    say('tires: ' + (o.tw * 1000).toFixed(0) + ' mm wide, middles ' + (o.tf * 1000).toFixed(0) + ' mm apart');
    say('written: ' + files[1] + '  (copy to /fs/rwdata/frontguides/frontcam.json on SYNC)');
}
