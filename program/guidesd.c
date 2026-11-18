/* guidesd: the program behind Front Tire Guides on SYNC 3 (QNX 6.5).
 *
 * It takes two things from SYNC's vehicle-data service (VS_CANShadow): the steering angle and which camera view is
 * showing. While a front view is up it hands the screen layer (screen/GuidesLayer.qml) what it needs to draw the
 * guides, in the run folder (/fs/tmpfs/frontguides):
 *
 *   look.json   the truck, the look of the guides and the camera calibration with the lift setting applied. About
 *               1 kB, written when the calibration, the lift setting or the lines' brightness or transparency changes.
 *   sw.pbm, st.pbm, sf.pbm
 *               the steering to show, 30 times a second, as the SIZES of three empty one-bit pictures (see
 *               "The picture channel" below).
 *
 * Settings come from the settings folder (/fs/rwdata/frontguides): frontcam.json (calibration), lift.json (the Lift
 * Offset slider), brightness.json and transparency.json (the two line sliders) and switch.json (the Tire Guides
 * switch).
 *
 * It sends nothing to the truck: its only request is a subscription to SYNC's own copy of two CAN messages. */
#include <math.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "mc.h"
#include "tirepath.h"

/* ---- SYNC's vehicle-data service -------------------------------------------------------------------------------
 * A subscription names messages as bus << 16 | CAN id and how often to send them. Layouts are the service's own
 * structs for SYNC 3.4 (the same in builds 22110 to 26057). */
#define CS_SERVICE "VS_CANShadow"
#define CS_CMD_SUBSCRIBE 0x543f
#define CS_EVERY_FRAME 0           /* each frame as it comes off the bus */
#define CS_ON_CHANGE 1             /* the whole message when it changes */
#define MSG_STEERING 0x2007D       /* pinion steering angle: float degrees at byte 16, about 10 a second */
#define MSG_CAMERA 0x203EE         /* the camera module's reports: {u8 value[2], u8 feature[2], ...} */
#define FEATURE_VIEW 0x81b         /* ...this feature is the view showing: 0 off, 5 rear, 8 front, 9 front split */
#define CS_MAX_MSGS 50
#define CS_MAX_SIGS 15

struct cs_entry {
    uint32_t msg, mode;
    uint8_t nsig, pad[3];
    uint32_t sig[CS_MAX_SIGS];
};
struct cs_request {
    uint8_t count, pad[3];
    struct cs_entry e[CS_MAX_MSGS];
};

static char run_dir[200] = "/fs/tmpfs/frontguides", settings_dir[200] = "/fs/rwdata/frontguides";
static const char *queue_name = "FRONT_TIRE_GUIDES";
static volatile sig_atomic_t stop;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;   /* the steering and camera state below */

static uint64_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Writes a file whole: to a temporary name, then renamed over the old one, so a reader never sees half of it. */
static void put_file(const char *name, const void *data, size_t n)
{
    char tmp[256], path[256];
    snprintf(tmp, sizeof(tmp), "%s/%s.tmp", run_dir, name);
    snprintf(path, sizeof(path), "%s/%s", run_dir, name);
    FILE *f = fopen(tmp, "wb");
    if (!f) return;
    fwrite(data, 1, n, f);
    fclose(f);
    if (rename(tmp, path)) unlink(tmp);
}

/* ---- the steering as the guides show it ------------------------------------------------------------------------
 * SYNC hands over a steering value about every 0.1 s, and not evenly: values are sometimes held up on the way and
 * then arrive together. Drawn as they come, the guides would stall and jump. So:
 *  - each value is given the time it was MEASURED, not the time it arrived: the values are a steady beat, and a
 *    late one is late by what it exceeds that beat (steer_seen);
 *  - the shown steering aims at the last value carried on at the rate the wheel was turning, for as long as that
 *    value is old (FOLLOW_CARRY at most), so a late value changes nothing;
 *  - a value that arrives unchanged says the wheel has stopped: the rate goes to nothing;
 *  - it follows that aim like a weight on a spring, so neither its place nor its speed ever jumps;
 *  - a wheel that stops is only known to have stopped when the next value comes, so the shown steering runs a
 *    little past it. It then comes back gently (a weaker spring, FOLLOW_BACK, while the wheel is slowing and the aim
 *    is behind it), and it is never shown past the furthest the wheel has been seen to turn each way, so nothing
 *    overruns at full lock. */
