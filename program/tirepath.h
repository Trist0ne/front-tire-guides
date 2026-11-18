/* tirepath.h: the front tires' tracks on the front camera picture, in C: the same arithmetic as
 * calibration/tirepath.js (the two agree outline by outline), plus a painter that fills
 * the outlines, anti-aliased, into a 32-bit picture. No QNX in here: plain C that builds anywhere. */
#ifndef TIREPATH_H
#define TIREPATH_H
#include <stddef.h>
#include <stdint.h>

struct tp_cam {   /* calibration/tirepath.js "the camera" */
    double h, z0, x0, pitch, yaw, roll, f, cx, cy, k1, k2, sx;
    int model;       /* 0 the wide-angle model, 1 a flat view ('rect': each pane of the split view) */
    double tw, tf;   /* this truck's measured tire width and distance between the front tires' middles (m); 0 = catalogue */
    int has_start, has_back;   /* frontcam.json "start", "back" (tirepath.js overlay): where the tracks begin, and how */
    double start, back;        /* far they go on under the bumper (those outlines are listed last: nmain .. n) */
};

#define TP_MAX_POLY 96   /* 12 blocks and a rail for each tire, in up to three panes */
#define TP_MAX_PT 72
struct tp_poly {
    int n;
    int id;   /* which outline this is, the same from one picture to the next (some are dropped or cut at an edge):
               * its place in the full list, plus 128 for each pane of the split view */
    double x[TP_MAX_PT], y[TP_MAX_PT];
};
struct tp_shape {
    int n, nblocks;   /* outlines; the first nblocks are blocks, then rails up to nmain, then the part under the bumper */
    int nmain;
    struct tp_poly p[TP_MAX_POLY];
};

/* frontcam.json as a whole: the normal view's camera, and the split view's three panes when measured (§1.11) */
struct tp_file {
    struct tp_cam cam;
    int has_split;
    double div[2];
    int width;
    struct tp_cam pane[3];
    int has_lift;      /* "lift": the lift (inches) the camera was measured at */
    double lift;
};

/* frontcam.json's text -> cam. 0 = all twelve numbers found and believable. */
int tp_cam_parse(const char *json, struct tp_cam *cam);
/* The tracks at steering sw (degrees at the wheel, + left) as outlines on the picture. */
void tp_overlay(double sw, const struct tp_cam *cam, struct tp_shape *out);
/* frontcam.json's text -> file: 0 when the normal view's camera is usable (the split view is optional). */
int tp_file_parse(const char *json, struct tp_file *file);
/* The tracks for the camera module's view (8 front normal, 9 front split, 7 front 360, 1 front), as tirepath.js's
 * overlayView: 0 when there's nothing to draw (split view not measured, not a front view). */
int tp_overlay_view(double sw, const struct tp_file *file, int view, struct tp_shape *out);
/* The calibration for a truck at another lift (inches, 0 to 4 by quarters), as tirepath.js lifted(): the lens that
 * much higher or lower, nothing else. Without "lift" in the file, or lift_in < 0: the file as it is. */
void tp_lifted(const struct tp_file *file, double lift_in, struct tp_file *out);
/* The truck, the look and the cameras (the normal view's, then the three panes' when measured) as JSON members
 * ("L":..,...,"cams":[...], no braces): what a drawer needs to make tp_overlay's picture itself. Returns the length. */
size_t tp_look_json(const struct tp_file *file, char *out, size_t cap);
/* Paint the outlines white with opacity ink (0..1) into px (w x h, stride bytes a row, 0xAARRGGBB words), which must
 * be clear where they go. premul: colour multiplied by alpha. box (x0, y0, x1, y1) receives what was touched
 * (x1 < x0 when nothing). */
void tp_paint(const struct tp_shape *s, uint32_t *px, int w, int h, int stride, double ink, int premul, int box[4]);
#endif
