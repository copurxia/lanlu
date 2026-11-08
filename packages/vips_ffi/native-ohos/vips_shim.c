#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
typedef struct { int w,h,b,refs; unsigned char* px; } VIMG;
static VIMG* mk(int w,int h){ VIMG*m=malloc(sizeof(VIMG)); m->w=w;m->h=h;m->b=4;m->refs=1; m->px=malloc((size_t)w*h*4); memset(m->px,0,(size_t)w*h*4); return m; }
/* ---- OHOS ImageSource fallback (for WebP etc), via dlopen ---- */
typedef struct { void* isrc; void* ipm; } OHH;
static OHH g_oh={0,0};
typedef int (*fn_create_from_uri)(char*,size_t,void**);
typedef int (*fn_create_pixelmap)(void*,void*,void**);
typedef void (*fn_rel)(void*);
typedef int (*fn_dopt_create)(void**); typedef int (*fn_dopt_setfmt)(void*,int); typedef void (*fn_dopt_rel)(void*);
typedef int (*fn_ii_create)(void**); typedef int (*fn_ii_getu)(void*,uint32_t*); typedef int (*fn_ii_geti)(void*,int32_t*); typedef void (*fn_ii_rel)(void*);
typedef int (*fn_getinfo)(void*,void*); typedef int (*fn_readpx)(void*,uint8_t*,size_t*);
static int oh_load(void){
  if(!g_oh.isrc){ g_oh.isrc=dlopen("libimage_source.so",RTLD_NOW|RTLD_GLOBAL); if(!g_oh.isrc) g_oh.isrc=dlopen("libimage_source.z.so",RTLD_NOW|RTLD_GLOBAL); }
  if(!g_oh.ipm){ g_oh.ipm=dlopen("libpixelmap.so",RTLD_NOW|RTLD_GLOBAL); if(!g_oh.ipm) g_oh.ipm=dlopen("libpixelmap.z.so",RTLD_NOW|RTLD_GLOBAL); }
  return g_oh.isrc && g_oh.ipm;
}
static VIMG* decode_oh(const char* path){
  if(!oh_load()) return 0;
  fn_create_from_uri f_uri=(fn_create_from_uri)dlsym(g_oh.isrc,"OH_ImageSourceNative_CreateFromUri");
  fn_create_pixelmap f_pm=(fn_create_pixelmap)dlsym(g_oh.isrc,"OH_ImageSourceNative_CreatePixelmap");
  fn_rel f_isrel=(fn_rel)dlsym(g_oh.isrc,"OH_ImageSourceNative_Release");
  fn_dopt_create f_doc=(fn_dopt_create)dlsym(g_oh.isrc,"OH_DecodingOptions_Create");
  fn_dopt_setfmt f_dof=(fn_dopt_setfmt)dlsym(g_oh.isrc,"OH_DecodingOptions_SetPixelFormat");
  fn_dopt_rel f_dor=(fn_dopt_rel)dlsym(g_oh.isrc,"OH_DecodingOptions_Release");
  fn_ii_create f_iic=(fn_ii_create)dlsym(g_oh.ipm,"OH_PixelmapImageInfo_Create");
  fn_ii_getu f_w=(fn_ii_getu)dlsym(g_oh.ipm,"OH_PixelmapImageInfo_GetWidth");
  fn_ii_getu f_h=(fn_ii_getu)dlsym(g_oh.ipm,"OH_PixelmapImageInfo_GetHeight");
  fn_ii_getu f_s=(fn_ii_getu)dlsym(g_oh.ipm,"OH_PixelmapImageInfo_GetRowStride");
  fn_ii_geti f_fmt=(fn_ii_geti)dlsym(g_oh.ipm,"OH_PixelmapImageInfo_GetPixelFormat");
  fn_ii_rel f_iir=(fn_ii_rel)dlsym(g_oh.ipm,"OH_PixelmapImageInfo_Release");
  fn_getinfo f_gi=(fn_getinfo)dlsym(g_oh.ipm,"OH_PixelmapNative_GetImageInfo");
  fn_readpx f_rp=(fn_readpx)dlsym(g_oh.ipm,"OH_PixelmapNative_ReadPixels");
  fn_rel f_pmrel=(fn_rel)dlsym(g_oh.ipm,"OH_PixelmapNative_Release");
  if(!f_uri||!f_pm||!f_doc||!f_iic||!f_gi||!f_rp) return 0;
  void* src=0; if(f_uri((char*)path,strlen(path),&src)!=0||!src) return 0;
  void* opt=0; f_doc(&opt); if(opt) f_dof(opt,3);
  void* pm=0; int e=f_pm(src,opt,&pm); if(opt&&f_dor)f_dor(opt); if(f_isrel)f_isrel(src);
  if(e!=0||!pm) return 0;
  void* info=0; f_iic(&info); f_gi(pm,info);
  uint32_t w=0,h=0,stride=0; int32_t fmt=0; f_w(info,&w); f_h(info,&h); f_s(info,&stride); f_fmt(info,&fmt);
  if(f_iir)f_iir(info);
  if(!w||!h){ if(f_pmrel)f_pmrel(pm); return 0; }
  size_t ssz=(stride?stride:(size_t)w*4)*(size_t)h; unsigned char* sbuf=malloc(ssz); size_t rsz=ssz;
  f_rp(pm,sbuf,&rsz); if(f_pmrel)f_pmrel(pm);
  VIMG* m=mk((int)w,(int)h); int ss=stride? (int)stride:(int)w*4;
  for(int y=0;y<(int)h;y++){ unsigned char* s=sbuf+(size_t)y*ss; unsigned char* d=m->px+(size_t)y*w*4; for(int x=0;x<(int)w;x++){ unsigned char r=s[x*4],g=s[x*4+1],b=s[x*4+2],a=s[x*4+3]; if(fmt==4){unsigned char t=r;r=b;b=t;} d[x*4]=r;d[x*4+1]=g;d[x*4+2]=b;d[x*4+3]=a; } }
  free(sbuf); return m;
}
static VIMG* decode_file(const char* path){
  int w=0,h=0,n=0; unsigned char* p=stbi_load(path,&w,&h,&n,4);
  if(p&&w&&h){ VIMG* m=mk(w,h); memcpy(m->px,p,(size_t)w*h*4); stbi_image_free(p); return m; }
  if(p) stbi_image_free(p);
  return decode_oh(path);
}
int vips_init(const char* a){ (void)a; return 0; }
void vips_shutdown(void){}
const char* vips_error_buffer(void){ return ""; }
void vips_error_clear(void){}
void vips_concurrency_set(int n){ (void)n; }
void* vips_image_new_from_file(const char* fn, ...){ return decode_file(fn); }
void* vips_image_new_from_memory_copy(void* data, size_t size, int w, int h, int bands, ...){ (void)size;(void)bands; VIMG*m=mk(w,h); memcpy(m->px,data,(size_t)w*h*4); return m; }
int vips_image_get_width(void* im){ return im?((VIMG*)im)->w:0; }
int vips_image_get_height(void* im){ return im?((VIMG*)im)->h:0; }
int vips_image_get_bands(void* im){ return im?((VIMG*)im)->b:0; }
/* libvips images are reference counted: each operation takes its own reference,
 * so the caller may unref every handle independently (decodeFileToRgba does exactly
 * that in its finally block). Aliasing without a reference caused a double free;
 * copying unconditionally would spike memory on full-size page decodes. */
