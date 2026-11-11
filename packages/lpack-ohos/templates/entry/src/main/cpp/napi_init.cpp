/* __APP__ XComponent module: XComponent -> EGL/GLES (owned by render thread) + Cangjie bootstrap. */
#include <napi/native_api.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <AbilityKit/ability_runtime/application_context.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <hilog/log.h>
#include <dlfcn.h>
#include <cstring>
#include <cstdio>
#include <cstdint>
#include <thread>
#include <atomic>

#undef LOG_TAG
#define LOG_TAG "CJPROBE"
#define LOGI(fmt, ...) do { char _b[256]; snprintf(_b,sizeof(_b),fmt,##__VA_ARGS__); OH_LOG_INFO(LOG_APP, "%{public}s", _b); } while(0)
#define LOGE(fmt, ...) do { char _b[256]; snprintf(_b,sizeof(_b),fmt,##__VA_ARGS__); OH_LOG_ERROR(LOG_APP, "%{public}s", _b); } while(0)

typedef int64_t (*SumFn)(int64_t,int64_t);
typedef int64_t (*CountFn)(void);
typedef int64_t (*MainFn)(void);
typedef void   (*InitRuntimeFn)(void*);
typedef int    (*LoadLibFn)(const char*);
static SumFn g_sum=nullptr; static CountFn g_count=nullptr; static MainFn g_main=nullptr;
typedef int64_t (*SurfFn)(void*,int32_t,int32_t);
typedef int64_t (*SurfChFn)(int32_t,int32_t);
typedef int64_t (*VoidFn)(void);
typedef int64_t (*TouchFn)(int32_t,float,float,int32_t);
typedef int64_t (*DirsFn)(const char*,const char*);
static SurfFn g_onSurf=nullptr; static SurfChFn g_onSurfCh=nullptr; static VoidFn g_onSurfDest=nullptr; static TouchFn g_onTouch=nullptr; static DirsFn g_onDirs=nullptr;
static bool g_booted=false; static int g_code=-1; static char g_err[256]={0};
static bool BootstrapCangjie(){
  if(g_booted) return true;
  void* rt=dlopen("libcangjie-runtime.so",RTLD_NOW|RTLD_GLOBAL); if(!rt){g_code=10; snprintf(g_err,sizeof g_err,"rt:%s",dlerror()); return false;}
  InitRuntimeFn init=(InitRuntimeFn)dlsym(rt,"InitCJRuntime"); LoadLibFn load=(LoadLibFn)dlsym(rt,"LoadCJLibraryWithInit");
  if(!init||!load){g_code=11; return false;}
  static char argbuf[1024]; memset(argbuf,0,sizeof argbuf); init((void*)argbuf); load("lib__ENGINE__.so");
  void* eng=dlopen("lib__ENGINE__.so",RTLD_NOW|RTLD_GLOBAL); if(!eng){g_code=20; snprintf(g_err,sizeof g_err,"eng:%s",dlerror()); return false;}
  g_sum=(SumFn)dlsym(eng,"cj_probe_sum"); g_count=(CountFn)dlsym(eng,"cj_probe_count"); g_main=(MainFn)dlsym(eng,"cj_app_main");
  if(!g_sum||!g_count||!g_main){g_code=30; return false;}
  g_onSurf=(SurfFn)dlsym(eng,"cj_on_surface"); g_onSurfCh=(SurfChFn)dlsym(eng,"cj_on_surface_changed");
  g_onSurfDest=(VoidFn)dlsym(eng,"cj_on_surface_destroyed"); g_onTouch=(TouchFn)dlsym(eng,"cj_on_touch");
  g_onDirs=(DirsFn)dlsym(eng,"cj_on_ability_dirs");
  g_main(); g_booted=true; g_code=0; return true;
}

static OH_NativeXComponent* g_xc=nullptr;
static void* g_window=nullptr; static int g_w=0,g_h=0;
static EGLDisplay g_dpy=EGL_NO_DISPLAY; static EGLSurface g_surf=EGL_NO_SURFACE; static EGLContext g_ctx=EGL_NO_CONTEXT; static EGLConfig g_cfg=nullptr;
static std::atomic<bool> g_running{false};
static std::atomic<bool> g_reinit{false};
static std::thread g_thread;

