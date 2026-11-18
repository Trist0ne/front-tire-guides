/* mc.h on SYNC: loads Ford's libNS_CoreUnified.so at run time, so building the program needs no Ford binaries. */
#include <dlfcn.h>
#include <stddef.h>
#include "mc.h"

/* Ford's libraries expect their host program to define g_PasLogParams (every Ford executable exports its own,
 * 12,120 bytes; the libraries read zone bits in it). Ours stays zero. Exported from the executable with
 * -Wl,--dynamic-list=exports.dyn (build.sh). Without it the library does not load on QNX ("unknown symbol:
 * g_PasLogParams"). */
char g_PasLogParams[12120];

static void *lib;
static mc_handle (*open_rx)(const char *), (*open_tx)(const char *);
static int (*send_fn)(mc_handle, const char *, uint32_t, uint32_t, const void *);
static int (*recv_fn)(mc_handle, char *, uint32_t *, uint32_t, void *);
static uint32_t (*len_fn)(const void *);
static int (*data_fn)(const void *, void *, uint32_t);
static int (*si_fn)(const void *, char *);   /* (not needed to load: only camctl uses it) */
static int (*close_fn)(mc_handle);

static int load(void)
{
    if (lib) return 0;
    lib = dlopen("/apps/lib/libNS_CoreUnified.so", RTLD_NOW);
    if (!lib) lib = dlopen("libNS_CoreUnified.so", RTLD_NOW);
    if (!lib) return -1;
    open_rx = (mc_handle (*)(const char *))dlsym(lib, "McOpenReceiver");
    open_tx = (mc_handle (*)(const char *))dlsym(lib, "McOpenSender");
    send_fn = (int (*)(mc_handle, const char *, uint32_t, uint32_t, const void *))dlsym(lib, "McSend");
    recv_fn = (int (*)(mc_handle, char *, uint32_t *, uint32_t, void *))dlsym(lib, "McReceive");
    len_fn = (uint32_t (*)(const void *))dlsym(lib, "McGetLength");
    data_fn = (int (*)(const void *, void *, uint32_t))dlsym(lib, "McGetDataOfSize");
    si_fn = (int (*)(const void *, char *))dlsym(lib, "McGetSysInfoData");
    close_fn = (int (*)(mc_handle))dlsym(lib, "McClose");
    if (!open_rx || !open_tx || !send_fn || !recv_fn || !len_fn || !data_fn || !close_fn) {
        dlclose(lib);
        lib = NULL;
        return -1;
    }
    return 0;
}

mc_handle McOpenReceiver(const char *name) { return load() ? NULL : open_rx(name); }
mc_handle McOpenSender(const char *name) { return load() ? NULL : open_tx(name); }
int McSend(mc_handle h, const char *src, uint32_t cmd, uint32_t len, const void *data)
{
    return load() ? -1 : send_fn(h, src, cmd, len, data);
}
int McReceive(mc_handle h, char *src, uint32_t *cmd, uint32_t len, void *buf)
{
    return load() ? -1 : recv_fn(h, src, cmd, len, buf);
}
uint32_t McGetLength(const void *buf) { return load() ? 0 : len_fn(buf); }
int McGetDataOfSize(const void *buf, void *dest, uint32_t size) { return load() ? -1 : data_fn(buf, dest, size); }
int McGetSysInfoData(const void *buf, char *dest) { return load() || !si_fn ? -1 : si_fn(buf, dest); }
int McClose(mc_handle h) { return load() ? -1 : close_fn(h); }
