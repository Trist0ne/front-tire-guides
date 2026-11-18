/* tirepath.c: see tirepath.h. Line for line the arithmetic of calibration/tirepath.js. */
#include "tirepath.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PI 3.14159265358979323846
static const double L = 2.670, TF0 = 1.610, TR = 1.595, TW0 = 0.235, FO = 0.856, LOCK = 501;
/* LOOK */
static const double K_START = 0.30, K_BLOCK = 0.27, K_GAP = 0.028, K_LEAD = 0.0, K_RAILGAP = 0.04, K_RAIL = 0.065;
enum { K_BLOCKS = 12, K_EDGE = 8 };
/* the saw-tooth edges of a block, as LOOK.near and LOOK.far in tirepath.js: {across the tire 0..1, metres along} */
static const double K_NEAR[K_EDGE][2] = { { 0, 0 }, { 0.16, 0 }, { 0.38, 0.024 }, { 0.42, 0 }, { 0.60, 0 }, { 0.82, 0.024 }, { 0.86, 0 }, { 1, 0 } };
static const double K_FAR[K_EDGE][2] = { { 0, 0 }, { 0.16, 0 }, { 0.40, 0.034 }, { 0.42, 0 }, { 0.60, 0 }, { 0.84, 0.034 }, { 0.86, 0 }, { 1, 0 } };

struct geo {
    double d, R, Rf;
    int sg;
};

static double dlock(void)
{
    double Rc = 11.40 / 2 - TW0 / 2, Rro = sqrt(Rc * Rc - L * L), R = Rro - TR / 2;
    return atan(L / R) * 180 / PI;
}

static struct geo steer_geo(double sw)
{
    struct geo g = { 0, 0, 0, 0 };
    double t = sw / LOCK, d = dlock() * (t < -1 ? -1 : t > 1 ? 1 : t);
    if (fabs(d) < 0.15) return g;
    g.d = d;
    g.R = L / tan(fabs(d) * PI / 180);
    g.sg = d > 0 ? 1 : -1;
    g.Rf = sqrt(g.R * g.R + L * L);
    return g;
}

static void path_pt(double px, double pz, const struct geo *g, double s, double out[2])
{
    if (!g->sg) {
        out[0] = px, out[1] = pz + s;
        return;
    }
    double cx = -g->sg * g->R, cz = -L, th = g->sg * s / g->Rf, vx = px - cx, vz = pz - cz;
    out[0] = cx + vx * cos(th) - vz * sin(th);
    out[1] = cz + vx * sin(th) + vz * cos(th);
}

static int project(const struct tp_cam *c, const double p[2], double *u, double *v)
{
    double D = PI / 180, X = p[0] - c->x0, Y = c->h, Z = p[1] - c->z0;
    double cp = cos(c->pitch * D), sp = sin(c->pitch * D), cyw = cos(c->yaw * D), syw = sin(c->yaw * D);
    double cr = cos(c->roll * D), sr = sin(c->roll * D);
    double x1 = X * cyw - Z * syw, z1 = X * syw + Z * cyw;
    double y2 = Y * cp - z1 * sp, z2 = Y * sp + z1 * cp;
    double x3 = x1 * cr + y2 * sr, y3 = -x1 * sr + y2 * cr;
    if (z2 <= 1e-6 && x3 * x3 + y3 * y3 < 1e-12) return 0;
    if (c->model == 1) {   /* a flat view: nothing at or behind its sideways plane */
        if (z2 < 0.34 * sqrt(x3 * x3 + y3 * y3 + z2 * z2)) return 0;   /* 70 deg off its axis at most (as tirepath.js) */
        double tx = x3 / z2, ty = y3 / z2, d = 1 + c->k1 * (tx * tx + ty * ty);
        *u = c->cx + c->sx * c->f * tx * d;
        *v = c->cy + c->f * ty * d;
        return 1;
    }
    double rxy = sqrt(x3 * x3 + y3 * y3), t = atan2(rxy, z2);
    if (t > 1.75) return 0;
    double r = c->f * (t + c->k1 * t * t * t + c->k2 * t * t * t * t * t);
    if (rxy < 1e-12) {
        *u = c->cx, *v = c->cy;
        return 1;
    }
    *u = c->cx + c->sx * r * x3 / rxy;
    *v = c->cy + r * y3 / rxy;
    return 1;
}

