#include "lanlu_avformat_bridge.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/dict.h>
#include <libavutil/mathematics.h>

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LLAV_MAX_STREAMS 4096
#define LLAV_MAX_EVENTS 2000000
#define LLAV_MAX_PAYLOAD (16 * 1024 * 1024)

struct LLAVCancel {
    atomic_int requested;
};

typedef struct {
    LLAVTrack value;
    int64_t event_capacity;
    AVCodecContext *decoder;
} LLAVTrackBuilder;

static char *llav_strdup(const char *value) {
    const char *source = value ? value : "";
    size_t size = strlen(source) + 1;
    char *copy = malloc(size);
    if (copy) {
        memcpy(copy, source, size);
    }
    return copy;
}

static char *llav_error_string(const char *context, int error_code) {
    char detail[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(error_code, detail, sizeof(detail));
    size_t context_size = strlen(context);
    size_t detail_size = strlen(detail);
    char *message = malloc(context_size + detail_size + 3);
    if (!message) {
        return llav_strdup("out of memory while formatting FFmpeg error");
    }
    memcpy(message, context, context_size);
    message[context_size] = ':';
    message[context_size + 1] = ' ';
    memcpy(message + context_size + 2, detail, detail_size + 1);
    return message;
}

static int llav_interrupted(void *opaque) {
    LLAVCancel *cancel = opaque;
    return cancel && atomic_load_explicit(&cancel->requested, memory_order_relaxed) != 0;
}

static int llav_http_options(AVDictionary **options, const char *bearer, char **error) {
    const char *const reconnect_options[][2] = {
        {"reconnect", "1"},
        {"reconnect_on_network_error", "1"},
        {"reconnect_streamed", "1"},
        {"reconnect_delay_max", "5"},
        {"reconnect_delay_total_max", "120"},
    };
    for (size_t index = 0; index < sizeof(reconnect_options) / sizeof(reconnect_options[0]); index++) {
        int status = av_dict_set(options, reconnect_options[index][0], reconnect_options[index][1], 0);
        if (status < 0) {
            *error = llav_error_string("failed to prepare HTTP reconnect options", status);
            return status;
        }
    }
    if (!bearer || !bearer[0]) {
        return 0;
    }
    if (strchr(bearer, '\r') || strchr(bearer, '\n')) {
        *error = llav_strdup("invalid bearer token characters");
        return AVERROR(EINVAL);
    }
    const char prefix[] = "Authorization: Bearer ";
    const char suffix[] = "\r\n";
    size_t bearer_size = strlen(bearer);
    if (bearer_size > SIZE_MAX - sizeof(prefix) - sizeof(suffix)) {
        *error = llav_strdup("bearer token is too large");
        return AVERROR(E2BIG);
    }
    size_t header_size = (sizeof(prefix) - 1) + bearer_size + (sizeof(suffix) - 1);
    char *header = malloc(header_size + 1);
    if (!header) {
        *error = llav_strdup("out of memory while preparing HTTP authorization");
        return AVERROR(ENOMEM);
    }
    memcpy(header, prefix, sizeof(prefix) - 1);
    memcpy(header + sizeof(prefix) - 1, bearer, bearer_size);
    memcpy(header + sizeof(prefix) - 1 + bearer_size, suffix, sizeof(suffix));
    int status = av_dict_set(options, "headers", header, 0);
    free(header);
    if (status < 0) {
        *error = llav_error_string("failed to prepare HTTP authorization", status);
    }
    return status;
}

static AVFormatContext *llav_open(const char *url, const char *bearer, LLAVCancel *cancel, char **error) {
    AVFormatContext *format = avformat_alloc_context();
    if (!format) {
        *error = llav_strdup("avformat_alloc_context failed");
        return NULL;
    }
    format->interrupt_callback.callback = llav_interrupted;
    format->interrupt_callback.opaque = cancel;
    AVDictionary *options = NULL;
    int status = llav_http_options(&options, bearer, error);
    if (status < 0) {
        avformat_free_context(format);
        return NULL;
    }
    status = avformat_open_input(&format, url, NULL, &options);
    av_dict_free(&options);
    if (status < 0) {
        *error = llav_error_string("avformat_open_input failed", status);
        avformat_close_input(&format);
        return NULL;
    }
    status = avformat_find_stream_info(format, NULL);
    if (status < 0) {
        *error = llav_error_string("avformat_find_stream_info failed", status);
        avformat_close_input(&format);
        return NULL;
    }
    return format;
}

static int llav_supported_codec(enum AVCodecID codec_id) {
    switch (codec_id) {
        case AV_CODEC_ID_ASS:
        case AV_CODEC_ID_SSA:
        case AV_CODEC_ID_SUBRIP:
        case AV_CODEC_ID_WEBVTT:
        case AV_CODEC_ID_MOV_TEXT:
            return 1;
        default:
            return 0;
    }
}

static int llav_is_text_codec(enum AVCodecID codec_id) {
    const AVCodecDescriptor *descriptor = avcodec_descriptor_get(codec_id);
    return descriptor && (descriptor->props & AV_CODEC_PROP_TEXT_SUB) != 0;
}

static const char *llav_metadata(AVDictionary *metadata, const char *key) {
    AVDictionaryEntry *entry = av_dict_get(metadata, key, NULL, 0);
    return entry && entry->value ? entry->value : "";
}

static int64_t llav_to_ms(int64_t value, AVRational time_base) {
    if (value == AV_NOPTS_VALUE) {
        return 0;
    }
    return av_rescale_q(value, time_base, (AVRational){1, 1000});
}

static int llav_copy_bytes(uint8_t **destination, int64_t *destination_size,
                           const uint8_t *source, int64_t size) {
    *destination = NULL;
    *destination_size = 0;
    if (!source || size <= 0) {
        return 0;
    }
    if (size > LLAV_MAX_PAYLOAD) {
        return AVERROR(E2BIG);
    }
    uint8_t *copy = malloc((size_t)size);
    if (!copy) {
        return AVERROR(ENOMEM);
    }
    memcpy(copy, source, (size_t)size);
    *destination = copy;
    *destination_size = size;
    return 0;
}

static void llav_stream_info_clear(LLAVStreamInfo *info) {
    if (!info) {
        return;
    }
    free(info->codec_name);
    free(info->title);
    free(info->language);
    free(info->unsupported_reason);
    memset(info, 0, sizeof(*info));
}

static int llav_fill_stream_info(LLAVStreamInfo *output, AVStream *stream) {
    enum AVCodecID codec_id = stream->codecpar->codec_id;
    const char *codec_name = avcodec_get_name(codec_id);
    int supported = llav_supported_codec(codec_id);
    memset(output, 0, sizeof(*output));
    output->stream_index = stream->index;
    output->codec_id = codec_id;
    output->codec_name = llav_strdup(codec_name);
    output->title = llav_strdup(llav_metadata(stream->metadata, "title"));
    output->language = llav_strdup(llav_metadata(stream->metadata, "language"));
    output->is_default = (stream->disposition & AV_DISPOSITION_DEFAULT) != 0;
    output->is_forced = (stream->disposition & AV_DISPOSITION_FORCED) != 0;
    output->is_text = llav_is_text_codec(codec_id);
    output->supported = supported;
    output->unsupported_reason = llav_strdup(supported ? "" : "bitmap or unsupported subtitle codec");
    if (!output->codec_name || !output->title || !output->language || !output->unsupported_reason) {
        llav_stream_info_clear(output);
        return AVERROR(ENOMEM);
    }
    return 0;
}

uint32_t llav_libavformat_version(void) {
    return avformat_version();
}

uint32_t llav_libavcodec_version(void) {
    return avcodec_version();
}

uint32_t llav_compiled_libavformat_version(void) {
    return LIBAVFORMAT_VERSION_INT;
}

uint32_t llav_compiled_libavcodec_version(void) {
    return LIBAVCODEC_VERSION_INT;
}

LLAVCancel *llav_cancel_new(void) {
    LLAVCancel *cancel = calloc(1, sizeof(*cancel));
    if (cancel) {
        atomic_init(&cancel->requested, 0);
    }
    return cancel;
}

void llav_cancel_request(LLAVCancel *cancel) {
    if (cancel) {
        atomic_store_explicit(&cancel->requested, 1, memory_order_relaxed);
    }
}

void llav_cancel_free(LLAVCancel *cancel) {
    free(cancel);
}

LLAVProbeResult *llav_probe_subtitle_streams(const char *url, const char *bearer, LLAVCancel *cancel) {
    LLAVProbeResult *result = calloc(1, sizeof(*result));
    if (!result) {
        return NULL;
    }
    AVFormatContext *format = llav_open(url, bearer, cancel, &result->error);
    if (!format) {
        return result;
    }
    if (format->nb_streams > LLAV_MAX_STREAMS) {
        result->error = llav_strdup("media contains too many streams");
        avformat_close_input(&format);
        return result;
    }
    int64_t subtitle_count = 0;
    for (unsigned int index = 0; index < format->nb_streams; index++) {
        if (format->streams[index]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            subtitle_count++;
        }
    }
    if (subtitle_count > 0) {
        result->items = calloc((size_t)subtitle_count, sizeof(*result->items));
        if (!result->items) {
            result->error = llav_strdup("out of memory while allocating subtitle stream list");
            avformat_close_input(&format);
            return result;
        }
    }
    for (unsigned int index = 0; index < format->nb_streams; index++) {
        AVStream *stream = format->streams[index];
        if (stream->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) {
            continue;
        }
        int status = llav_fill_stream_info(&result->items[result->count], stream);
        if (status < 0) {
            result->error = llav_error_string("subtitle metadata allocation failed", status);
            break;
        }
        result->count++;
    }
    avformat_close_input(&format);
    return result;
}

void llav_probe_result_free(LLAVProbeResult *result) {
    if (!result) {
        return;
    }
    for (int64_t index = 0; index < result->count; index++) {
        llav_stream_info_clear(&result->items[index]);
    }
    free(result->items);
    free(result->error);
    free(result);
}

static void llav_track_clear(LLAVTrack *track) {
    if (!track) {
        return;
    }
    free(track->codec_name);
    free(track->codec_private);
    for (int64_t index = 0; index < track->event_count; index++) {
        free(track->events[index].payload);
    }
    free(track->events);
    memset(track, 0, sizeof(*track));
}

static void llav_builder_clear(LLAVTrackBuilder *builder) {
    if (!builder) {
        return;
    }
    llav_track_clear(&builder->value);
    avcodec_free_context(&builder->decoder);
    builder->event_capacity = 0;
}

static int llav_append_event(LLAVTrackBuilder *builder, int64_t start_ms, int64_t duration_ms,
                             int32_t payload_kind, const uint8_t *payload, int64_t payload_size) {
    if (!payload || payload_size <= 0) {
        return 0;
    }
    if (builder->value.event_count >= LLAV_MAX_EVENTS) {
        return AVERROR(E2BIG);
    }
    if (builder->value.event_count == builder->event_capacity) {
        int64_t next_capacity = builder->event_capacity == 0 ? 128 : builder->event_capacity * 2;
        if (next_capacity > LLAV_MAX_EVENTS) {
            next_capacity = LLAV_MAX_EVENTS;
        }
        LLAVEvent *events = realloc(builder->value.events, (size_t)next_capacity * sizeof(*events));
        if (!events) {
            return AVERROR(ENOMEM);
        }
        memset(events + builder->event_capacity, 0,
               (size_t)(next_capacity - builder->event_capacity) * sizeof(*events));
        builder->value.events = events;
        builder->event_capacity = next_capacity;
    }
    LLAVEvent *event = &builder->value.events[builder->value.event_count];
    int status = llav_copy_bytes(&event->payload, &event->payload_size, payload, payload_size);
    if (status < 0) {
        return status;
    }
    event->start_ms = start_ms < 0 ? 0 : start_ms;
    event->duration_ms = duration_ms < 0 ? 0 : duration_ms;
    event->payload_kind = payload_kind;
    builder->value.event_count++;
    return 0;
}

static const char *llav_ass_dialogue_text(const char *ass) {
    if (!ass) return NULL;
    const char *cursor = ass;
    for (int field = 0; field < 8; field++) {
        cursor = strchr(cursor, ',');
        if (!cursor) return ass;
        cursor++;
    }
    return cursor;
}

static int llav_decode_mov_text(LLAVTrackBuilder *builder, AVPacket *packet, AVRational time_base) {
    AVSubtitle subtitle = {0};
    int got_subtitle = 0;
    int status = avcodec_decode_subtitle2(builder->decoder, &subtitle, &got_subtitle, packet);
    if (status < 0) return status;
    if (!got_subtitle) return 0;

    int64_t packet_start = llav_to_ms(packet->pts, time_base);
    int64_t start_ms = packet_start + subtitle.start_display_time;
    int64_t duration_ms = subtitle.end_display_time > subtitle.start_display_time
        ? (int64_t)subtitle.end_display_time - subtitle.start_display_time
        : llav_to_ms(packet->duration, time_base);
    for (unsigned int index = 0; index < subtitle.num_rects; index++) {
        AVSubtitleRect *rect = subtitle.rects[index];
        if (!rect) continue;
        const char *text = rect->text && rect->text[0]
            ? rect->text : llav_ass_dialogue_text(rect->ass);
        if (!text || !text[0]) continue;
        status = llav_append_event(builder, start_ms, duration_ms, LLAV_PAYLOAD_PLAIN_TEXT,
                                   (const uint8_t *)text, (int64_t)strlen(text));
        if (status < 0) break;
    }
    avsubtitle_free(&subtitle);
    return status < 0 ? status : 0;
}

static int llav_builder_init(LLAVTrackBuilder *builder, AVStream *stream) {
    memset(builder, 0, sizeof(*builder));
    builder->value.stream_index = stream->index;
    builder->value.codec_name = llav_strdup(avcodec_get_name(stream->codecpar->codec_id));
    if (!builder->value.codec_name) {
        return AVERROR(ENOMEM);
    }
    int status = llav_copy_bytes(&builder->value.codec_private, &builder->value.codec_private_size,
                                 stream->codecpar->extradata, stream->codecpar->extradata_size);
    if (status < 0) {
        return status;
    }
    if (stream->codecpar->codec_id == AV_CODEC_ID_MOV_TEXT) {
        const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
        if (!codec) return AVERROR_DECODER_NOT_FOUND;
        builder->decoder = avcodec_alloc_context3(codec);
        if (!builder->decoder) return AVERROR(ENOMEM);
        status = avcodec_parameters_to_context(builder->decoder, stream->codecpar);
        if (status < 0) return status;
        status = avcodec_open2(builder->decoder, codec, NULL);
        if (status < 0) return status;
    }
    return 0;
}

LLAVExtractResult *llav_extract_subtitle_tracks(const char *url, const char *bearer, LLAVCancel *cancel) {
    LLAVExtractResult *result = calloc(1, sizeof(*result));
    if (!result) {
        return NULL;
    }
    AVFormatContext *format = llav_open(url, bearer, cancel, &result->error);
    if (!format) {
        result->cancelled = llav_interrupted(cancel);
        return result;
    }
    if (format->nb_streams > LLAV_MAX_STREAMS) {
        result->error = llav_strdup("media contains too many streams");
        avformat_close_input(&format);
        return result;
    }
    int64_t supported_count = 0;
    for (unsigned int index = 0; index < format->nb_streams; index++) {
        AVStream *stream = format->streams[index];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE &&
            llav_supported_codec(stream->codecpar->codec_id)) {
            supported_count++;
        }
    }
    LLAVTrackBuilder *builders = supported_count > 0
        ? calloc((size_t)supported_count, sizeof(*builders)) : NULL;
    int32_t *builder_by_stream = calloc(format->nb_streams, sizeof(*builder_by_stream));
    if ((supported_count > 0 && !builders) || !builder_by_stream) {
        result->error = llav_strdup("out of memory while allocating subtitle extractors");
        free(builders);
        free(builder_by_stream);
        avformat_close_input(&format);
        return result;
    }
    for (unsigned int index = 0; index < format->nb_streams; index++) {
        builder_by_stream[index] = -1;
    }
    int status = 0;
    int64_t builder_count = 0;
    for (unsigned int index = 0; index < format->nb_streams; index++) {
        AVStream *stream = format->streams[index];
        if (stream->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE ||
            !llav_supported_codec(stream->codecpar->codec_id)) {
            continue;
        }
        status = llav_builder_init(&builders[builder_count], stream);
        if (status < 0) {
            result->error = llav_error_string("subtitle decoder initialization failed", status);
            llav_builder_clear(&builders[builder_count]);
            break;
        }
        builder_by_stream[index] = (int32_t)builder_count;
        builder_count++;
    }
    AVPacket *packet = status < 0 ? NULL : av_packet_alloc();
    if (status >= 0 && !packet) {
        status = AVERROR(ENOMEM);
        result->error = llav_strdup("av_packet_alloc failed");
    }
    while (status >= 0 && (status = av_read_frame(format, packet)) >= 0) {
        if (packet->stream_index >= 0 && (unsigned int)packet->stream_index < format->nb_streams) {
            int32_t builder_index = builder_by_stream[packet->stream_index];
            if (builder_index >= 0) {
                AVStream *stream = format->streams[packet->stream_index];
                LLAVTrackBuilder *builder = &builders[builder_index];
                int event_status;
                if (stream->codecpar->codec_id == AV_CODEC_ID_MOV_TEXT) {
                    event_status = llav_decode_mov_text(builder, packet, stream->time_base);
                } else {
                    int kind = (stream->codecpar->codec_id == AV_CODEC_ID_ASS ||
                                stream->codecpar->codec_id == AV_CODEC_ID_SSA)
                        ? LLAV_PAYLOAD_MATROSKA_ASS_CHUNK : LLAV_PAYLOAD_PLAIN_TEXT;
                    event_status = llav_append_event(builder, llav_to_ms(packet->pts, stream->time_base),
                        llav_to_ms(packet->duration, stream->time_base), kind, packet->data, packet->size);
                }
                if (event_status < 0) {
                    status = event_status;
                    result->error = llav_error_string("subtitle packet extraction failed", event_status);
                }
            }
        }
        av_packet_unref(packet);
    }
    if (status == AVERROR_EOF) {
        AVPacket flush_packet = {0};
        flush_packet.pts = AV_NOPTS_VALUE;
        for (int64_t index = 0; index < builder_count; index++) {
            if (!builders[index].decoder) continue;
            int flush_status = llav_decode_mov_text(&builders[index], &flush_packet, (AVRational){1, 1000});
            if (flush_status < 0 && flush_status != AVERROR_EOF) {
                status = flush_status;
                result->error = llav_error_string("subtitle decoder flush failed", flush_status);
                break;
            }
        }
        if (!result->error) status = AVERROR_EOF;
    }
    if (packet) {
        av_packet_unref(packet);
        av_packet_free(&packet);
    }
    if (status == AVERROR_EXIT || llav_interrupted(cancel)) {
        result->cancelled = 1;
        free(result->error);
        result->error = NULL;
    } else if (status < 0 && status != AVERROR_EOF && !result->error) {
        result->error = llav_error_string("av_read_frame failed", status);
    }
    if (!result->error && !result->cancelled) {
        result->tracks = calloc((size_t)builder_count, sizeof(*result->tracks));
        if (!result->tracks && builder_count > 0) {
            result->error = llav_strdup("out of memory while finalizing subtitle tracks");
        } else {
            result->track_count = builder_count;
            for (int64_t index = 0; index < builder_count; index++) {
                result->tracks[index] = builders[index].value;
                memset(&builders[index].value, 0, sizeof(builders[index].value));
            }
        }
    }
    for (int64_t index = 0; index < builder_count; index++) {
        llav_builder_clear(&builders[index]);
    }
    free(builders);
    free(builder_by_stream);
    avformat_close_input(&format);
    return result;
}

void llav_extract_result_free(LLAVExtractResult *result) {
    if (!result) {
        return;
    }
    for (int64_t index = 0; index < result->track_count; index++) {
        llav_track_clear(&result->tracks[index]);
    }
    free(result->tracks);
    free(result->error);
    free(result);
}
