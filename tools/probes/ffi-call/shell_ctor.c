/* 变体：壳在 dlopen 时刻的构造函数里自启动引擎（= 现在 shell_napi.cpp::lanlu_autostart_engine 的做法）。
 * 故意复现"构造函数里 InitCJRuntime + LoadCJLibraryWithInit + cj_app_main"的时序。 */
#include <stdio.h>
#include <dlfcn.h>
#include <string.h>

__attribute__((visibility("default"))) int lwp_probe(int x) { return x * 7 + 1; }

/* 引擎需要的第二个符号（本变体不做外部线程测试，给个桩） */
__attribute__((visibility("default"))) int lwp_spawn_foreign(void) {
    fprintf(stdout, "[ctor] spawn_foreign stub\n");
    return 0;
}


__attribute__((constructor)) static void ctor_autostart(void) {
    fprintf(stdout, "[ctor] enter (dlopen 时刻)\n");
    void* rt = dlopen("libcangjie-runtime.so", RTLD_NOW | RTLD_GLOBAL);
    if (!rt) { fprintf(stdout, "[ctor] runtime fail: %s\n", dlerror()); return; }
    typedef int (*init_fn)(void*);
    typedef int (*load_fn)(const char*);
    init_fn init = (init_fn)dlsym(rt, "InitCJRuntime");
    load_fn load = (load_fn)dlsym(rt, "LoadCJLibraryWithInit");
    if (!init || !load) { fprintf(stdout, "[ctor] dlsym fail\n"); return; }
    static char argbuf[4096];
    memset(argbuf, 0, sizeof argbuf);
    fprintf(stdout, "[ctor] InitCJRuntime rc=%d\n", init((void*)argbuf));
    fprintf(stdout, "[ctor] LoadCJLibraryWithInit rc=%d\n", load("./libengine.so"));
    void* eng = dlopen("./libengine.so", RTLD_LAZY | RTLD_GLOBAL);
    if (!eng) { fprintf(stdout, "[ctor] engine dlopen fail: %s\n", dlerror()); return; }
    long (*m)(void) = (long (*)(void))dlsym(eng, "cj_app_main");
    fprintf(stdout, "[ctor] cj_app_main=%p\n", (void*)m);
    if (m) fprintf(stdout, "[ctor] cj_app_main returned %ld\n", m());
    fprintf(stdout, "[ctor] done\n");
}