int tp_cam_parse(const char *json, struct tp_cam *cam)
{
    static const char *const names[12] = { "h", "z0", "x0", "pitch", "yaw", "roll", "f", "cx", "cy", "k1", "k2", "sx" };
    double *field[12] = { &cam->h, &cam->z0, &cam->x0, &cam->pitch, &cam->yaw, &cam->roll,
                          &cam->f, &cam->cx, &cam->cy, &cam->k1, &cam->k2, &cam->sx };
    for (int i = 0; i < 12; i++) {
        char key[16];
        size_t n = strlen(names[i]);
        key[0] = '"';
        memcpy(key + 1, names[i], n);
        key[n + 1] = '"', key[n + 2] = ':', key[n + 3] = 0;
        const char *p = strstr(json, key);
        if (!p) return -1;
        char *end;
        *field[i] = strtod(p + n + 3, &end);
        if (end == p + n + 3) return -1;
    }
    cam->model = strstr(json, "\"model\":\"rect\"") != NULL;
    cam->tw = cam->tf = 0;   /* the measured tire: optional, both or neither */
    const char *a = strstr(json, "\"tw\":"), *b = strstr(json, "\"tf\":");
    if (a && b) {
        double tw = strtod(a + 5, NULL), tf = strtod(b + 5, NULL);
        if (tw > 0.15 && tw < 0.40 && tf > 1.2 && tf < 2.1) cam->tw = tw, cam->tf = tf;
    }
    return cam->f > 0 && cam->h > 0.3 && cam->h < 1.6 && cam->sx > 0.3 && cam->sx < 3 ? 0 : -1;
}

/* One outline: its ground points projected; dropped whole if any point is outside what the lens sees. */
static void put(struct tp_shape *out, const struct tp_cam *cam, const double (*g)[2], int n, int id)
{
    if (out->n >= TP_MAX_POLY || n > TP_MAX_PT) return;
    struct tp_poly *p = &out->p[out->n];
    for (int i = 0; i < n; i++)
        if (!project(cam, g[i], &p->x[i], &p->y[i])) return;
    p->n = n, p->id = id;
    out->n++;
}

static void block(struct tp_shape *out, const struct tp_cam *cam, const struct geo *g, double x0, double TW, double sa, int id)
{
    double pts[TP_MAX_PT][2], sb = sa + K_BLOCK;
    int n = 0;
    for (int j = 0; j < K_EDGE; j++) path_pt(x0 - TW / 2 + TW * K_NEAR[j][0], 0, g, sa + K_NEAR[j][1], pts[n++]);
    for (int j = K_EDGE - 1; j >= 0; j--) path_pt(x0 - TW / 2 + TW * K_FAR[j][0], 0, g, sb + K_FAR[j][1], pts[n++]);
    put(out, cam, pts, n, id);
}

static void rail(struct tp_shape *out, const struct tp_cam *cam, const struct geo *g, double x0, double inner, double outer,
                 double from, double to, int id)
{
    double pts[TP_MAX_PT][2];
    int n = (int)ceil((to - from) / 0.15);
    if (2 * (n + 1) > TP_MAX_PT) n = TP_MAX_PT / 2 - 1;
    for (int i = 0; i <= n; i++) {
        double s = from + (to - from) * i / n;
        path_pt(x0 + inner, 0, g, s, pts[i]);
        path_pt(x0 + outer, 0, g, s, pts[2 * n + 1 - i]);
    }
    put(out, cam, pts, 2 * (n + 1), id);
}

void tp_overlay(double sw, const struct tp_cam *cam, struct tp_shape *out)
{
    struct geo g = steer_geo(sw);
    double TW = cam->tw > 0 ? cam->tw : TW0, TF = cam->tf > 0 ? cam->tf : TF0, pitch = K_BLOCK + K_GAP;
    double start = cam->has_start ? cam->start : K_START, s0 = FO + start;
    int has_back = cam->has_back && cam->back < start, nb = has_back ? (int)ceil((start - cam->back) / pitch - 1e-9) : 0;
    double end = s0 + K_BLOCKS * pitch - K_GAP;
    out->n = out->nblocks = out->nmain = 0;
    int id = 0;
    /* the order tirepath.js lists them: the blocks of both tires, the rails, then (each tire) the part under the bumper */
    for (int side = -1; side <= 1; side += 2)
        for (int i = 0; i < K_BLOCKS; i++) block(out, cam, &g, side * TF / 2, TW, s0 + i * pitch, id++);
    out->nblocks = out->n;
    for (int side = -1; side <= 1; side += 2)
        rail(out, cam, &g, side * TF / 2, side * (TW / 2 + K_RAILGAP), side * (TW / 2 + K_RAILGAP + K_RAIL), s0 - K_LEAD, end, id++);
    out->nmain = out->n;
    for (int side = -1; has_back && side <= 1; side += 2) {
        for (int i = -nb; i < 0; i++) block(out, cam, &g, side * TF / 2, TW, s0 + i * pitch, id++);
        rail(out, cam, &g, side * TF / 2, side * (TW / 2 + K_RAILGAP), side * (TW / 2 + K_RAILGAP + K_RAIL), s0 - nb * pitch - K_LEAD, s0 - K_LEAD, id++);
    }
}

