#include "ArchiveMedia.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/error.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define ADM_PIXELS (3840LL * 2160)
#define ADM_FILE_LIMIT (512LL * 1024 * 1024)
#define ADM_PACKET_LIMIT (8 * 1024 * 1024)
#define ADM_PCM_SAMPLES 65536
struct ADMDecoder {
    int fd, stream[2], pending, eof, flush[2], drained[2];
    int64_t size, position;
    ADMContinue continuation;
    void *continuation_context;
    AVFormatContext *format;
    AVIOContext *io;
    AVCodecContext *codec[2];
    AVPacket *packet;
    AVFrame *frame;
    struct SwsContext *scaler;
    SwrContext *resampler;
    AVChannelLayout source_layout;
    int source_rate, source_format;
    uint8_t *rgba, *pcm;
    size_t rgba_size;
    double next_time[2];
};
static const char *codec_list = "aac,flac,mjpeg,png,mp3,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,h264,hevc,libdav1d,webp,vorbis,opus";
static dispatch_once_t initialized;
static void initialize_media(void *unused) {
    (void)unused;
    av_max_alloc(64U * 1024U * 1024U);
    av_log_set_level(AV_LOG_QUIET); /* Never log user media metadata/paths. */
    #ifdef ADM_VERIFY_TRACE
    av_log_set_level(AV_LOG_WARNING); /* Host-only test build, never in the app. */
    #endif
}
static int interrupted(void *opaque) {
    ADMDecoder *d = opaque;
    return d->continuation && !d->continuation(d->continuation_context);
}
static int read_media(void *opaque, uint8_t *buffer, int count) {
    ADMDecoder *d = opaque;
    if (interrupted(d)) return AVERROR_EXIT;
    if (d->position >= d->size) return AVERROR_EOF;
    if (count > d->size - d->position) count = (int)(d->size - d->position);
    ssize_t got;
    do { got = pread(d->fd, buffer, count, d->position); } while (got < 0 && errno == EINTR && !interrupted(d));
    if (got < 0) return AVERROR(errno);
    if (!got) return AVERROR_EOF;
    d->position += got;
    return (int)got;
}
static int64_t seek_media(void *opaque, int64_t offset, int origin) {
    ADMDecoder *d = opaque;
    if (interrupted(d)) return AVERROR_EXIT;
    if (origin == AVSEEK_SIZE) return d->size;
    origin &= ~AVSEEK_FORCE;
    int64_t base, position;
    switch (origin) { case SEEK_SET: base = 0; break; case SEEK_CUR: base = d->position; break; case SEEK_END: base = d->size; break; default: return AVERROR(EINVAL); }
    if (__builtin_add_overflow(base, offset, &position) || position < 0 || position > d->size) return AVERROR(EINVAL);
    d->position = position;
    return position;
}
void adm_close(ADMDecoder **pointer) {
    if (!pointer || !*pointer) return;
    ADMDecoder *d = *pointer; *pointer = NULL;
    avcodec_free_context(&d->codec[0]); avcodec_free_context(&d->codec[1]);
    av_packet_free(&d->packet); av_frame_free(&d->frame);
    sws_freeContext(d->scaler); swr_free(&d->resampler);
    av_channel_layout_uninit(&d->source_layout);
    av_free(d->rgba); av_free(d->pcm);
    avformat_close_input(&d->format);
    if (d->io) { av_freep(&d->io->buffer); avio_context_free(&d->io); }
    if (d->fd >= 0) close(d->fd);
    free(d);
}
static void decoder_options(AVDictionary **options) {
    av_dict_set(options, "threads", "2", 0);
    av_dict_set(options, "max_pixels", "8294400", 0);
    av_dict_set(options, "max_frame_delay", "1", 0);
    av_dict_set(options, "codec_whitelist", codec_list, 0);
}
int adm_open(const char *path, ADMContinue continuation, void *context, ADMDecoder **output, ADMInfo *info) {
    if (!path || !output || !info) return AVERROR(EINVAL);
    *output = NULL; memset(info, 0, sizeof(*info));
    dispatch_once_f(&initialized, NULL, initialize_media);
    ADMDecoder *d = calloc(1, sizeof(*d));
    if (!d) return AVERROR(ENOMEM);
    d->fd = -1; d->stream[0] = d->stream[1] = -1; d->pending = -1;
    d->continuation = continuation; d->continuation_context = context;
    int result = AVERROR(ENOMEM);
    const char *stage = "local input";
    d->fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (d->fd < 0) { result = AVERROR(errno); goto failure; }
    struct stat st;
    if (fstat(d->fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 || st.st_size > ADM_FILE_LIMIT) { result = AVERROR(EFBIG); goto failure; }
    d->size = st.st_size;
    uint8_t *io_buffer = av_malloc(64 * 1024);
    if (!io_buffer) goto failure;
    d->io = avio_alloc_context(io_buffer, 64 * 1024, 0, d, read_media, NULL, seek_media);
    if (!d->io) { av_free(io_buffer); goto failure; }
    d->format = avformat_alloc_context();
    if (!d->format) goto failure;
    d->format->pb = d->io; d->format->flags |= AVFMT_FLAG_CUSTOM_IO;
    d->format->interrupt_callback = (AVIOInterruptCB){interrupted, d};
    d->format->probesize = 1024 * 1024; d->format->max_analyze_duration = 2 * AV_TIME_BASE;
    AVDictionary *options = NULL;
    av_dict_set(&options, "max_streams", "8", 0);
    av_dict_set(&options, "codec_whitelist", codec_list, 0);
    av_dict_set(&options, "protocol_whitelist", "", 0);
    av_dict_set(&options, "format_whitelist", "mov,flac,mp3,aac,wav,matroska,webm,ogg,mjpeg,jpeg_pipe,png_pipe,webp_pipe", 0);
    av_dict_set(&options, "enable_drefs", "0", 0);
    av_dict_set(&options, "use_absolute_path", "0", 0);
    stage = "format open";
    result = avformat_open_input(&d->format, path, NULL, &options);
    av_dict_free(&options);
    if (result < 0) goto failure;
    if (!d->format->nb_streams || d->format->nb_streams > 8) { result = AVERROR(EFBIG); goto failure; }
    AVDictionary *stream_options[8] = {0};
    for (unsigned i = 0; i < d->format->nb_streams; i++) decoder_options(&stream_options[i]);
    stage = "stream information";
    result = avformat_find_stream_info(d->format, stream_options);
    for (unsigned i = 0; i < 8; i++) av_dict_free(&stream_options[i]);
    if (result < 0) goto failure;
    if (!d->format->nb_streams || d->format->nb_streams > 8) { result = AVERROR(EFBIG); goto failure; }
    for (int kind = 0; kind < 2; kind++) {
        stage = kind ? "audio decoder" : "video decoder";
        enum AVMediaType type = kind ? AVMEDIA_TYPE_AUDIO : AVMEDIA_TYPE_VIDEO;
        const AVCodec *codec = NULL;
        int index = av_find_best_stream(d->format, type, -1, -1, &codec, 0);
        if (index == AVERROR_STREAM_NOT_FOUND) { d->drained[kind] = 1; continue; }
        if (index < 0 || !codec) { result = index; goto failure; }
        AVCodecParameters *p = d->format->streams[index]->codecpar;
        if ((!kind && (p->width <= 0 || p->height <= 0 || (int64_t)p->width * p->height > ADM_PIXELS)) ||
            (kind && (p->ch_layout.nb_channels < 1 || p->ch_layout.nb_channels > 8 || p->sample_rate < 8000 || p->sample_rate > 192000))) { result = AVERROR(EFBIG); goto failure; }
        d->stream[kind] = index;
        d->codec[kind] = avcodec_alloc_context3(codec);
        if (!d->codec[kind]) { result = AVERROR(ENOMEM); goto failure; }
        if ((result = avcodec_parameters_to_context(d->codec[kind], p)) < 0) goto failure;
        d->codec[kind]->thread_count = 2; d->codec[kind]->max_pixels = ADM_PIXELS;
        d->codec[kind]->pkt_timebase = d->format->streams[index]->time_base;
        d->codec[kind]->flags |= AV_CODEC_FLAG_LOW_DELAY;
        decoder_options(&options);
        result = avcodec_open2(d->codec[kind], codec, &options);
        av_dict_free(&options);
        if (result < 0) goto failure;
        char *name = kind ? info->audio_codec : info->video_codec;
        snprintf(name, 32, "%s", codec->name);
        if (kind) info->has_audio = 1;
        else { info->has_video = 1; info->width = p->width; info->height = p->height; }
    }
    if (!info->has_video && !info->has_audio) { result = AVERROR_DECODER_NOT_FOUND; goto failure; }
    d->packet = av_packet_alloc(); d->frame = av_frame_alloc();
    d->pcm = av_malloc(ADM_PCM_SAMPLES * 2 * sizeof(float));
    if (!d->packet || !d->frame || !d->pcm) { result = AVERROR(ENOMEM); goto failure; }
    info->duration = d->format->duration == AV_NOPTS_VALUE ? 0 : (double)d->format->duration / AV_TIME_BASE;
    if (!isfinite(info->duration) || info->duration < 0) info->duration = 0;
    *output = d;
    return 0;
failure:
    #ifdef ADM_VERIFY_TRACE
    fprintf(stderr, "Media open stage: %s, status %d\n", stage, result);
    #else
    (void)stage;
    #endif
    adm_close(&d);
    return result;
}
static int convert_frame(ADMDecoder *d, int kind, ADMFrame *event) {
    AVFrame *f = d->frame;
    memset(event, 0, sizeof(*event)); event->kind = kind + 1;
    AVRational time_base = d->format->streams[d->stream[kind]]->time_base;
    event->time = f->best_effort_timestamp == AV_NOPTS_VALUE ? d->next_time[kind] : f->best_effort_timestamp * av_q2d(time_base);
    if (!isfinite(event->time)) return AVERROR_INVALIDDATA;
    if (!kind) {
        if (f->width <= 0 || f->height <= 0 || (int64_t)f->width * f->height > ADM_PIXELS) return AVERROR(EFBIG);
        double ratio = fmin(1.0, 1280.0 / fmax(f->width, f->height));
        int width = (int)(f->width * ratio), height = (int)(f->height * ratio);
        if (width < 1 || height < 1) return AVERROR_INVALIDDATA;
        size_t size = (size_t)width * height * 4;
        if (size != d->rgba_size) {
            uint8_t *buffer = av_realloc(d->rgba, size);
            if (!buffer) return AVERROR(ENOMEM);
            d->rgba = buffer; d->rgba_size = size;
        }
        d->scaler = sws_getCachedContext(d->scaler, f->width, f->height, f->format,
            width, height, AV_PIX_FMT_RGBA, SWS_BILINEAR | SWS_ACCURATE_RND, NULL, NULL, NULL);
        if (!d->scaler) return AVERROR(ENOMEM);
        const int *coefficients = sws_getCoefficients(f->colorspace == AVCOL_SPC_BT709 ? SWS_CS_ITU709 : SWS_CS_DEFAULT);
        sws_setColorspaceDetails(d->scaler, coefficients, f->color_range == AVCOL_RANGE_JPEG,
            coefficients, 1, 0, 1 << 16, 1 << 16);
        uint8_t *pixels[4] = {d->rgba, NULL, NULL, NULL}; int strides[4] = {width * 4, 0, 0, 0};
        if (sws_scale(d->scaler, (const uint8_t *const *)f->data, f->linesize, 0, f->height, pixels, strides) <= 0) return AVERROR_INVALIDDATA;
        event->data = d->rgba; event->size = size; event->width = width; event->height = height;
        AVRational rate = av_guess_frame_rate(d->format, d->format->streams[d->stream[0]], f);
        event->duration = rate.num > 0 && rate.den > 0 ? av_q2d(av_inv_q(rate)) : 1.0 / 30.0;
    } else {
        if (f->ch_layout.nb_channels < 1 || f->ch_layout.nb_channels > 8 || f->sample_rate < 8000 || f->sample_rate > 192000 || f->nb_samples < 1 || f->nb_samples > ADM_PCM_SAMPLES) return AVERROR(EFBIG);
        if (!d->resampler || d->source_rate != f->sample_rate || d->source_format != f->format || av_channel_layout_compare(&d->source_layout, &f->ch_layout)) {
            swr_free(&d->resampler); av_channel_layout_uninit(&d->source_layout);
            AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
            int result = swr_alloc_set_opts2(&d->resampler, &stereo, AV_SAMPLE_FMT_FLT, 48000,
                &f->ch_layout, f->format, f->sample_rate, 0, NULL);
            if (result < 0 || (result = swr_init(d->resampler)) < 0) return result;
            if ((result = av_channel_layout_copy(&d->source_layout, &f->ch_layout)) < 0) return result;
            d->source_rate = f->sample_rate; d->source_format = f->format;
        }
        int64_t count = av_rescale_rnd(swr_get_delay(d->resampler, f->sample_rate) + f->nb_samples, 48000, f->sample_rate, AV_ROUND_UP);
        if (count > ADM_PCM_SAMPLES) return AVERROR(EFBIG);
        event->time -= swr_get_delay(d->resampler, f->sample_rate) / (double)f->sample_rate;
        uint8_t *samples[1] = {d->pcm};
        int got = swr_convert(d->resampler, samples, ADM_PCM_SAMPLES, (const uint8_t **)f->extended_data, f->nb_samples);
        if (got < 0) return got;
        event->samples = got; event->data = d->pcm; event->size = (size_t)got * 2 * sizeof(float);
        event->duration = got / 48000.0;
    }
    d->next_time[kind] = event->time + event->duration;
    return 1;
}
int adm_next(ADMDecoder *d, ADMFrame *event) {
    if (!d || !event) return AVERROR(EINVAL);
    for (;;) {
        if (interrupted(d)) return AVERROR_EXIT;
        if (d->pending >= 0) {
            int kind = d->pending;
            int result = avcodec_receive_frame(d->codec[kind], d->frame);
            if (result >= 0) {
                result = convert_frame(d, kind, event); av_frame_unref(d->frame);
                if (result < 0 || event->size) return result;
                continue;
            }
            if (result == AVERROR_EOF) d->drained[kind] = 1;
            else if (result != AVERROR(EAGAIN)) return result;
            d->pending = -1;
        }
        if (d->eof) {
            int kind = !d->drained[0] ? 0 : !d->drained[1] ? 1 : -1;
            if (kind < 0) {
                if (!d->resampler) return 0;
                uint8_t *samples[1] = {d->pcm};
                int got = swr_convert(d->resampler, samples, ADM_PCM_SAMPLES, NULL, 0);
                if (got <= 0) return got;
                memset(event, 0, sizeof(*event));
                event->kind = 2; event->data = d->pcm;
                event->samples = got; event->size = (size_t)got * 2 * sizeof(float);
                event->time = d->next_time[1]; event->duration = got / 48000.0;
                d->next_time[1] += event->duration;
                return 1;
            }
            if (!d->flush[kind]) {
                int result = avcodec_send_packet(d->codec[kind], NULL);
                if (result < 0 && result != AVERROR_EOF) return result;
                d->flush[kind] = 1;
            } else { d->drained[kind] = 1; continue; }
            d->pending = kind;
            continue;
        }
        int result = av_read_frame(d->format, d->packet);
        if (result == AVERROR_EOF) { d->eof = 1; continue; }
        if (result < 0) return result;
        if (d->packet->size < 0 || d->packet->size > ADM_PACKET_LIMIT) { av_packet_unref(d->packet); return AVERROR(EFBIG); }
        int kind = d->packet->stream_index == d->stream[0] ? 0 : d->packet->stream_index == d->stream[1] ? 1 : -1;
        if (kind >= 0) result = avcodec_send_packet(d->codec[kind], d->packet);
        av_packet_unref(d->packet);
        if (result < 0) return result;
        d->pending = kind;
    }
}
int adm_seek(ADMDecoder *d, double seconds) {
    if (!d || !isfinite(seconds) || seconds < 0 || seconds > 86400) return AVERROR(EINVAL);
    int result = avformat_seek_file(d->format, -1, INT64_MIN, (int64_t)(seconds * AV_TIME_BASE), INT64_MAX, 0);
    if (result < 0) return result;
    av_packet_unref(d->packet); av_frame_unref(d->frame);
    for (int i = 0; i < 2; i++) {
        if (d->codec[i]) avcodec_flush_buffers(d->codec[i]);
        d->flush[i] = 0; d->drained[i] = d->codec[i] == NULL; d->next_time[i] = seconds;
    }
    d->pending = -1; d->eof = 0; swr_free(&d->resampler);
    return 0;
}
void adm_error(int error, char *buffer, size_t size) { if (buffer && size) av_strerror(error, buffer, size); }
const char *adm_license(void) { return avutil_license(); }