#define FOLLOW_W 25.0        /* the spring, 1/s (critically damped) */
#define FOLLOW_BACK 11.0     /* the weaker spring for coming back after running past */
#define FOLLOW_RATE 0.06     /* s: a rising turning rate is eased in over this */
#define FOLLOW_STOP 0.03     /* s: a falling one over this: quicker to stop than to start */
#define FOLLOW_CARRY 0.25    /* s: how long the last value is carried on at its rate when the next is late */

static double steer_v, steer_rate;               /* the last value, and the wheel's rate at it (deg/s) */
static uint64_t steer_t;                         /* when that value was measured, on our clock */
static double steer_hi = 480, steer_lo = -470;   /* the furthest seen each way; starts inside any truck's locks */
static int steer_way, steer_slow, steer_have;    /* the way it last turned; slowing or stopped; any value yet */
static int cam_view;                             /* the camera view showing */
static uint64_t heard_t;                         /* when anything last came from the service */

static void steer_seen(double v, uint64_t t)   /* (lock held) t: when it arrived */
{
    static double last, period = 100, at, had;
    static uint64_t last_t;
    static int have;
    if (!have || t - last_t > 1000) {          /* the first value, or the first after a silence */
        have = 1, last = v, last_t = t, at = (double)t;
        steer_v = v, steer_t = t, steer_rate = 0, steer_have = 1;
        return;
    }
    /* the beat: the average time between values, followed slowly */
    period += ((double)(t - last_t) - period) * 0.02;
    if (period < 60) period = 60;
    if (period > 150) period = 150;
    /* measured one beat after the one before; never after it arrived, never more than 200 ms before that */
    at += period;
    if (at > (double)t) at = (double)t;
    if (at < (double)t - 200) at = (double)t - 200;
    steer_rate = (v - last) / period * 1000.0;
    had = fabs(steer_rate) > had * 0.9 ? fabs(steer_rate) : had * 0.9;   /* the rate it had lately */
    steer_slow = fabs(steer_rate) < 0.5 * had || steer_rate == 0;
    if (v > last) steer_way = 1;
    if (v < last) steer_way = -1;
    if (v > steer_hi && v < 560) steer_hi = v;
    if (v < steer_lo && v > -560) steer_lo = v;
    last = v, last_t = t;
    steer_v = v, steer_t = (uint64_t)at;
}

struct follow {
    int on;
    double rs, shown, vel;   /* the eased rate; the steering shown and its speed */
    uint64_t at;
};

/* Advances the shown steering to `now`, in steps of 5 ms at most, so the result does not depend on how often it is
 * asked. */
static double follow_step(struct follow *f, double v, double rate, uint64_t v_t, uint64_t now, int way, int slow,
                          double lo, double hi)
{
    double left = (double)(now - f->at) / 1000.0;
    if (!f->on || left > 0.5) {   /* the first step, or the first after a pause: start from the value itself */
        f->on = 1, f->rs = f->vel = 0, f->shown = v, f->at = now;
        return v;
    }
    double age = ((double)f->at - (double)v_t) / 1000.0;
    while (left > 1e-9) {
        double h = left > 0.005 ? 0.005 : left;
        age += h, left -= h;
        double r = age > 0.4 ? 0 : rate;    /* no value for 0.4 s: the wheel is taken as still */
        f->rs += (r - f->rs) * (1 - exp(-h / (fabs(r) < fabs(f->rs) ? FOLLOW_STOP : FOLLOW_RATE)));
        double target = v + f->rs * (age > FOLLOW_CARRY ? FOLLOW_CARRY : age < 0 ? 0 : age);
        if (target > hi) target = hi;
        if (target < lo) target = lo;
        double k = slow && (target - f->shown) * way < 0 ? FOLLOW_BACK : FOLLOW_W;
        double acc = k * k * (target - f->shown) + 2 * FOLLOW_W * (f->rs - f->vel);
        f->vel += acc * h, f->shown += f->vel * h;
        if (f->shown > hi) { f->shown = hi; if (f->vel > 0) f->vel = 0; }
        if (f->shown < lo) { f->shown = lo; if (f->vel < 0) f->vel = 0; }
    }
    f->at = now;
    return f->shown;
}

/* ---- settings and the look -------------------------------------------------------------------------------------
 * The settings folder is on SYNC's flash, and a read can take a long time while SYNC is busy starting up. So it is
 * read from a thread of its own (settings_thread), never from the thread that keeps the beat. */
static struct tp_file cal, cal_lifted;   /* the calibration as measured, and with the lift setting applied */
static int cal_ok;
static double lift_in;
static double line_bright = 0.95, line_ink = 0.85;   /* the lines' brightness (white = 1) and opacity (0.2 to 1) */
static unsigned look_id;                 /* new with every look.json written (0: none yet) */
static int look_split;                   /* the calibration has the split view */
static volatile int guides_off;          /* the Tire Guides switch */

