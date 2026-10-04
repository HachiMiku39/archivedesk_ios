#ifndef ARCHIVEDESK_CODEC_ALLOCATOR_H
#define ARCHIVEDESK_CODEC_ALLOCATOR_H
#include <stdlib.h>
#include <string.h>
void *archivedesk_codec_malloc(size_t);
void *archivedesk_codec_calloc(size_t, size_t);
void *archivedesk_codec_realloc(void *, size_t);
void archivedesk_codec_free(void *);
char *archivedesk_codec_strdup(const char *);
size_t archivedesk_codec_live_bytes(void);
#ifndef ARCHIVEDESK_ALLOCATOR_IMPLEMENTATION
#define malloc archivedesk_codec_malloc
#define calloc archivedesk_codec_calloc
#define realloc archivedesk_codec_realloc
#define free archivedesk_codec_free
#define strdup archivedesk_codec_strdup
#endif
#endif
