// Reproduces decodeFileToRgba's handle/unref sequence against vips_shim.c.
// Before the fix every conversion aliased the input, so unref'ing each handle
// freed the same VIMG repeatedly (heap corruption). ASAN must stay silent.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int w,h,b; unsigned char* px; } VIMG;
void* vips_image_new_from_file(const char* fn, ...);
int vips_autorot(void* in, void** out, ...);
int vips_colourspace(void* in, void** out, int space, ...);
int vips_cast_uchar(void* in, void** out, ...);
int vips_bandjoin_const1(void* in, void** out, double c, ...);
void* vips_image_write_to_memory(void* im, size_t* size);
void g_object_unref(void* o);
int vips_image_get_width(void* im);
int vips_image_get_height(void* im);
int vips_image_get_bands(void* im);

static int round_trip(const char* path) {
    void* in = vips_image_new_from_file(path);
    if (!in) { printf("decode failed\n"); return -1; }
    void* rot = 0; void* srgb = 0; void* u8 = 0; void* norm = 0; void* mem = 0;
    if (vips_autorot(in, &rot) != 0 || !rot) { printf("autorot failed\n"); return -1; }
    if (vips_colourspace(rot, &srgb, 0) != 0 || !srgb) { printf("colourspace failed\n"); return -1; }
    if (vips_cast_uchar(srgb, &u8) != 0 || !u8) { printf("cast failed\n"); return -1; }
    int bands = vips_image_get_bands(u8);
    if (bands == 3) {
        if (vips_bandjoin_const1(u8, &norm, 255.0) != 0 || !norm) { printf("bandjoin failed\n"); return -1; }
    } else { norm = u8; u8 = 0; }
    int w = vips_image_get_width(norm), h = vips_image_get_height(norm);
    size_t n = 0;
    mem = vips_image_write_to_memory(norm, &n);
    if (!mem || n != (size_t)w*h*4) { printf("write_to_memory bad: %zu vs %d\n", n, w*h*4); return -1; }
    free(mem);
    g_object_unref(in); g_object_unref(rot); g_object_unref(srgb); g_object_unref(u8); g_object_unref(norm);
    return 0;
}

// backdrop / cover 链路：resize -> extract_area -> gaussblur，各自独立 unref。
int vips_resize(void* in, void** out, double scale, ...);
int vips_extract_area(void* in, void** out, int left,int top,int width,int height, ...);
int vips_gaussblur(void* in, void** out, double s, ...);

static int resize_chain(const char* path) {
    void* in = vips_image_new_from_file(path);
    if (!in) { printf("decode failed\n"); return -1; }
    void* rs = 0; void* ar = 0; void* gb = 0;
    if (vips_resize(in, &rs, 0.5) != 0 || !rs) { printf("resize failed\n"); return -1; }
    if (vips_extract_area(rs, &ar, 0, 0, 32, 32) != 0 || !ar) { printf("extract failed\n"); return -1; }
    if (vips_gaussblur(ar, &gb, 2.0) != 0 || !gb) { printf("blur failed\n"); return -1; }
    size_t n = 0;
    void* mem = vips_image_write_to_memory(gb, &n);
    if (!mem || n == 0) { printf("blur write failed\n"); return -1; }
    free(mem);
    g_object_unref(in); g_object_unref(rs); g_object_unref(ar); g_object_unref(gb);
    return 0;
}

int main(int argc, char** argv) {
    for (int i = 1; i < argc; i++) {
        for (int k = 0; k < 3; k++) {
            if (round_trip(argv[i]) != 0) return 1;
        }
        printf("ok: %s (3 rounds)\n", argv[i]);
        if (resize_chain(argv[i]) != 0) return 1;
        printf("ok: %s (resize/extract/blur chain)\n", argv[i]);
    }
    return 0;
}
