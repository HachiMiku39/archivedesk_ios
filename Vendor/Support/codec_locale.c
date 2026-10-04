#include <locale.h>
#include <xlocale.h>
#include <stdlib.h>

/* libarchive converts archive names through the current C locale. Use a
 * thread-local UTF-8 locale, never mutate the application's global locale. */
typedef struct { locale_t previous, utf8; } codec_locale;
void *archivedesk_codec_enter_utf8_locale(void) {
    codec_locale *context = malloc(sizeof(*context));
    if (!context) return NULL;
    context->utf8 = newlocale(LC_CTYPE_MASK, "en_US.UTF-8", NULL);
    if (!context->utf8) { free(context); return NULL; }
    context->previous = uselocale(context->utf8);
    if (!context->previous) { freelocale(context->utf8); free(context); return NULL; }
    return context;
}
void archivedesk_codec_leave_utf8_locale(void *opaque) {
    if (!opaque) return;
    codec_locale *context = opaque;
    uselocale(context->previous);
    freelocale(context->utf8);
    free(context);
}