static size_t read_small(const char *name, char *text, size_t cap)
{
    char path[256];
    snprintf(path, sizeof(path), "%s/%s", settings_dir, name);
    FILE *f = fopen(path, "r");
    size_t n = f ? fread(text, 1, cap - 1, f) : 0;
    if (f) fclose(f);
    text[n] = 0;
    return n;
}

/* <name>.json, {"<name>": 55}: a whole percentage from lo to hi; no file, or anything else in it: def. */
static double percent_setting(const char *name, double lo, double hi, double def)
{
    char file[40], key[40], small[96];
    snprintf(file, sizeof(file), "%s.json", name);
    snprintf(key, sizeof(key), "\"%s\"", name);
    if (!read_small(file, small, sizeof(small))) return def;
    const char *q = strstr(small, key);
    if (!q || !(q = strchr(q, ':'))) return def;
    double v = strtod(q + 1, NULL);
    return v >= lo && v <= hi ? v : def;
}

static void settings_load(void)
{
    static char text[8192];
    static long cal_size = -1, cal_mtime;
    char path[256], small[96];
    struct stat st;
    snprintf(path, sizeof(path), "%s/frontcam.json", settings_dir);
    if (stat(path, &st)) cal_ok = 0, cal_size = -1;
    else if ((long)st.st_size != cal_size || (long)st.st_mtime != cal_mtime) {
        cal_ok = read_small("frontcam.json", text, sizeof(text)) > 0 && !tp_file_parse(text, &cal);
        cal_size = (long)st.st_size, cal_mtime = (long)st.st_mtime;
    }
    double lift = 0;   /* no lift.json: stock height */
    if (read_small("lift.json", small, sizeof(small))) {
        const char *q = strstr(small, "\"lift\"");
        if (q && (q = strchr(q, ':'))) lift = strtod(q + 1, NULL);
        if (!(lift >= 0 && lift <= 4)) lift = 0;
    }
    lift_in = lift;
    /* "Line Brightness" (70 to 100 % of white, no file: 95) and "Line Transparency" (0 to 50 %, no file: 15): the
     * standard sits a little inside each range, so there is room both ways. The ranges end where the lines stop
     * being of use over a camera picture (rendered 11-17: under 70 % they are grey, past 50 % hard to see). */
    line_bright = percent_setting("brightness", 70, 100, 95) / 100;
    line_ink = 1 - percent_setting("transparency", 0, 50, 15) / 100;
    if (cal_ok) tp_lifted(&cal, lift_in, &cal_lifted);
}

/* The Tire Guides switch: {"guides": false} in switch.json is off; no file, or anything else in it, is on. */
static int switch_off(void)
{
    char text[256];
    if (!read_small("switch.json", text, sizeof(text))) return 0;
    const char *p = strstr(text, "\"guides\"");
    if (!p) return 0;
    p += 8;
    while (*p == ' ' || *p == ':') p++;
    return !strncmp(p, "false", 5);
}

static void write_look(void)
{
    static char out[8192];
    static unsigned seed;
    if (!seed) seed = (unsigned)time(NULL) % 100000 * 10 + 1;   /* so an earlier run's look is never taken for this one's */
    unsigned id = look_id ? look_id + 1 : seed;
    size_t o = (size_t)snprintf(out, sizeof(out), "{\"k\":%u,\"lift\":%.2f,\"bright\":%.2f,\"ink\":%.2f,", id, lift_in, line_bright, line_ink);
    o += tp_look_json(&cal_lifted, out + o, sizeof(out) - o - 8);
    o += (size_t)snprintf(out + o, sizeof(out) - o, "}\n");
    put_file("look.json", out, o);
    look_split = cal_lifted.has_split;
    look_id = id;
}

static void *settings_thread(void *arg)
{
    (void)arg;
    static struct tp_file written;
    static double bright_written, ink_written;
    for (unsigned n = 0; !stop; n++) {
        if (n % 10 == 0) {   /* the calibration and the lift once a second; a new one: the look again */
            settings_load();
            if (cal_ok && (!look_id || memcmp(&written, &cal_lifted, sizeof written) || bright_written != line_bright || ink_written != line_ink))
                written = cal_lifted, bright_written = line_bright, ink_written = line_ink, write_look();
        }
        guides_off = switch_off();   /* the switch ten times a second: it should feel immediate */
        usleep(100000);
    }
    return NULL;
}

