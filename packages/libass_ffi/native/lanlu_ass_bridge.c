#include "lanlu_ass_bridge.h"

#if defined(__has_include)
#  if __has_include(<ass/ass.h>)
#    include <ass/ass.h>
#  else
#    include "lanlu_ass_compat.h"
#  endif
#else
#  include <ass/ass.h>
#endif

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define LLASS_MAX_DIMENSION 16384
#define LLASS_MAX_INPUT (64 * 1024 * 1024)
#define LLASS_MAX_TRACKS 1024

struct LLASSRenderer {
    ASS_Library *library;
    ASS_Renderer *renderer;
    int32_t width;
    int32_t height;
};

struct LLASSTrack {
    ASS_Track *track;
};

static char *llass_strdup(const char *value) {
    size_t size = strlen(value) + 1;
    char *copy = malloc(size);
    if (copy) {
        memcpy(copy, value, size);
    }
    return copy;
}

static int llass_dimensions_valid(int32_t width, int32_t height) {
    return width > 0 && height > 0 && width <= LLASS_MAX_DIMENSION && height <= LLASS_MAX_DIMENSION &&
        (int64_t)width * height <= INT64_MAX / 4;
}

static int llass_input_valid(const uint8_t *data, int64_t size) {
    return size >= 0 && size <= LLASS_MAX_INPUT && (size == 0 || data != NULL);
}

uint32_t llass_runtime_version(void) {
    return (uint32_t)ass_library_version();
}

uint32_t llass_compiled_version(void) {
    return LIBASS_VERSION;
}

LLASSRenderer *llass_renderer_new(int32_t width, int32_t height, char **error) {
    if (error) {
        *error = NULL;
    }
    if (!llass_dimensions_valid(width, height)) {
        if (error) *error = llass_strdup("invalid libass renderer dimensions");
        return NULL;
    }
    LLASSRenderer *value = calloc(1, sizeof(*value));
    if (!value) {
        if (error) *error = llass_strdup("failed to allocate libass renderer owner");
        return NULL;
    }
    value->library = ass_library_init();
    if (!value->library) {
        if (error) *error = llass_strdup("ass_library_init failed");
        free(value);
        return NULL;
    }
    value->renderer = ass_renderer_init(value->library);
    if (!value->renderer) {
        if (error) *error = llass_strdup("ass_renderer_init failed");
        ass_library_done(value->library);
        free(value);
        return NULL;
    }
    value->width = width;
    value->height = height;
    ass_set_frame_size(value->renderer, width, height);
    ass_set_storage_size(value->renderer, width, height);
    ass_set_margins(value->renderer, 0, 0, 0, 0);
    ass_set_use_margins(value->renderer, 0);
    ass_set_pixel_aspect(value->renderer, 1.0);
    ass_set_fonts(value->renderer, NULL, NULL, ASS_FONTPROVIDER_AUTODETECT, NULL, 1);
    return value;
}

int32_t llass_renderer_configure(LLASSRenderer *renderer, int32_t width, int32_t height,
                                 double pixel_aspect, char **error) {
    if (error) *error = NULL;
    if (!renderer || !renderer->renderer || !llass_dimensions_valid(width, height) ||
        pixel_aspect <= 0.0 || pixel_aspect > 100.0) {
        if (error) *error = llass_strdup("invalid libass renderer configuration");
        return -1;
    }
    renderer->width = width;
    renderer->height = height;
    ass_set_frame_size(renderer->renderer, width, height);
    ass_set_storage_size(renderer->renderer, width, height);
    ass_set_pixel_aspect(renderer->renderer, pixel_aspect);
    return 0;
}

void llass_renderer_free(LLASSRenderer *renderer) {
    if (!renderer) return;
    if (renderer->renderer) ass_renderer_done(renderer->renderer);
    if (renderer->library) ass_library_done(renderer->library);
    free(renderer);
}

LLASSTrack *llass_track_read(LLASSRenderer *renderer, const uint8_t *data, int64_t size,
                             char **error) {
    if (error) *error = NULL;
    if (!renderer || !renderer->library || !llass_input_valid(data, size) || size == 0) {
        if (error) *error = llass_strdup("invalid ASS document input");
        return NULL;
    }
    LLASSTrack *value = calloc(1, sizeof(*value));
    if (!value) {
        if (error) *error = llass_strdup("failed to allocate ASS track owner");
        return NULL;
    }
    value->track = ass_read_memory(renderer->library, (char *)data, (size_t)size, "UTF-8");
    if (!value->track) {
        if (error) *error = llass_strdup("ass_read_memory failed");
        free(value);
        return NULL;
    }
    return value;
}

LLASSTrack *llass_track_new(LLASSRenderer *renderer, const uint8_t *codec_private,
                            int64_t codec_private_size, char **error) {
    if (error) *error = NULL;
    if (!renderer || !renderer->library || !llass_input_valid(codec_private, codec_private_size)) {
        if (error) *error = llass_strdup("invalid ASS CodecPrivate input");
        return NULL;
    }
    LLASSTrack *value = calloc(1, sizeof(*value));
    if (!value) {
        if (error) *error = llass_strdup("failed to allocate ASS track owner");
        return NULL;
    }
    value->track = ass_new_track(renderer->library);
    if (!value->track) {
        if (error) *error = llass_strdup("ass_new_track failed");
        free(value);
        return NULL;
    }
    if (codec_private_size > 0) {
        ass_process_codec_private(value->track, (const char *)codec_private, (int)codec_private_size);
    }
    return value;
}

