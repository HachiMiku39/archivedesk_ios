#include "ArchiveMedia.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
static int keep_going(void *opaque) { return opaque == NULL || *(int *)opaque; }
static void check(int result) {
    if (result < 0) { char error[256]; adm_error(result, error, sizeof(error)); fprintf(stderr, "Decoder error: %s\n", error); }
    assert(result >= 0);
}
int main(int argc, char **argv) {
    assert(argc == 4);
    assert(strstr(adm_license(), "LGPL version 2.1"));
    for (int file = 1; file < argc; file++) {
        ADMDecoder *decoder = NULL; ADMInfo info;
        check(adm_open(argv[file], keep_going, NULL, &decoder, &info));
        assert(decoder);
        if (file == 1) { assert(info.has_video && info.has_audio); assert(strcmp(info.video_codec, "libdav1d") == 0); }
        if (file == 2) assert(strcmp(info.audio_codec, "flac") == 0);
        if (file == 3) assert(strcmp(info.video_codec, "mjpeg") == 0);
        ADMFrame event; int result; uint64_t images = 0, samples = 0, checksum = 1469598103934665603ULL;
        while ((result = adm_next(decoder, &event)) > 0) {
            assert(isfinite(event.time) && isfinite(event.duration));
            assert(event.size > 0 && event.size <= 1280 * 1280 * 4);
            if (event.kind == 1) { images++; assert(event.width <= 1280 && event.height <= 1280); }
            else { assert(event.kind == 2 && event.samples > 0); samples += event.samples; }
            for (size_t i = 0; i < event.size; i += 137) { checksum ^= event.data[i]; checksum *= 1099511628211ULL; }
            assert(images < 1000000 && samples < 48000ULL * 86400);
        }
        check(result);
        if (file == 1) assert(images > 2000 && samples > 48000 * 90);
        if (file == 2) assert(samples > 48000 * 162 && !images);
        if (file == 3) assert(images == 1 && !samples);
        printf("PASS: media %d full software decode, video=%llu PCM frames=%llu fingerprint=%016llx\n", file,
            (unsigned long long)images, (unsigned long long)samples, (unsigned long long)checksum);
        if (file != 3) {
            fprintf(stderr, "Checking seek for media %d\n", file);
            check(adm_seek(decoder, 30)); check(adm_next(decoder, &event));
        }
        adm_close(&decoder); assert(!decoder);
        int continuation = 1;
        check(adm_open(argv[file], keep_going, &continuation, &decoder, &info));
        continuation = 0;
        assert(adm_next(decoder, &event) < 0);
        adm_close(&decoder);
        fprintf(stderr, "Finished media %d including cancellation\n", file);
    }
    ADMDecoder *missing = NULL; ADMInfo info;
    assert(adm_open("https://example.invalid/not-a-local-file", keep_going, NULL, &missing, &info) < 0 && !missing);
    puts("PASS: seek, cooperative cancellation, close/null and non-file input rejection");
}
