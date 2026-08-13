#ifndef LANLU_ASS_BRIDGE_H
#define LANLU_ASS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LLASSRenderer LLASSRenderer;
typedef struct LLASSTrack LLASSTrack;

typedef struct {
    int32_t canvas_width;
    int32_t canvas_height;
    int32_t x;
    int32_t y;
    int32_t width;
    int32_t height;
    int32_t changed;
    uint8_t *rgba;
    int64_t rgba_size;
    char *error;
} LLASSBitmap;

uint32_t llass_runtime_version(void);
uint32_t llass_compiled_version(void);

LLASSRenderer *llass_renderer_new(int32_t width, int32_t height, char **error);
int32_t llass_renderer_configure(LLASSRenderer *renderer, int32_t width, int32_t height,
                                 double pixel_aspect, char **error);
void llass_renderer_free(LLASSRenderer *renderer);

LLASSTrack *llass_track_read(LLASSRenderer *renderer, const uint8_t *data, int64_t size,
                             char **error);
LLASSTrack *llass_track_new(LLASSRenderer *renderer, const uint8_t *codec_private,
                            int64_t codec_private_size, char **error);
int32_t llass_track_process_chunk(LLASSTrack *track, const uint8_t *data, int64_t size,
                                  int64_t start_ms, int64_t duration_ms, char **error);
void llass_track_flush(LLASSTrack *track);
void llass_track_free(LLASSTrack *track);

LLASSBitmap *llass_render(LLASSRenderer *renderer, LLASSTrack *const *tracks,
                          int64_t track_count, int64_t now_ms);
void llass_bitmap_free(LLASSBitmap *bitmap);
void llass_error_free(char *error);

#ifdef __cplusplus
}
#endif

#endif
