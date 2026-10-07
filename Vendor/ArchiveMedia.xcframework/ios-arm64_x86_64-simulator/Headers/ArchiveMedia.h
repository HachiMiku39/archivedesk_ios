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
void adm_close(ADMDecoder **decoder);
void adm_error(int error, char *buffer, size_t size);
const char *adm_license(void);
#ifdef __cplusplus
}
#endif