static bool EglInit(void* window,int w,int h){
  g_dpy=eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if(g_dpy==EGL_NO_DISPLAY){ LOGE("eglGetDisplay failed"); return false; }
  EGLint major=0,minor=0;
  if(!eglInitialize(g_dpy,&major,&minor)){ LOGE("eglInitialize fail 0x%x",eglGetError()); return false; }
  EGLint cfgAttr[]={EGL_SURFACE_TYPE,EGL_WINDOW_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_NONE};
  EGLint n=0;
  if(!eglChooseConfig(g_dpy,cfgAttr,&g_cfg,1,&n)||n<1){ LOGE("eglChooseConfig fail 0x%x",eglGetError()); return false; }
  EGLint ctxAttr[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};
  g_ctx=eglCreateContext(g_dpy,g_cfg,EGL_NO_CONTEXT,ctxAttr); if(g_ctx==EGL_NO_CONTEXT){ LOGE("eglCreateContext fail 0x%x",eglGetError()); return false; }
  g_surf=eglCreateWindowSurface(g_dpy,g_cfg,(EGLNativeWindowType)window,nullptr); if(g_surf==EGL_NO_SURFACE){ LOGE("eglCreateWindowSurface fail 0x%x",eglGetError()); return false; }
  if(!eglMakeCurrent(g_dpy,g_surf,g_surf,g_ctx)){ LOGE("eglMakeCurrent fail 0x%x",eglGetError()); return false; }
  glViewport(0,0,w,h);
  LOGI("EGL ok ver=%d.%d size=%dx%d renderer=%s",major,minor,w,h,(const char*)glGetString(GL_RENDERER));
  return true;
}
static void EglTeardown(){
  if(g_dpy!=EGL_NO_DISPLAY){ eglMakeCurrent(g_dpy,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
    if(g_surf!=EGL_NO_SURFACE) eglDestroySurface(g_dpy,g_surf);
    if(g_ctx!=EGL_NO_CONTEXT) eglDestroyContext(g_dpy,g_ctx); eglTerminate(g_dpy); }
  g_dpy=EGL_NO_DISPLAY; g_surf=EGL_NO_SURFACE; g_ctx=EGL_NO_CONTEXT;
}
static void GLProbe(){
  GLuint fbo=0,rb=0; glGenFramebuffers(1,&fbo); glBindFramebuffer(GL_FRAMEBUFFER,fbo);
  glGenRenderbuffers(1,&rb); glBindRenderbuffer(GL_RENDERBUFFER,rb); glRenderbufferStorage(GL_RENDERBUFFER,GL_RGBA8,4,4);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,rb);
  GLenum st=glCheckFramebufferStatus(GL_FRAMEBUFFER);
  glViewport(0,0,4,4); glClearColor(1.0f,0.4f,0.0f,1.0f); glClear(GL_COLOR_BUFFER_BIT);
  unsigned char px[4]={0,0,0,0}; glReadPixels(0,0,1,1,GL_RGBA,GL_UNSIGNED_BYTE,px);
  LOGI("GLPROBE fbo status=0x%x px=#%02X%02X%02X%02X expectFF6600FF",st,px[0],px[1],px[2],px[3]);
  glBindFramebuffer(GL_FRAMEBUFFER,0); glDeleteFramebuffers(1,&fbo); glDeleteRenderbuffers(1,&rb); glViewport(0,0,g_w,g_h);
}
static void RenderThreadMain(){
  LOGI("RenderThread start window=%p size=%dx%d",g_window,g_w,g_h);
  if(!EglInit(g_window,g_w,g_h)) LOGE("EglInit failed on render thread");
  else GLProbe();
  int frame=0;
  while(g_running.load()){
    if(g_reinit.exchange(false)){ EglTeardown(); if(g_window) { if(EglInit(g_window,g_w,g_h)) GLProbe(); } }
    if(g_surf!=EGL_NO_SURFACE){
      float r=(frame%120)/120.0f;
      glClearColor(r,0.4f,1.0f-r,1.0f); glClear(GL_COLOR_BUFFER_BIT);
      if(eglSwapBuffers(g_dpy,g_surf)!=EGL_TRUE){ if(frame%60==0) LOGE("eglSwapBuffers fail 0x%x",eglGetError()); }
      frame++;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(16));
  }
  EglTeardown();
  LOGI("RenderThread exit");
}
static void OnSurfaceCreated(OH_NativeXComponent* comp, void* window){
  g_xc=comp; g_window=window; uint64_t w=0,h=0; OH_NativeXComponent_GetXComponentSize(comp,window,&w,&h); g_w=(int)w; g_h=(int)h;
  LOGI("OnSurfaceCreated window=%p size=%dx%d",window,g_w,g_h);
  if(g_onSurf){ int64_t r=g_onSurf(window,g_w,g_h); LOGI("cj_on_surface -> %lld expect=%lld",(long long)r,(long long)((int64_t)g_w*100000+g_h)); }
  if(g_running.load()){ g_reinit.store(true); return; }
  g_running.store(true); g_thread=std::thread(RenderThreadMain);
}
static void OnSurfaceChanged(OH_NativeXComponent* comp, void* window){
  uint64_t w=0,h=0; OH_NativeXComponent_GetXComponentSize(comp,window,&w,&h); g_w=(int)w; g_h=(int)h; g_window=window;
  LOGI("OnSurfaceChanged size=%dx%d",g_w,g_h);
  if(g_onSurfCh){ int64_t r=g_onSurfCh(g_w,g_h); LOGI("cj_on_surface_changed -> %lld",(long long)r); }
  g_reinit.store(true);
}
static void OnSurfaceDestroyed(OH_NativeXComponent* comp, void* window){
  LOGI("OnSurfaceDestroyed"); if(g_onSurfDest) g_onSurfDest();
  g_running.store(false); if(g_thread.joinable()) g_thread.join();
}
static void DispatchTouch(OH_NativeXComponent* comp, void* window){
  OH_NativeXComponent_TouchEvent ev;
  int32_t rc = OH_NativeXComponent_GetTouchEvent(comp, window, &ev);
  if(rc==0 && g_onTouch){ int64_t n=g_onTouch((int32_t)ev.type, ev.x, ev.y, ev.id);
    LOGI("cj_on_touch type=%d x=%.1f y=%.1f -> count=%lld",(int)ev.type,ev.x,ev.y,(long long)n); }
}
static OH_NativeXComponent_Callback g_cb = { OnSurfaceCreated, OnSurfaceChanged, OnSurfaceDestroyed, DispatchTouch };

