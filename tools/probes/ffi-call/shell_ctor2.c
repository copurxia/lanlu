/* 变体：构造函数只起线程，延迟再 InitCJRuntime + 加载引擎
 * （= 现在 shell_napi.cpp::lanlu_autostart_engine 的真实形态：构造里 pthread_create，
 *   线程里初始化；但线程何时跑完是不确定的）。 */
#include <stdio.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>

__attribute__((visibility("default"))) int lwp_probe(int x) { return x * 7 + 1; }

/* 引擎需要的第二个符号（本变体不做外部线程测试，给个桩） */
__attribute__((visibility("default"))) int lwp_spawn_foreign(void) {
    fprintf(stdout, "[ctor] spawn_foreign stub\n");
    return 0;
}


static void* engine_thread(void* arg) {
    (void)arg;
    usleep(200 * 1000);           /* 模拟"构造函数返回之后"才真正开始 */
    fprintf(stdout, "[ctor2] thread: enter\n");
    fprintf(stdout, "[ctor2] dlsym(RTLD_DEFAULT, lwp_probe) = %p\n", dlsym(RTLD_DEFAULT, "lwp_probe"));
    void* rt = dlopen("libcangjie-runtime.so", RTLD_NOW | RTLD_GLOBAL);
    if (!rt) { fprintf(stdout, "[ctor2] runtime fail: %s\n", dlerror()); return NULL; }
    typedef int (*init_fn)(void*);
    typedef int (*load_fn)(const char*);
    init_fn init = (init_fn)dlsym(rt, "InitCJRuntime");
    load_fn load = (load_fn)dlsym(rt, "LoadCJLibraryWithInit");
    static char argbuf[4096];
    memset(argbuf, 0, sizeof argbuf);
    fprintf(stdout, "[ctor2] InitCJRuntime rc=%d\n", init((void*)argbuf));
    fprintf(stdout, "[ctor2] LoadCJLibraryWithInit rc=%d\n", load("./libengine.so"));
    void* eng = dlopen("./libengine.so", RTLD_LAZY | RTLD_GLOBAL);
    if (!eng) { fprintf(stdout, "[ctor2] engine fail: %s\n", dlerror()); return NULL; }
    long (*m)(void) = (long (*)(void))dlsym(eng, "cj_app_main");
    if (m) fprintf(stdout, "[ctor2] cj_app_main returned %ld\n", m());
    return NULL;
}

__attribute__((constructor)) static void ctor_spawn(void) {
    fprintf(stdout, "[ctor2] construct -> spawn thread\n");
    pthread_t th;
    pthread_create(&th, NULL, engine_thread, NULL);
    pthread_detach(th);
}
