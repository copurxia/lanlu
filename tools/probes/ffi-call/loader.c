/* 最小"宿主"：InitCJRuntime → LoadCJLibraryWithInit(engine) → 可选提前 dlopen 壳 → cj_app_main。
 * 用法：./loader <engine.so> <shell.so> <mode>
 *   mode=shell-first-g   先 dlopen 壳（RTLD_GLOBAL），再加载引擎
 *   mode=engine-first    先加载引擎（RTLD_LAZY），再 dlopen 壳（RTLD_GLOBAL）
 *   mode=shell-local     先 dlopen 壳（RTLD_LOCAL），再加载引擎（RTLD_LAZY）
 */
#include <stdio.h>
#include <dlfcn.h>
#include <string.h>
#include <time.h>

typedef int  (*init_fn)(void*);
typedef int  (*load_fn)(const char*);
typedef long (*main_fn)(void);

static void* open_shell(const char* path, int mode, const char* tag) {
    void* h = dlopen(path, RTLD_NOW | mode);
    printf("[loader] dlopen shell (%s) = %s\n", tag, h ? "ok" : dlerror());
    return h;
}

int main(int argc, char** argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s engine.so shell.so mode\n", argv[0]); return 2; }
    const char* engine = argv[1];
    const char* shell  = argv[2];
    const char* mode   = argv[3];

    if (strcmp(mode, "ctor") == 0) {
        /* 壳的构造函数会自己起运行时与引擎；这里只负责 dlopen 壳。 */
        void* h = dlopen(shell, RTLD_NOW | RTLD_GLOBAL);
        printf("[loader] dlopen shell (ctor mode) = %s\n", h ? "ok" : dlerror());
        /* 等壳里 spawn 的引擎线程跑完（模拟"构造函数返回后引擎才启动"） */
        struct timespec ts = {2, 0};
        nanosleep(&ts, NULL);
        return h ? 0 : 1;
    }

    void* rt = dlopen("libcangjie-runtime.so", RTLD_NOW | RTLD_GLOBAL);
    if (!rt) { printf("[loader] runtime fail: %s\n", dlerror()); return 1; }
    init_fn init = (init_fn)dlsym(rt, "InitCJRuntime");
    load_fn load = (load_fn)dlsym(rt, "LoadCJLibraryWithInit");
    if (!init || !load) { printf("[loader] dlsym runtime fail\n"); return 1; }
    static char argbuf[4096];
    memset(argbuf, 0, sizeof argbuf);
    int rc = init((void*)argbuf);
    printf("[loader] InitCJRuntime rc=%d\n", rc);

    void* sh = NULL;
    if (strcmp(mode, "shell-first-g") == 0) {
        sh = open_shell(shell, RTLD_GLOBAL, "RTLD_GLOBAL");
    } else if (strcmp(mode, "shell-local") == 0) {
        sh = open_shell(shell, RTLD_LOCAL, "RTLD_LOCAL");
    }

    int lrc = load(engine);
    printf("[loader] LoadCJLibraryWithInit rc=%d\n", lrc);

    if (strcmp(mode, "engine-first") == 0) {
        sh = open_shell(shell, RTLD_GLOBAL, "RTLD_GLOBAL after engine");
    }

    void* eng = dlopen(engine, RTLD_LAZY | RTLD_GLOBAL);
    printf("[loader] dlopen engine = %s\n", eng ? "ok" : dlerror());
    if (!eng) return 1;
    main_fn m = (main_fn)dlsym(eng, "cj_app_main");
    printf("[loader] cj_app_main=%p\n", (void*)m);
    if (!m) return 1;
    long v = m();
    printf("[loader] cj_app_main returned %ld\n", v);
    return 0;
}