static VIMG* ref_img(void* in){ VIMG* s=(VIMG*)in; if(s) s->refs++; return s; }
static void* dup_img(void* in){ if(!in)return 0; VIMG*s=(VIMG*)in; VIMG*m=mk(s->w,s->h); if(!m)return 0; memcpy(m->px,s->px,(size_t)s->w*s->h*4); m->b=s->b; return m; }
/* 3x3 box blur approximating vips_gaussblur (backdrop 用途) */
static void box_blur(VIMG* m){ int w=m->w,h=m->h; unsigned char* src=malloc((size_t)w*h*4); if(!src)return; memcpy(src,m->px,(size_t)w*h*4);
  for(int y=0;y<h;y++){ for(int x=0;x<w;x++){ int r=0,g=0,b=0,a=0,n=0;
    for(int dy=-1;dy<=1;dy++){ int yy=y+dy; if(yy<0||yy>=h)continue; for(int dx=-1;dx<=1;dx++){ int xx=x+dx; if(xx<0||xx>=w)continue;
      unsigned char* p=src+((size_t)yy*w+xx)*4; r+=p[0];g+=p[1];b+=p[2];a+=p[3];n++; } }
    unsigned char* d=m->px+((size_t)y*w+x)*4; d[0]=r/n; d[1]=g/n; d[2]=b/n; d[3]=a/n; } }
  free(src); }
