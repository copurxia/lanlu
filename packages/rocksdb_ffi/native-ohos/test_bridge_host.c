// Host regression test for the OHOS rocksdb bridge (rocksdb_bridge_ohos.c).
// Covers: default-CF put/get, column-family isolation, prefix iteration order,
// write batch, delete, and file persistence round-trip.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void* rocksdb_open_column_families(void* o, const char* n, int num, void* names, void* cfopts, void* handles, void* err);
void* rocksdb_create_column_family(void* db, void* o, const char* n, void* err);
void* rocksdb_writebatch_create(void);
void rocksdb_writebatch_put_cf(void* p, void* cf, const char* k, unsigned kl, const char* v, unsigned vl);
void rocksdb_write(void* db, void* o, void* p, void* err);
void rocksdb_put_cf(void* db, void* o, void* cf, const char* k, unsigned kl, const char* v, unsigned vl, void* err);
unsigned char* rocksdb_get_cf(void* db, void* o, void* cf, const char* k, unsigned kl, unsigned* vallen, void* err);
void rocksdb_put(void* db, void* o, const char* k, unsigned kl, const char* v, unsigned vl, void* err);
unsigned char* rocksdb_get(void* db, void* o, const char* k, unsigned kl, unsigned* vallen, void* err);
void* rocksdb_create_iterator_cf(void* db, void* o, void* cf);
void* rocksdb_create_iterator(void* db, void* o);
void rocksdb_iter_seek_to_first(void* it);
void rocksdb_iter_seek(void* it, const char* k, unsigned kl);
unsigned char rocksdb_iter_valid(void* it);
unsigned char* rocksdb_iter_key(void* it, unsigned* l);
unsigned char* rocksdb_iter_value(void* it, unsigned* l);
void rocksdb_iter_next(void* it);
void rocksdb_iter_destroy(void* it);
void rocksdb_delete_cf(void* db, void* o, void* cf, const char* k, unsigned kl, void* err);
void rocksdb_flush(void* db, void* o, void* err);

static int fails = 0;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); fails++; } } while (0)

static int get_eq(void* db, const char* key, const char* want, int cf, void* cfh) {
    unsigned n = 0;
    unsigned char* v = cf ? rocksdb_get_cf(db, 0, cfh, key, (unsigned)strlen(key), &n, 0)
                         : rocksdb_get(db, 0, key, (unsigned)strlen(key), &n, 0);
    if (!v) return want == 0;
    int ok = want && n == strlen(want) && memcmp(v, want, n) == 0;
    free(v);
    return ok;
}

int main(int argc, char** argv) {
    const char* dir = argv[1];
    char path[1024];
    snprintf(path, sizeof path, "%s/db", dir);

    const char* cfs[2] = {"meta", "objects"};
    void* handles[2] = {0, 0};
    void* db = rocksdb_open_column_families(0, path, 2, (void*)cfs, 0, handles, 0);
    CHECK(db, "open db");
    void* meta = handles[0];
    void* objects = handles[1];
    CHECK(meta && objects && meta != objects, "distinct cf handles");

    rocksdb_put(db, 0, "plain", 5, "v0", 2, 0);
    rocksdb_put_cf(db, 0, meta, "schema", 6, "v3", 2, 0);
    CHECK(get_eq(db, "plain", "v0", 0, 0), "default cf put/get");
    CHECK(get_eq(db, "schema", "v3", 1, meta), "meta cf put/get");
    // 同一 key 在两个 cf 中必须互相隔离
    rocksdb_put_cf(db, 0, objects, "schema", 6, "other", 5, 0);
    CHECK(get_eq(db, "schema", "v3", 1, meta), "cf isolation (meta)");
    CHECK(get_eq(db, "schema", "other", 1, objects), "cf isolation (objects)");

    // 批处理
    void* b = rocksdb_writebatch_create();
    rocksdb_writebatch_put_cf(b, objects, "k1", 2, "a", 1);
    rocksdb_writebatch_put_cf(b, objects, "k2", 2, "b", 1);
    rocksdb_write(b, 0, b, 0);
    CHECK(get_eq(db, "k1", "a", 1, objects), "batch k1");
    CHECK(get_eq(db, "k2", "b", 1, objects), "batch k2");

    // 前缀迭代顺序：objects cf 里 k1<k2<schema
    void* it = rocksdb_create_iterator_cf(db, 0, objects);
    rocksdb_iter_seek_to_first(it);
    CHECK(rocksdb_iter_valid(it), "iter valid");
    unsigned kl = 0;
    unsigned char* k = rocksdb_iter_key(it, &kl);
    CHECK(k && kl == 2 && memcmp(k, "k1", 2) == 0, "iter first key");
    rocksdb_iter_next(it);
    k = rocksdb_iter_key(it, &kl);
    CHECK(k && kl == 2 && memcmp(k, "k2", 2) == 0, "iter second key");
    rocksdb_iter_destroy(it);

    // seek
    it = rocksdb_create_iterator_cf(db, 0, objects);
    rocksdb_iter_seek(it, "k2", 2);
    k = rocksdb_iter_key(it, &kl);
    CHECK(k && kl == 2 && memcmp(k, "k2", 2) == 0, "iter seek");
    rocksdb_iter_destroy(it);

    // 删除
    rocksdb_delete_cf(db, 0, objects, "k1", 2, 0);
    CHECK(get_eq(db, "k1", 0, 1, objects), "delete");
    rocksdb_flush(db, 0, 0);

    // 落盘后重新打开（open 会 load 同一文件）
    const char* cfs2[2] = {"meta", "objects"};
    void* h2[2] = {0, 0};
    void* db2 = rocksdb_open_column_families(0, path, 2, (void*)cfs2, 0, h2, 0);
    CHECK(get_eq(db2, "plain", "v0", 0, 0), "persist default cf");
    CHECK(get_eq(db2, "schema", "v3", 1, h2[0]), "persist meta cf");
    CHECK(get_eq(db2, "k2", "b", 1, h2[1]), "persist objects cf");
    CHECK(get_eq(db2, "k1", 0, 1, h2[1]), "persist delete");

    if (fails == 0) printf("ok: rocksdb bridge (all checks)\n");
    return fails ? 1 : 0;
}