static napi_value Boot(napi_env env,napi_callback_info){ bool ok=BootstrapCangjie(); napi_value o; napi_get_boolean(env,ok,&o); return o; }
static napi_value Sum(napi_env env,napi_callback_info info){ size_t c=2; napi_value a[2]; napi_get_cb_info(env,info,&c,a,nullptr,nullptr); int64_t x=0,y=0; napi_get_value_int64(env,a[0],&x); napi_get_value_int64(env,a[1],&y); if(!BootstrapCangjie()){napi_throw_error(env,nullptr,"boot fail");return nullptr;} napi_value o; napi_create_int64(env,g_sum(x,y),&o); return o; }
static napi_value Count(napi_env env,napi_callback_info){ if(!BootstrapCangjie()){napi_throw_error(env,nullptr,"boot fail");return nullptr;} napi_value o; napi_create_int64(env,g_count(),&o); return o; }
static napi_value LastErr(napi_env env,napi_callback_info){ napi_value o; napi_create_string_utf8(env,g_err,NAPI_AUTO_LENGTH,&o); return o; }

static napi_value Init(napi_env env, napi_value exports){
  BootstrapCangjie();
  if(g_onDirs){ char files[512]={0}, cache[512]={0}; int32_t wl=0;
    OH_AbilityRuntime_ApplicationContextGetFilesDir(files,(int32_t)sizeof(files),&wl);
    OH_AbilityRuntime_ApplicationContextGetCacheDir(cache,(int32_t)sizeof(cache),&wl);
    int64_t r=g_onDirs(files,cache); LOGI("cj_on_ability_dirs files='%s' cache='%s' -> %lld",files,cache,(long long)r); }
  napi_value xcObj=nullptr; napi_get_named_property(env,exports,OH_NATIVE_XCOMPONENT_OBJ,&xcObj);
  if(xcObj){ OH_NativeXComponent* comp=nullptr; napi_unwrap(env,xcObj,(void**)&comp); if(comp){ OH_NativeXComponent_RegisterCallback(comp,&g_cb); LOGI("RegisterCallback ok"); } else LOGE("unwrap xcomponent null"); }
  else LOGE("no __NapiXComponent__ in exports");
  napi_property_descriptor d[]={ {"boot",NULL,Boot,NULL,NULL,NULL,napi_default,NULL},{"lastError",NULL,LastErr,NULL,NULL,NULL,napi_default,NULL},{"sum",NULL,Sum,NULL,NULL,NULL,napi_default,NULL},{"count",NULL,Count,NULL,NULL,NULL,napi_default,NULL} };
  napi_define_properties(env,exports,sizeof(d)/sizeof(d[0]),d);
  return exports;
}
static napi_module g_module={1,0,NULL,Init,"__SHIM__",NULL,{0}};
extern "C" __attribute__((constructor)) void Register__APP__Module(void){ napi_module_register(&g_module); }