/* Everything a drawer needs to make the same picture itself (the screen layer's shaders, GuidesOverlay.qml): the
 * truck, the look and the cameras as one line of JSON. The numbers are the ones tp_overlay uses, from here only. */
static size_t cam_json(char *out, size_t cap, size_t o, const struct tp_cam *c)
{
    return o + (size_t)snprintf(out + o, cap - o, "{\"model\":%d,\"h\":%.5f,\"z0\":%.5f,\"x0\":%.5f,\"pitch\":%.5f,\"yaw\":%.5f,\"roll\":%.5f,"
                                "\"f\":%.5f,\"cx\":%.4f,\"cy\":%.4f,\"k1\":%.6f,\"k2\":%.6f,\"sx\":%.6f}",
                                c->model, c->h, c->z0, c->x0, c->pitch, c->yaw, c->roll, c->f, c->cx, c->cy, c->k1, c->k2, c->sx);
}

size_t tp_look_json(const struct tp_file *file, char *out, size_t cap)
{
    const struct tp_cam *cam = &file->cam;
    double TW = cam->tw > 0 ? cam->tw : TW0, TF = cam->tf > 0 ? cam->tf : TF0, pitch = K_BLOCK + K_GAP;
    double start = cam->has_start ? cam->start : K_START;
    int has_back = cam->has_back && cam->back < start, nb = has_back ? (int)ceil((start - cam->back) / pitch - 1e-9) : 0;
    size_t o = (size_t)snprintf(out, cap, "\"L\":%.4f,\"lock\":%.2f,\"dlock\":%.6f,\"fo\":%.4f,\"tw\":%.4f,\"tf\":%.4f,\"start\":%.4f,\"nb\":%d,"
                                "\"blocks\":%d,\"block\":%.4f,\"gap\":%.4f,\"lead\":%.4f,\"railgap\":%.4f,\"rail\":%.4f,\"w\":%d,"
                                "\"split\":%d,\"div\":[%.2f,%.2f],", L, LOCK, dlock(), FO, TW, TF, start, nb, K_BLOCKS, K_BLOCK, K_GAP, K_LEAD,
                                K_RAILGAP, K_RAIL, file->width, file->has_split, file->div[0], file->div[1]);
    for (int k = 0; k < 2; k++) {
        o += (size_t)snprintf(out + o, cap - o, "\"%s\":[", k ? "far" : "near");
        for (int j = 0; j < K_EDGE; j++)
            o += (size_t)snprintf(out + o, cap - o, "%s[%.4f,%.4f]", j ? "," : "", (k ? K_FAR : K_NEAR)[j][0], (k ? K_FAR : K_NEAR)[j][1]);
        o += (size_t)snprintf(out + o, cap - o, "],");
    }
    o += (size_t)snprintf(out + o, cap - o, "\"cams\":[");
    o = cam_json(out, cap, o, cam);
    for (int p = 0; file->has_split && p < 3; p++) {
        out[o++] = ',';
        o = cam_json(out, cap, o, &file->pane[p]);
    }
    o += (size_t)snprintf(out + o, cap - o, "]");
    return o;
}

/* ---- the split view (tirepath.js overlayView) ---- */

/* Copies the text of the object starting at the first '{' at or after p, braces balanced. */
static const char *object_at(const char *p, char *buf, size_t cap)
{
    p = strchr(p, '{');
    if (!p) return NULL;
    int depth = 0;
    size_t n = 0;
    for (const char *q = p; *q; q++) {
        if (n + 1 >= cap) return NULL;
        buf[n++] = *q;
        if (*q == '{') depth++;
        if (*q == '}' && --depth == 0) {
            buf[n] = 0;
            return q + 1;
        }
    }
    return NULL;
}