/* ---- the picture channel ---------------------------------------------------------------------------------------
 * The screen layer runs inside SYNC's own screen software, a Qt 5.6 script engine shared with all of Ford's screens.
 * That engine stops the whole screen for about a tenth of a second whenever it clears away objects that scripts have
 * made and dropped, and reading a file through a request (XMLHttpRequest) makes several kB of them each time. Read
 * 30 times a second, that froze the screen every few seconds.
 *
 * A picture's size, though, reaches a script as two plain numbers, with nothing made. So the steering is written as
 * the sizes of empty one-bit pictures (PBM "P4", which Qt reads itself):
 *
 *   sw.pbm  width  = 1 + (steering + 600) * 8       an eighth of a degree       height = 1 + count % 4
 *   st.pbm  width  = 1 + our clock in ms % 4096                                 height = 1 + count % 4 (+ 4: split view)
 *   sf.pbm  width  = 1 + (guides switched off: 1) + 2 * (look id % 2048)        height = 1
 *
 * sw and st belong together when their counts agree. The files are there only while a front view is up and this
 * program is writing them, and are removed otherwise, so a file that is there is fresh. */
static int pbm_there;

static void pbm_put(const char *name, unsigned w, unsigned h)
{
    static unsigned char out[32 + 1201 * 8];
    if (w < 1 || w > 9601 || h < 1 || h > 8) return;
    int o = snprintf((char *)out, 32, "P4\n%u %u\n", w, h);
    size_t n = (size_t)((w + 7) / 8) * h;
    memset(out + o, 0, n);
    put_file(name, out, (size_t)o + n);
}

static void pbm_gone(void)
{
    static const char *const names[] = { "sw.pbm", "st.pbm", "sf.pbm" };
    char path[256];
    if (!pbm_there) return;
    for (int i = 0; i < 3; i++) {
        snprintf(path, sizeof(path), "%s/%s", run_dir, names[i]);
        unlink(path);
    }
    pbm_there = 0;
}

/* One beat: the steering to show now, written if it has moved. While the wheel is still it is written twice a
 * second, so the layer knows the program is alive; and once more just after it stops, with the very value written
 * before, so the layer's glide ends at rest. */
static void beat(uint64_t now)
{
    static struct follow fol;
    static uint32_t count;
    static double last_sw = 1e9, last_lift = -1;
    static uint64_t last_t;
    static unsigned last_id;
    static int last_view = -1, settle, last_flags = -1;
    pthread_mutex_lock(&lock);
    int ok = steer_have && (heard_t >= now || now - heard_t <= 2000);   /* the service is talking to us */
    double v = steer_v, rate = steer_rate, lo = steer_lo < steer_v ? steer_lo : steer_v, hi = steer_hi > steer_v ? steer_hi : steer_v;
    uint64_t v_t = steer_t;
    int way = steer_way, slow = steer_slow, view = ok ? cam_view : 0;
    pthread_mutex_unlock(&lock);
    if (!ok || !cal_ok || !look_id || !(view == 8 || (view == 9 && look_split))) {   /* no front view we can draw */
        fol.on = 0, last_view = -1, last_flags = -1;
        pbm_gone();
        return;
    }
    int flags = guides_off + 2 * (int)(look_id % 2048);
    if (flags != last_flags || !pbm_there) pbm_put("sf.pbm", 1 + (unsigned)flags, 1), last_flags = flags, pbm_there = 1;
    double sw = follow_step(&fol, v, rate, v_t, now, way, slow, lo, hi);
    int moved = fabs(sw - last_sw) >= 0.05 || view != last_view || lift_in != last_lift || look_id != last_id;
    if (!moved && !settle && now - last_t < 500) return;
    settle = moved;
    if (!moved && last_sw < 1e8) sw = last_sw;
    count++;
    double code = (sw + 600) * 8;
    pbm_put("sw.pbm", 1 + (unsigned)(code < 0 ? 0 : code > 9600 ? 9600 : code + 0.5), 1 + count % 4);
    pbm_put("st.pbm", 1 + (unsigned)(now % 4096), 1 + count % 4 + (view == 9 ? 4 : 0));
    last_sw = sw, last_view = view, last_lift = lift_in, last_t = now, last_id = look_id;
}

/* The two threads the guides' smoothness depends on (the one receiving the steering, the one keeping the beat) run
 * at priority 31: just above SYNC's screen software (30), below its camera program (35). At ordinary priority they
 * are held up for 100 ms and more while SYNC is still starting its other programs, and every such hold is a stall
 * and a jump of the guides. Their own work is about a millisecond in every 33. */
