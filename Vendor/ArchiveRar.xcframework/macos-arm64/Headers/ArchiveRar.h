#ifndef ARCHIVEDESK_RAR_H
#define ARCHIVEDESK_RAR_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// LGPL-2.1-or-later bridge to 7-Zip. RAR decoder sources additionally carry
// the unRAR restriction: they must not be used to develop a RAR archiver.
typedef int (*ADRContinue)(void *context);
typedef int (*ADRWrite)(void *context, const void *bytes, size_t count);
typedef struct {
    uint64_t size, packed;
    uint32_t crc;
    int directory, encrypted, unsafe, has_crc;
} ADREntry;
enum { ADR_OK=0, ADR_PASSWORD_REQUIRED=1, ADR_PASSWORD_OR_DAMAGE=2,
       ADR_UNSUPPORTED=3, ADR_CANCELLED=4, ADR_CAPACITY=5, ADR_MALFORMED=6 };
void *adr_open(const char *path, const char *password, ADRContinue proceed, void *context, int *status);
void adr_close(void *handle);
uint32_t adr_count(void *handle);
int adr_headers_encrypted(void *handle);
int adr_version(void *handle);
int adr_entry(void *handle, uint32_t index, char *path, size_t capacity, ADREntry *entry);
int adr_extract(void *handle, uint32_t index, uint64_t expected_size, const char *password,
                ADRWrite write, void *context);
#ifdef __cplusplus
}
#endif
#endif
