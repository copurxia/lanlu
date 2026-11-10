#ifndef LANLU_RAWDIR_BRIDGE_H
#define LANLU_RAWDIR_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Raw-byte directory bridge.
 *
 * Why: Cangjie std.fs (Directory.readFrom / Dirent) requires entry names to be
 * valid UTF-8; one non-UTF-8 entry poisons the whole listing. These helpers
 * enumerate entries by raw bytes (POSIX readdir), rename entries by raw bytes,
 * and convert legacy encodings via iconv, so a single bad name only affects
 * itself.
 */

/*
 * Flat-buffer directory listing (skips "." / ".." and non file/dir/symlink
 * types). Names are copied NUL-terminated into namebuf back to back;
 * offbuf[i] is the start offset of name i, typebuf[i] its d_type.
 *
 * Returns entry count (>= 0), -10001 if a buffer is too small (retry bigger),
 * or -errno on failure.
 */
int64_t lrawdir_list(const char *dirpath, uint8_t *namebuf, int64_t namecap,
                     uint8_t *typebuf, int64_t *offbuf, int64_t maxn);

/*
 * rename(dirpath + "/" + rawname, dirpath + "/" + newname).
 * rawname is raw on-disk bytes (may be non-UTF-8); newname must be valid
 * UTF-8. Returns 0 on success, -errno on failure.
 */
int64_t lrawdir_rename_utf8(const char *dirpath, const uint8_t *rawname,
                            int64_t rawlen, const char *newname);

/*
 * iconv wrapper: decode in[0..inlen) from `fromcode` to UTF-8 into out.
 * Returns written byte count (>= 0), -10002 if the charset is unavailable,
 * -errno on conversion failure (EILSEQ invalid sequence, E2BIG, EINVAL).
 * A non-empty incomplete tail is treated as invalid (EILSEQ).
 */
int64_t lrawdir_convert(const char *fromcode, const uint8_t *in, int64_t inlen,
                        uint8_t *out, int64_t outcap);

#ifdef __cplusplus
}
#endif

#endif /* LANLU_RAWDIR_BRIDGE_H */