static void raise_priority(void)
{
    struct sched_param sp;
    int policy;
    if (pthread_getschedparam(pthread_self(), &policy, &sp)) return;
    sp.sched_priority = 31;
    pthread_setschedparam(pthread_self(), policy, &sp);
}

/* The beat: every 1/30 s to the millisecond (33, 33, 34 ms), sleeping to the next beat rather than for a fixed time. */

static void *beat_thread(void *arg)
{
    (void)arg;
    raise_priority();
    uint64_t next = 0;
    for (unsigned k = 0; !stop;) {
        uint64_t now = now_ms();
        beat(now);
        uint64_t done = now_ms();
        if (!next || done > next + 200) next = done;
        next += ++k % 3 ? 33 : 34;
        if (next > done) usleep((useconds_t)((next - done) * 1000));
    }
    return NULL;
}

/* ---- receiving from the service --------------------------------------------------------------------------------
 * The request can be lost when this program starts before the service is listening (it is started with SYNC's own
 * services). So while nothing at all has come since the request, it is sent again: every 3 s for the first minute,
 * then every 30 s (a sleeping truck sends nothing either). Once anything has come, never. */
static volatile int asked, got;

static int subscribe(void)
{
    static struct cs_request req;
    mc_handle tx = McOpenSender(CS_SERVICE);
    if (!tx) return -1;
    memset(&req, 0, sizeof(req));
    req.count = 2;
    req.e[0].msg = MSG_STEERING, req.e[0].mode = CS_EVERY_FRAME;
    req.e[1].msg = MSG_CAMERA, req.e[1].mode = CS_ON_CHANGE;
    int st = McSend(tx, queue_name, CS_CMD_SUBSCRIBE, sizeof(req), &req);
    McClose(tx);
    return st ? -1 : 0;
}

static void *ask_again_thread(void *arg)
{
    (void)arg;
    unsigned waited = 0, n = 0;
    while (!stop) {
        sleep(3);
        if (!asked || got) { waited = 0, n = 0; continue; }
        waited += 3;
        if (n >= 20 && waited < 30) continue;
        waited = 0, n++;
        subscribe();
    }
    return NULL;
}

static void *receive_thread(void *arg)
{
    (void)arg;
    static uint8_t buf[MC_HDR_SIZE + 4096], data[4096];
    raise_priority();
    while (!stop) {
        mc_handle rx = McOpenReceiver(queue_name);
        if (!rx || subscribe()) {   /* SYNC's message service is not up yet: again in 5 s */
            if (rx) McClose(rx);
            sleep(5);
            continue;
        }
        got = 0, asked = 1;
        while (!stop) {
            char src[MC_NAME_LEN];
            uint32_t msg = 0;
            if (McReceive(rx, src, &msg, sizeof(buf), buf)) break;
            uint32_t len = McGetLength(buf);
            if (len > sizeof(data) || McGetDataOfSize(buf, data, sizeof(data))) continue;
            got = 1;
            pthread_mutex_lock(&lock);
            heard_t = now_ms();
            if (msg == MSG_STEERING && len >= 20) {
                float deg;
                memcpy(&deg, data + 16, 4);
                if (deg == deg && deg > -1600 && deg < 1600) steer_seen(deg, heard_t);
            } else if (msg == MSG_CAMERA && len >= 4) {
                /* the feature number's byte order is not certain; a view fits in one byte, so either is taken */
                unsigned le = data[2] | data[3] << 8, be = data[3] | data[2] << 8;
                if (le == FEATURE_VIEW || be == FEATURE_VIEW) cam_view = data[0] ? data[0] : data[1];
            }
            pthread_mutex_unlock(&lock);
        }
        asked = 0;
        McClose(rx);
        sleep(1);
    }
    return NULL;
}

static void on_signal(int sig)
{
    (void)sig;
    stop = 1;
}

int main(void)
{
    mkdir(run_dir, 0755);
    mkdir(settings_dir, 0755);
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGPIPE, SIG_IGN);
    pbm_there = 1, pbm_gone();   /* none left from an earlier run */

    pthread_t t;
    pthread_create(&t, NULL, receive_thread, NULL);
    pthread_create(&t, NULL, ask_again_thread, NULL);
    pthread_create(&t, NULL, settings_thread, NULL);
    pthread_create(&t, NULL, beat_thread, NULL);
    while (!stop) {
        sleep(1);
    }
    pbm_gone();
    return 0;
}