int32_t llass_track_process_chunk(LLASSTrack *track, const uint8_t *data, int64_t size,
                                  int64_t start_ms, int64_t duration_ms, char **error) {
    if (error) *error = NULL;
    if (!track || !track->track || !llass_input_valid(data, size) || size == 0 ||
        start_ms < 0 || duration_ms < 0 || size > INT_MAX) {
        if (error) *error = llass_strdup("invalid ASS event chunk");
        return -1;
    }
    ass_process_chunk(track->track, (const char *)data, (int)size, start_ms, duration_ms);
    return 0;
}

void llass_track_flush(LLASSTrack *track) {
    if (track && track->track) ass_flush_events(track->track);
}

void llass_track_free(LLASSTrack *track) {
    if (!track) return;
    if (track->track) ass_free_track(track->track);
    free(track);
}

static void llass_source_over(uint8_t *destination, uint8_t red, uint8_t green,
                              uint8_t blue, uint8_t alpha) {
    if (alpha == 0) return;
    uint32_t destination_alpha = destination[3];
    uint32_t inverse = 255u - alpha;
    uint32_t output_alpha = alpha + (destination_alpha * inverse + 127u) / 255u;
    if (output_alpha == 0) return;
    uint32_t destination_factor = (destination_alpha * inverse + 127u) / 255u;
    destination[0] = (uint8_t)((red * alpha + destination[0] * destination_factor + output_alpha / 2u) /
                               output_alpha);
    destination[1] = (uint8_t)((green * alpha + destination[1] * destination_factor + output_alpha / 2u) /
                               output_alpha);
    destination[2] = (uint8_t)((blue * alpha + destination[2] * destination_factor + output_alpha / 2u) /
                               output_alpha);
    destination[3] = (uint8_t)output_alpha;
}

static int llass_composite_image(LLASSRenderer *renderer, uint8_t *rgba, const ASS_Image *image) {
    if (!image || image->w < 0 || image->h < 0 || image->stride < image->w ||
        image->w > LLASS_MAX_DIMENSION || image->h > LLASS_MAX_DIMENSION ||
        (image->w > 0 && image->h > 0 && !image->bitmap)) {
        return -1;
    }
    uint8_t red = (uint8_t)(image->color >> 24);
    uint8_t green = (uint8_t)(image->color >> 16);
    uint8_t blue = (uint8_t)(image->color >> 8);
    uint8_t color_opacity = (uint8_t)(255u - (image->color & 0xffu));
    for (int32_t source_y = 0; source_y < image->h; source_y++) {
        int64_t destination_y = (int64_t)image->dst_y + source_y;
        if (destination_y < 0 || destination_y >= renderer->height) continue;
        for (int32_t source_x = 0; source_x < image->w; source_x++) {
            int64_t destination_x = (int64_t)image->dst_x + source_x;
            if (destination_x < 0 || destination_x >= renderer->width) continue;
            uint8_t coverage = image->bitmap[(int64_t)source_y * image->stride + source_x];
            uint8_t alpha = (uint8_t)(((uint32_t)coverage * color_opacity + 127u) / 255u);
            int64_t offset = (destination_y * renderer->width + destination_x) * 4;
            llass_source_over(rgba + offset, red, green, blue, alpha);
        }
    }
    return 0;
}

LLASSBitmap *llass_render(LLASSRenderer *renderer, LLASSTrack *const *tracks,
                          int64_t track_count, int64_t now_ms) {
    LLASSBitmap *result = calloc(1, sizeof(*result));
    if (!result) return NULL;
    if (!renderer || !renderer->renderer || track_count < 0 || track_count > LLASS_MAX_TRACKS ||
        (track_count > 0 && !tracks)) {
        result->error = llass_strdup("invalid libass render request");
        return result;
    }
    result->width = renderer->width;
    result->height = renderer->height;
    result->rgba_size = (int64_t)renderer->width * renderer->height * 4;
    result->rgba = calloc((size_t)result->rgba_size, 1);
    if (!result->rgba) {
        result->error = llass_strdup("failed to allocate subtitle RGBA bitmap");
        return result;
    }
    for (int64_t index = 0; index < track_count; index++) {
        if (!tracks[index] || !tracks[index]->track) {
            result->error = llass_strdup("invalid ASS track in render request");
            return result;
        }
        int changed = 0;
        ASS_Image *image = ass_render_frame(renderer->renderer, tracks[index]->track, now_ms, &changed);
        if (changed > result->changed) result->changed = changed;
        while (image) {
            if (llass_composite_image(renderer, result->rgba, image) != 0) {
                result->error = llass_strdup("invalid ASS_Image returned by libass");
                return result;
            }
            image = image->next;
        }
    }
    return result;
}

void llass_bitmap_free(LLASSBitmap *bitmap) {
    if (!bitmap) return;
    free(bitmap->rgba);
    free(bitmap->error);
    free(bitmap);
}

void llass_error_free(char *error) {
    free(error);
}
