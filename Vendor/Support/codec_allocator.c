#define ARCHIVEDESK_ALLOCATOR_IMPLEMENTATION
#include "codec_allocator.h"
#include <stddef.h>
#include <stdint.h>
#include <errno.h>
/* Decoder objects stay on their creating thread. XZ is built single-threaded.
 * This bounds vendor allocations, not total app RSS or system zlib/bzip2. */
typedef union { max_align_t alignment; size_t size; } allocation_header;
static _Thread_local size_t live_bytes;
static const size_t budget = 256U * 1024U * 1024U;
static const size_t largest = 128U * 1024U * 1024U;
size_t archivedesk_codec_live_bytes(void) { return live_bytes; }
void *archivedesk_codec_malloc(size_t size) {
    if (size > largest || size > budget - live_bytes || size > SIZE_MAX - sizeof(allocation_header)) {
        errno = ENOMEM; return NULL;
    }
    allocation_header *header = malloc(sizeof(*header) + (size ? size : 1));
    if (!header) return NULL;
    header->size = size; live_bytes += size;
    return header + 1;
}
void archivedesk_codec_free(void *pointer) {
    if (!pointer) return;
    allocation_header *header = (allocation_header *)pointer - 1;
    live_bytes -= header->size;
    free(header);
}
void *archivedesk_codec_calloc(size_t count, size_t size) {
    if (size && count > SIZE_MAX / size) { errno = ENOMEM; return NULL; }
    void *pointer = archivedesk_codec_malloc(count * size);
    if (pointer) memset(pointer, 0, count * size);
    return pointer;
}
void *archivedesk_codec_realloc(void *pointer, size_t size) {
    if (!pointer) return archivedesk_codec_malloc(size);
    if (!size) { archivedesk_codec_free(pointer); return NULL; }
    allocation_header *old = (allocation_header *)pointer - 1;
    if (size > largest || size > budget - (live_bytes - old->size)) { errno = ENOMEM; return NULL; }
    size_t old_size = old->size;
    allocation_header *header = realloc(old, sizeof(*header) + size);
    if (!header) return NULL;
    header->size = size; live_bytes = live_bytes - old_size + size;
    return header + 1;
}
char *archivedesk_codec_strdup(const char *string) {
    size_t length = strlen(string) + 1;
    char *copy = archivedesk_codec_malloc(length);
    if (copy) memcpy(copy, string, length);
    return copy;
}
