#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct ADMDecoder ADMDecoder;
typedef int (*ADMContinue)(void *context);
typedef struct {
    int has_video, has_audio, width, height;
    double duration;
    char video_codec[32], audio_codec[32];
    int sample_rate, channels;
    int64_t bit_rate;
} ADMInfo;
typedef struct {
    int kind; /* 1: RGBA8 video/image, 2: interleaved stereo Float32 PCM 48kHz */
    const uint8_t *data; /* task-owned, valid only until the next bridge call */
    size_t size;
    int width, height, samples;
    double time, duration;
} ADMFrame;
int adm_open(const char *path, ADMContinue continuation, void *context, ADMDecoder **decoder, ADMInfo *info);
int adm_next(ADMDecoder *decoder, ADMFrame *frame); /* 1 event, 0 EOF, negative error */
int adm_seek(ADMDecoder *decoder, double seconds);
/* Serialized with decoding. Limits the primary video/image output surface;
   callers retain 1280 for still images. Does not change frame rate, source
   resolution or the native-resolution AV1 decoding workload. Artwork is separate. */
int adm_video_output_limit(ADMDecoder *decoder, int longest_edge);
/* Format tags followed by audio-stream tags, without fetching external URLs.
   Caller buffers are bounded UTF-8; 2 means truncated, 1 present, 0 absent. */
int adm_metadata(ADMDecoder *decoder, unsigned index, char *key, size_t key_size, char *value, size_t value_size);
/* Independent JPEG/PNG attached-picture decoder, not a playback stream.
   1 RGBA image, 0 no embedded cover, negative error (audio remains usable). */
int adm_artwork(ADMDecoder *decoder, ADMFrame *frame);
void adm_close(ADMDecoder **decoder);
void adm_error(int error, char *buffer, size_t size);
const char *adm_license(void);
#ifdef __cplusplus
}
#endif
