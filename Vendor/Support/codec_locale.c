#include <locale.h>
#include <xlocale.h>
#include <stdlib.h>
#include <errno.h>
#include <langinfo.h>
#include <string.h>

/* libarchive converts archive names through the current C locale. Use a
 * thread-local UTF-8 locale, never mutate the application's global locale. */
typedef struct { locale_t previous, utf8; } codec_locale;
void *archivedesk_codec_enter_utf8_locale(void) {
    codec_locale *context = malloc(sizeof(*context));
    if (!context) return NULL;
    /* Named locale tables can differ on a device and Simulator. Never fall
     * back to ASCII: that silently corrupts non-ASCII archive pathnames. */
    static const char *names[] = { "en_US.UTF-8", "UTF-8", "C.UTF-8" };
    context->utf8 = NULL;
    int failure = ENOENT;
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        errno = 0;
        locale_t candidate = newlocale(LC_CTYPE_MASK, names[i], NULL);
        if (!candidate) {
            if (errno) failure = errno;
            if (failure == ENOMEM) break;
            continue;
        }
        const char *codeset = nl_langinfo_l(CODESET, candidate);
        if (codeset && (strcmp(codeset, "UTF-8") == 0 || strcmp(codeset, "UTF8") == 0)) {
            context->utf8 = candidate;
            break;
        }
        freelocale(candidate);
        failure = EILSEQ;
    }
    if (!context->utf8) { free(context); errno = failure; return NULL; }
    context->previous = uselocale(context->utf8);
    if (!context->previous) {
        failure = errno ? errno : EINVAL;
        freelocale(context->utf8); free(context); errno = failure; return NULL;
    }
    errno = 0;
    return context;
}
void archivedesk_codec_leave_utf8_locale(void *opaque) {
    if (!opaque) return;
    codec_locale *context = opaque;
    uselocale(context->previous);
    freelocale(context->utf8);
    free(context);
}
