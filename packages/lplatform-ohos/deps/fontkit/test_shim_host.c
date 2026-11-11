// Host regression test for the OHOS fontkit shim: scan a directory, check counts,
// labels/paths, non-font filtering, and clean destruction (run under ASAN).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void* lanlu_font_list_create(void);
unsigned long lanlu_font_list_count(void* p);
const char* lanlu_font_list_label(void* p, unsigned long i);
const char* lanlu_font_list_path(void* p, unsigned long i);
void lanlu_font_list_destroy(void* p);

static int fails = 0;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); fails++; } } while (0)

int main(int argc, char** argv) {
    const char* dir = argv[1];
    setenv("LANLU_FONT_DIR", dir, 1);
    void* l = lanlu_font_list_create();
    CHECK(l != 0, "list created");
    CHECK(lanlu_font_list_count(l) == 3, "count == 3 (ttf/otf/ttc only)");
    CHECK(strcmp(lanlu_font_list_label(l, 0), "a") == 0, "label[0]");
    CHECK(strcmp(lanlu_font_list_label(l, 1), "b") == 0, "label[1]");
    const char* p = lanlu_font_list_path(l, 0);
    CHECK(p && strncmp(p, dir, strlen(dir)) == 0, "path prefix");
    CHECK(strstr(p, "a.ttf") != 0, "path filename");
    lanlu_font_list_destroy(l);

    setenv("LANLU_FONT_DIR", "/nonexistent-dir-xyz", 1);
    CHECK(lanlu_font_list_create() == 0, "missing dir -> null");
    if (fails == 0) printf("ok: fontkit shim (all checks)\n");
    return fails ? 1 : 0;
}
