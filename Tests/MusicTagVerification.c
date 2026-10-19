#include "ArchiveMedia.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int keep_going(void *context) { return *(int *)context; }
static void verify(const char *root, const char *name, int expected_cover, int expected_tags) {
    char path[4096]; snprintf(path, sizeof(path), "%s/%s", root, name);
    ADMDecoder *d = NULL; ADMInfo info;
    assert(adm_open(path, NULL, NULL, &d, &info) == 0 && d);
    assert(info.has_audio && !info.has_video && info.sample_rate >= 44100 && info.channels == 1);
    char key[128], value[2049]; int title = 0, artist = 0, album = 0, track = 0;
    for (unsigned i = 0; i < 64; i++) {
        int result = adm_metadata(d, i, key, sizeof(key), value, sizeof(value));
        assert(result >= 0); if (!result) break;
        if (!strcmp(key, "title")) { title++; if (expected_tags) assert(!strcmp(value, "星のうた · 测试曲")); }
        if (!strcmp(key, "artist")) { artist++; assert(!strcmp(value, "ArchiveDesk Artist")); }
        if (!strcmp(key, "album")) { album++; assert(!strcmp(value, "Preview Test Album")); }
        if (!strcmp(key, "track")) { track++; assert(!strcmp(value, "3/12")); }
    }
    if (expected_tags) assert(title && artist && album && track);
    char small[2]; assert(adm_metadata(d, 65, key, sizeof(key), value, sizeof(value)) < 0);
    if (expected_tags) assert(adm_metadata(d, 0, small, sizeof(small), value, sizeof(value)) == 2);
    ADMFrame frame; int cover = adm_artwork(d, &frame);
    if (expected_cover == 1) {
        assert(cover == 1 && frame.kind == 1 && frame.size > 0 && frame.width <= 1280 && frame.height <= 1280);
        assert(adm_artwork(d, &frame) == 1); // replacing task-owned pixels is safe
    }
    else if (expected_cover == 0) assert(cover == 0);
    else assert(cover < 0);
    // Artwork and metadata must not consume or disrupt the audio stream.
    int audio = 0, result;
    while ((result = adm_next(d, &frame)) > 0) { assert(frame.kind == 2); audio += frame.samples; }
    assert(result == 0 && audio > 48000);
    assert(adm_seek(d, 1) == 0 && adm_next(d, &frame) > 0 && frame.kind == 2);
    adm_close(&d); assert(!d);
    printf("PASS %s: tags, cover bounds, complete audio decode and seek\n", name);
}
int main(int argc, char **argv) {
    assert(argc == 2);
    verify(argv[1], "tagged.mp3", 1, 1);
    verify(argv[1], "id3v24.mp3", 1, 1);
    verify(argv[1], "tagged.flac", 1, 1);
    verify(argv[1], "tagged.m4a", 1, 1);
    verify(argv[1], "plain.wav", 0, 0);
    verify(argv[1], "oversized.flac", -1, 0);
    verify(argv[1], "broken-cover.mp3", -1, 0);
    verify(argv[1], "large-cover.mp3", -1, 0);
    char path[4096], key[128], value[2049];
    snprintf(path, sizeof(path), "%s/long-tags.mp3", argv[1]);
    ADMDecoder *d = NULL; ADMInfo info;
    assert(adm_open(path, NULL, NULL, &d, &info) == 0);
    assert(adm_metadata(d, 0, key, sizeof(key), value, sizeof(value)) == 2);
    assert(strlen(value) == sizeof(value) - 1);
    assert(adm_metadata(d, 64, key, sizeof(key), value, sizeof(value)) == 1);
    adm_close(&d);
    puts("PASS metadata value and entry-count bounds");
    snprintf(path, sizeof(path), "%s/tagged.mp3", argv[1]);
    int continuation = 1;
    assert(adm_open(path, keep_going, &continuation, &d, &info) == 0);
    continuation = 0;
    ADMFrame event;
    assert(adm_metadata(d, 0, key, sizeof(key), value, sizeof(value)) < 0);
    assert(adm_artwork(d, &event) < 0 && adm_next(d, &event) < 0);
    adm_close(&d);
    puts("PASS tag/artwork cooperative cancellation and repeated cover access");
}
