/* 最小"壳"：导出引擎要调的 C 函数。
 * 复现 docs/l-layer.md 记录的历史崩溃场景（引擎调壳导出符号）。 */
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>
#include <stdint.h>
#include <dlfcn.h>

__attribute__((visibility("default"))) int lwp_probe(int x) {
    return x * 7 + 1;
}

/* 供"外部线程调仓颉"用例：自己 dlsym 引擎导出的 @C 符号（引擎以 RTLD_GLOBAL 加载） */
typedef int64_t (*engine_foreign_fn)(int32_t);
static engine_foreign_fn g_foreign = NULL;

static void* thread_main(void* arg) {
    (void)arg;
    if (g_foreign) {
        int64_t v = g_foreign(21);
        fprintf(stdout, "[shell] foreign thread call -> %lld\n", (long long)v);
    }
    return NULL;
}

__attribute__((visibility("default"))) int lwp_spawn_foreign(void) {
    if (!g_foreign) {
        g_foreign = (engine_foreign_fn)dlsym(RTLD_DEFAULT, "cj_foreign_entry");
        fprintf(stdout, "[shell] dlsym cj_foreign_entry = %p\n", (void*)g_foreign);
    }
    pthread_t th;
    if (pthread_create(&th, NULL, thread_main, NULL) != 0) return -1;
    pthread_join(th, NULL);
    return 0;
}
