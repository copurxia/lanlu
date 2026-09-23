#ifndef LANLU_ASS_COMPAT_H
#define LANLU_ASS_COMPAT_H

/*
 * Minimal ABI declarations for systems that ship libass.so.9 without the
 * development headers.  When <ass/ass.h> exists the bridge uses it instead.
 * libass documents ASS_Image's prefix as ABI-stable; every other object stays
 * opaque.  The declared API baseline is libass 0.13.0.1 (soname 9).
 */

#include <stddef.h>
#include <stdint.h>

#define LIBASS_VERSION 0x01300001
#define ASS_FONTPROVIDER_AUTODETECT 1

typedef struct ass_library ASS_Library;
typedef struct ass_renderer ASS_Renderer;
typedef struct ass_track ASS_Track;

typedef struct ass_image {
    int w;
    int h;
    int stride;
    unsigned char *bitmap;
    uint32_t color;
    int dst_x;
    int dst_y;
    struct ass_image *next;
} ASS_Image;

int ass_library_version(void);
ASS_Library *ass_library_init(void);
void ass_library_done(ASS_Library *library);
ASS_Renderer *ass_renderer_init(ASS_Library *library);
void ass_renderer_done(ASS_Renderer *renderer);
void ass_set_frame_size(ASS_Renderer *renderer, int width, int height);
void ass_set_storage_size(ASS_Renderer *renderer, int width, int height);
void ass_set_margins(ASS_Renderer *renderer, int top, int bottom, int left, int right);
void ass_set_use_margins(ASS_Renderer *renderer, int use);
void ass_set_pixel_aspect(ASS_Renderer *renderer, double pixel_aspect);
void ass_set_fonts(ASS_Renderer *renderer, const char *default_font,
                   const char *default_family, int provider,
                   const char *config, int update);
ASS_Track *ass_read_memory(ASS_Library *library, char *data, size_t size,
                           const char *codepage);
ASS_Track *ass_new_track(ASS_Library *library);
void ass_process_codec_private(ASS_Track *track, const char *data, int size);
void ass_process_chunk(ASS_Track *track, const char *data, int size,
                       long long start_ms, long long duration_ms);
void ass_flush_events(ASS_Track *track);
void ass_free_track(ASS_Track *track);
ASS_Image *ass_render_frame(ASS_Renderer *renderer, ASS_Track *track,
                            long long now_ms, int *changed);

#endif