int tp_file_parse(const char *json, struct tp_file *file)
{
    char normal[4096], one[1024];
    memset(file, 0, sizeof *file);
    file->width = 800;
    const char *sp = strstr(json, "\"split\"");
    size_t n = sp ? (size_t)(sp - json) : strlen(json);
    if (n >= sizeof normal) return -1;
    memcpy(normal, json, n);
    normal[n] = 0;
    if (tp_cam_parse(normal, &file->cam)) return -1;
    file->cam.model = 0;
    const char *sz = strstr(normal, "\"size\":[");
    if (sz) file->width = atoi(sz + 8) > 0 ? atoi(sz + 8) : 800;
    const char *q;
    /* (these follow the split part in the file; no pane has them) */
    if ((q = strstr(json, "\"start\":"))) file->cam.has_start = 1, file->cam.start = strtod(q + 8, NULL);
    if ((q = strstr(json, "\"back\":"))) file->cam.has_back = 1, file->cam.back = strtod(q + 7, NULL);
    q = strstr(json, "\"lift\":");   /* (written last, after the split part) */
    if (q) file->has_lift = 1, file->lift = strtod(q + 7, NULL);
    if (!sp) return 0;
    const char *d = strstr(sp, "\"div\":[");
    file->div[0] = 267, file->div[1] = 533;
    if (d) {
        char *e;
        file->div[0] = strtod(d + 7, &e);
        if (*e == ',') file->div[1] = strtod(e + 1, NULL);
    }
    const char *p = strstr(sp, "\"panes\":[");
    for (int i = 0; p && i < 3; i++) {
        p = object_at(p, one, sizeof one);
        if (!p || tp_cam_parse(one, &file->pane[i])) return 0;   /* (a broken split part: the normal view still draws) */
        file->pane[i].tw = file->cam.tw, file->pane[i].tf = file->cam.tf;
        file->pane[i].has_start = file->cam.has_start, file->pane[i].start = file->cam.start;
        file->pane[i].has_back = file->cam.has_back, file->pane[i].back = file->cam.back;
    }
    file->has_split = p != NULL && file->div[0] > 0 && file->div[1] > file->div[0];
    return 0;
}

/* Sutherland-Hodgman against u >= x (above) or u <= x: the same arithmetic as tirepath.js clipX. */
static int clip_edge(const double *ix, const double *iy, int n, double x, int above, double *ox, double *oy)
{
    int m = 0;
    for (int i = 0; i < n && m < TP_MAX_PT - 1; i++) {
        int j = (i + 1) % n, ina = above ? ix[i] >= x : ix[i] <= x, inb = above ? ix[j] >= x : ix[j] <= x;
        if (ina) ox[m] = ix[i], oy[m++] = iy[i];
        if (ina != inb && m < TP_MAX_PT) {
            double t = (x - ix[i]) / (ix[j] - ix[i]);
            ox[m] = x, oy[m++] = iy[i] + t * (iy[j] - iy[i]);
        }
    }
    return m;
}

static void put_clipped(struct tp_shape *out, const struct tp_poly *p, double lo, double hi, int pane)
{
    double ax[TP_MAX_PT], ay[TP_MAX_PT];
    if (out->n >= TP_MAX_POLY) return;
    int m = clip_edge(p->x, p->y, p->n, lo, 1, ax, ay);
    if (!m) return;
    struct tp_poly *q = &out->p[out->n];
    q->n = clip_edge(ax, ay, m, hi, 0, q->x, q->y);
    q->id = p->id + 128 * pane;
    if (q->n >= 3) out->n++;
}

int tp_overlay_view(double sw, const struct tp_file *file, int view, struct tp_shape *out)
{
    out->n = out->nblocks = out->nmain = 0;
    if (view == 8 || view == 7 || view == 1) {
        tp_overlay(sw, &file->cam, out);
        return 1;
    }
    if (view != 9 || !file->has_split) return 0;
    static struct tp_shape pane[3];
    double b[3][2] = { { 0, file->div[0] }, { file->div[0], file->div[1] }, { file->div[1], file->width } };
    for (int p = 0; p < 3; p++) tp_overlay(sw, &file->pane[p], &pane[p]);
    /* every pane's blocks, then every pane's rails, then every pane's part under the bumper: tirepath.js's order */
    for (int p = 0; p < 3; p++)
        for (int i = 0; i < pane[p].nblocks; i++) put_clipped(out, &pane[p].p[i], b[p][0], b[p][1], p);
    out->nblocks = out->n;
    for (int p = 0; p < 3; p++)
        for (int i = pane[p].nblocks; i < pane[p].nmain; i++) put_clipped(out, &pane[p].p[i], b[p][0], b[p][1], p);
    out->nmain = out->n;
    for (int p = 0; p < 3; p++)
        for (int i = pane[p].nmain; i < pane[p].n; i++) put_clipped(out, &pane[p].p[i], b[p][0], b[p][1], p);
    return 1;
}

