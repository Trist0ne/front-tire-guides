/* Ford NS framework message channels: plain C exports of SYNC's /apps/lib/libNS_CoreUnified.so.
 * Signatures read from SYNC 3.4 (the same in builds 22110 to 26057). Return value 0 = OK. */
#ifndef MC_H
#define MC_H

#include <stdint.h>

typedef void *mc_handle;

mc_handle McOpenReceiver(const char *name);
mc_handle McOpenSender(const char *name);
int McSend(mc_handle h, const char *source, uint32_t cmd, uint32_t len, const void *data);
/* source: 64-byte buffer for the sender's name; buf receives header (MC_HDR_SIZE) + data */
int McReceive(mc_handle h, char *source, uint32_t *cmd, uint32_t buf_len, void *buf);
uint32_t McGetLength(const void *buf);
int McGetDataOfSize(const void *buf, void *dest, uint32_t size);
/* sysinfo: a 64-byte field of the header; SYNC's notification service puts the notification's name there
 * (dest: 64 bytes). Used by camctl only. */
int McGetSysInfoData(const void *buf, char *dest);
int McClose(mc_handle h);

#define MC_HDR_SIZE 0xd4
#define MC_NAME_LEN 64

#endif
