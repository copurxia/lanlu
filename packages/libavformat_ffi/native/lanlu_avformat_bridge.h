#ifndef LANLU_AVFORMAT_BRIDGE_H
#define LANLU_AVFORMAT_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    LLAV_PAYLOAD_MATROSKA_ASS_CHUNK = 1,
    LLAV_PAYLOAD_PLAIN_TEXT = 2,
};

typedef struct LLAVCancel LLAVCancel;

typedef struct {
    int32_t stream_index;
    int32_t codec_id;
    char *codec_name;
    char *title;
    char *language;
    int32_t is_default;
    int32_t is_forced;
    int32_t is_text;
    int32_t supported;
    char *unsupported_reason;
} LLAVStreamInfo;

typedef struct {
    LLAVStreamInfo *items;
    int64_t count;
    char *error;
} LLAVProbeResult;

typedef struct {
    int64_t start_ms;
    int64_t duration_ms;
    int32_t payload_kind;
    uint8_t *payload;
    int64_t payload_size;
} LLAVEvent;

typedef struct {
    int32_t stream_index;
    char *codec_name;
    uint8_t *codec_private;
    int64_t codec_private_size;
    LLAVEvent *events;
    int64_t event_count;
} LLAVTrack;

typedef struct {
    LLAVTrack *tracks;
    int64_t track_count;
    char *error;
    int32_t cancelled;
} LLAVExtractResult;

uint32_t llav_libavformat_version(void);
uint32_t llav_libavcodec_version(void);
uint32_t llav_compiled_libavformat_version(void);
uint32_t llav_compiled_libavcodec_version(void);

LLAVCancel *llav_cancel_new(void);
void llav_cancel_request(LLAVCancel *cancel);
void llav_cancel_free(LLAVCancel *cancel);

LLAVProbeResult *llav_probe_subtitle_streams(const char *url, const char *bearer, LLAVCancel *cancel);
void llav_probe_result_free(LLAVProbeResult *result);

LLAVExtractResult *llav_extract_subtitle_tracks(const char *url, const char *bearer, LLAVCancel *cancel);
void llav_extract_result_free(LLAVExtractResult *result);

#ifdef __cplusplus
}
#endif

#endif
