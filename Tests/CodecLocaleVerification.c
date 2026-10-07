#include <locale.h>
#include <xlocale.h>
#include <langinfo.h>
#include <errno.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

void *archivedesk_codec_enter_utf8_locale(void);
void archivedesk_codec_leave_utf8_locale(void *);
static int mode, attempts;

/* Fault injection is linked only into this host test, never into the app. */
locale_t probe_newlocale(int mask, const char *name, locale_t base) {
    attempts++;
    if (mode == 1 && attempts == 1) { errno = ENOENT; return NULL; }
    if (mode == 2) { errno = ENOENT; return NULL; }
    if (mode == 3) { errno = ENOMEM; return NULL; }
    if (mode == 4) return newlocale(mask, "C", base);
    return newlocale(mask, name, base);
}
locale_t probe_uselocale(locale_t value) {
    if (mode == 5 && value != NULL && value != LC_GLOBAL_LOCALE) { errno = EACCES; return NULL; }
    return uselocale(value);
}
int main(void) {
    locale_t original = uselocale(NULL);
    void *outer = archivedesk_codec_enter_utf8_locale();
    assert(outer && errno == 0);
    assert(strcmp(nl_langinfo_l(CODESET, uselocale(NULL)), "UTF-8") == 0);
    void *inner = archivedesk_codec_enter_utf8_locale();
    assert(inner);
    archivedesk_codec_leave_utf8_locale(inner);
    archivedesk_codec_leave_utf8_locale(outer);
    assert(uselocale(NULL) == original);
    mode = 1; attempts = 0;
    outer = archivedesk_codec_enter_utf8_locale();
    assert(outer && attempts == 2 && errno == 0);
    archivedesk_codec_leave_utf8_locale(outer);
    mode = 2; attempts = 0;
    assert(!archivedesk_codec_enter_utf8_locale() && attempts == 3 && errno == ENOENT);
    mode = 3; attempts = 0;
    assert(!archivedesk_codec_enter_utf8_locale() && attempts == 1 && errno == ENOMEM);
    mode = 4; attempts = 0;
    assert(!archivedesk_codec_enter_utf8_locale() && attempts == 3 && errno == EILSEQ);
    mode = 5; attempts = 0;
    assert(!archivedesk_codec_enter_utf8_locale() && errno == EACCES);
    assert(uselocale(NULL) == original);
    puts("PASS: UTF-8 locale fallback, no ASCII fallback, nested restoration, errno preservation, ENOMEM and activation failure");
}
