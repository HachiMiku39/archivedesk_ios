#include "ArchiveMedia.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

typedef struct { unsigned frames; unsigned long long samples; double last_time; } Counts;
static Counts decode(const char *path, int edge) {
    ADMDecoder *decoder = NULL; ADMInfo info; ADMFrame frame;
    assert(adm_open(path, NULL, NULL, &decoder, &info) == 0);
    assert(adm_video_output_limit(decoder, 159) < 0);
    assert(adm_video_output_limit(decoder, 1281) < 0);
    assert(adm_video_output_limit(decoder, edge) == 0);
    Counts count = {0}; int result;
    while ((result = adm_next(decoder, &frame)) > 0) {
        if (frame.kind == 1) {
            assert(frame.width == edge && frame.height == edge * 9 / 16);
            assert(frame.size == (size_t)frame.width * frame.height * 4);
            if (count.frames) assert(frame.time >= count.last_time);
            count.frames++; count.last_time = frame.time;
        } else { count.samples += frame.samples; }
    }
    assert(result == 0 && count.frames > 2000 && count.samples > 48000ULL * 90);
    assert(adm_seek(decoder, 30) == 0);
    do { result = adm_next(decoder, &frame); } while (result > 0 && frame.kind != 1);
    assert(result > 0 && frame.width == edge);
    adm_close(&decoder);
    return count;
}
int main(int argc, char **argv) {
    assert(argc == 4);
    Counts full = decode(argv[1], 1280), small = decode(argv[1], 640);
    assert(full.frames == small.frames && full.samples == small.samples);
    assert(fabs(full.last_time - small.last_time) < 0.000001);
    ADMDecoder *decoder = NULL; ADMInfo info; ADMFrame frame;
    assert(adm_open(argv[2], NULL, NULL, &decoder, &info) == 0);
    assert(adm_next(decoder, &frame) > 0 && frame.width == 900 && frame.height == 900);
    adm_close(&decoder);
    assert(adm_open(argv[3], NULL, NULL, &decoder, &info) == 0);
    assert(adm_video_output_limit(decoder, 640) == 0);
    assert(adm_artwork(decoder, &frame) == 1 && frame.width == 700 && frame.height == 700);
    adm_close(&decoder);
    printf("PASS: 1280/640 preserve %u video frames, %llu PCM frames and timestamps; seek retains cap; invalid caps rejected; JPEG/artwork unchanged\n", small.frames, small.samples);
}