int vips_autorot(void* in, void** out, ...){ if(!in){ if(out)*out=0; return -1; } if(out)*out=ref_img(in); return 0; }
int vips_colourspace(void* in, void** out, int space, ...){ (void)space; if(!in){ if(out)*out=0; return -1; } if(out)*out=ref_img(in); return 0; }
int vips_cast_uchar(void* in, void** out, ...){ if(!in){ if(out)*out=0; return -1; } if(out)*out=ref_img(in); return 0; }
int vips_bandjoin_const1(void* in, void** out, double c, ...){ VIMG*m=(VIMG*)dup_img(in); if(m&&m->b==3){ for(int i=0;i<m->w*m->h;i++) m->px[i*4+3]=(unsigned char)(int)c; m->b=4; } if(out)*out=m; return in?0:-1; }
int vips_bandjoin(void** in, void** out, int n, ...){ (void)n; if(!in||!in[0]){ if(out)*out=0; return -1; } if(out)*out=dup_img(in[0]); return 0; }
int vips_gaussblur(void* in, void** out, double s, ...){ (void)s; if(!in){ if(out)*out=0; return -1; }
  VIMG* src=(VIMG*)in; if(src->refs<=1){ box_blur(src); if(out)*out=ref_img(src); } else { VIMG* m=(VIMG*)dup_img(in); if(m) box_blur(m); if(out)*out=m; } return 0; }
int vips_extract_band(void* in, void** out, int band, ...){ (void)band; if(!in){ if(out)*out=0; return -1; } if(out)*out=ref_img(in); return 0; }
int vips_text(void** out, const char* t, ...){ (void)t; if(out)*out=0; return -1; }
int vips_resize(void* in, void** out, double scale, ...){ if(!in){ if(out)*out=0; return -1; } VIMG*s=in; int w=(int)(s->w*scale+0.5),h=(int)(s->h*scale+0.5); if(w<1)w=1; if(h<1)h=1; VIMG*m=mk(w,h); for(int y=0;y<h;y++){ int sy=y*s->h/h; for(int x=0;x<w;x++){ int sx=x*s->w/w; unsigned char*sp=s->px+((size_t)sy*s->w+sx)*4; unsigned char*dp=m->px+((size_t)y*w+x)*4; dp[0]=sp[0];dp[1]=sp[1];dp[2]=sp[2];dp[3]=sp[3]; } } if(out)*out=m; return 0; }
int vips_extract_area(void* in, void** out, int left,int top,int width,int height, ...){ if(!in){ if(out)*out=0; return -1;} VIMG*s=in; if(left<0)left=0; if(top<0)top=0; if(left+width>s->w)width=s->w-left; if(top+height>s->h)height=s->h-top; if(width<1||height<1){ if(out)*out=0; return -1;} VIMG*m=mk(width,height); for(int y=0;y<height;y++){ const unsigned char*sp=s->px+((size_t)(top+y)*s->w+left)*4; unsigned char*dp=m->px+(size_t)y*width*4; memcpy(dp,sp,(size_t)width*4);} if(out)*out=m; return 0; }
int vips_image_write_to_file(void* im, const char* fn, ...){ (void)im;(void)fn; return -1; }
void* vips_image_write_to_memory(void* im, size_t* size){ if(!im){ if(size)*size=0; return 0;} VIMG*m=im; size_t n=(size_t)m->w*m->h*4; void*p=malloc(n); memcpy(p,m->px,n); if(size)*size=n; return p; }
void g_object_unref(void* o){ if(!o)return; VIMG*m=o; if(--m->refs>0) return; free(m->px); free(m); }
void g_free(void* p){ free(p); }
