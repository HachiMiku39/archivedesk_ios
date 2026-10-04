#include "archive.h"
#include "archive_entry.h"
void *archivedesk_codec_enter_utf8_locale(void);
void archivedesk_codec_leave_utf8_locale(void *);
#include <stddef.h>
static inline int archivedesk_entry_is_directory(struct archive_entry *entry) {
    return archive_entry_filetype(entry) == AE_IFDIR;
}
static inline int archivedesk_entry_is_regular(struct archive_entry *entry) {
    return archive_entry_filetype(entry) == AE_IFREG;
}
size_t archivedesk_codec_live_bytes(void);
void *archivedesk_codec_malloc(size_t);
void archivedesk_codec_free(void *);