void tp_lifted(const struct tp_file *file, double lift_in, struct tp_file *out)
{
    *out = *file;
    if (!file->has_lift || !(lift_in >= 0)) return;
    double want = floor(lift_in * 4 + 0.5) / 4;
    if (want > 4) want = 4;
    if (want < 0) want = 0;
    double d = (want - file->lift) * 0.0254;
    out->cam.h = file->cam.h + d;
    for (int p = 0; p < 3; p++) out->pane[p].h = file->pane[p].h + d;
}

/* ---- the painter: even-odd fill, four sample rows a pixel, exact coverage along each row ---------------------- */
enum { SUB = 4 };

void tp_paint(const struct tp_shape *s, uint32_t *px, int w, int h, int stride, double ink, int premul, int box[4])
{
    uint16_t *acc = calloc((size_t)w + 2, sizeof *acc);   /* coverage of the row being filled, 0..SUB*256 */
    box[0] = w, box[1] = h, box[2] = -1, box[3] = -1;
    if (!acc) return;
    int A = (int)(ink * 256 + 0.5);
    for (int k = 0; k < s->n; k++) {
        const struct tp_poly *p = &s->p[k];
        double ly = 1e9, hy = -1e9;
        for (int i = 0; i < p->n; i++) {
            if (p->y[i] < ly) ly = p->y[i];
            if (p->y[i] > hy) hy = p->y[i];
        }
        int y0 = (int)floor(ly), y1 = (int)floor(hy);
        if (y0 < 0) y0 = 0;
        if (y1 > h - 1) y1 = h - 1;
        for (int y = y0; y <= y1; y++) {
            int lo = w, hi = -1;
            for (int sub = 0; sub < SUB; sub++) {
                double yc = y + (sub + 0.5) / SUB, xs[TP_MAX_PT];
                int nx = 0;
                for (int i = 0; i < p->n; i++) {
                    int j = (i + 1) % p->n;
                    if ((p->y[i] <= yc) == (p->y[j] <= yc)) continue;
                    xs[nx++] = p->x[i] + (yc - p->y[i]) * (p->x[j] - p->x[i]) / (p->y[j] - p->y[i]);
                }
                for (int a = 1; a < nx; a++) {   /* a handful of crossings: insertion sort */
                    double v = xs[a];
                    int b = a - 1;
                    for (; b >= 0 && xs[b] > v; b--) xs[b + 1] = xs[b];
                    xs[b + 1] = v;
                }
                for (int a = 0; a + 1 < nx; a += 2) {
                    double xa = xs[a] < 0 ? 0 : xs[a], xb = xs[a + 1] > w ? w : xs[a + 1];
                    if (xb <= xa) continue;
                    int ia = (int)xa, ib = (int)xb;
                    if (ib >= w) ib = w - 1, xb = w;
                    if (ia == ib) acc[ia] += (uint16_t)((xb - xa) * 256);
                    else {
                        acc[ia] += (uint16_t)((ia + 1 - xa) * 256);
                        for (int x = ia + 1; x < ib; x++) acc[x] += 256;
                        acc[ib] += (uint16_t)((xb - ib) * 256);
                    }
                    if (ia < lo) lo = ia;
                    if (ib > hi) hi = ib;
                }
            }
            if (hi < lo) continue;
            uint32_t *row = (uint32_t *)((uint8_t *)px + (size_t)y * (size_t)stride);
            for (int x = lo; x <= hi; x++) {
                int cov = acc[x] > SUB * 256 ? SUB * 256 : acc[x], a = cov * A / (SUB * 256);   /* 0..256 */
                acc[x] = 0;
                if (a <= 0) continue;
                int old = (int)(row[x] >> 24);   /* outlines never overlap; where edges meet in a pixel, the larger wins */
                int al = a >= 256 ? 255 : a;
                if (al <= old) continue;
                int c = premul ? al : 255;
                row[x] = (uint32_t)al << 24 | (uint32_t)c << 16 | (uint32_t)c << 8 | (uint32_t)c;
            }
            if (lo < box[0]) box[0] = lo;
            if (hi > box[2]) box[2] = hi;
            if (y < box[1]) box[1] = y;
            if (y > box[3]) box[3] = y;
        }
    }
    free(acc);
}
