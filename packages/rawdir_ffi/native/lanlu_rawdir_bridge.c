#include "lanlu_rawdir_bridge.h"

#include <dirent.h>
#include <errno.h>
#include <iconv.h>
#include <stdio.h> /* rename(2) is declared in stdio.h */
#include <stdlib.h>
#include <string.h>

#define RAWDIR_BUFFER_FULL ((int64_t)-10001)
#define RAWDIR_CHARSET_UNAVAILABLE ((int64_t)-10002)

int64_t lrawdir_list(const char *dirpath, uint8_t *namebuf, int64_t namecap,
                     uint8_t *typebuf, int64_t *offbuf, int64_t maxn) {
    if (dirpath == NULL || namebuf == NULL || namecap <= 0 || typebuf == NULL ||
        offbuf == NULL || maxn <= 0) {
        return -(int64_t)EINVAL;
    }

    DIR *d = opendir(dirpath);
    if (d == NULL) {
        return -(int64_t)errno;
    }

    int64_t n = 0;
    int64_t used = 0;
    int overflow = 0;
    int readErr = 0;
    struct dirent *ent;

    for (;;) {
        errno = 0;
        ent = readdir(d);
        if (ent == NULL) {
            readErr = errno; /* 0 on normal EOF */
            break;
        }

        const char *nm = ent->d_name;
        if (nm[0] == '.' && (nm[1] == '\0' || (nm[1] == '.' && nm[2] == '\0'))) {
            continue; /* "." and ".." */
        }

        unsigned char t = ent->d_type;
        if (!(t == DT_REG || t == DT_DIR || t == DT_LNK || t == DT_UNKNOWN)) {
            continue; /* sockets, fifos, devices: never scan targets */
        }

        size_t len = strlen(nm); /* POSIX entry names cannot contain NUL */
        if (n >= maxn || used + (int64_t)len + 1 > namecap) {
            overflow = 1;
            break;
        }

        memcpy(namebuf + used, nm, len + 1);
        offbuf[n] = used;
        typebuf[n] = (uint8_t)t;
        n += 1;
        used += (int64_t)len + 1;
    }

    closedir(d);

    if (overflow) {
        return RAWDIR_BUFFER_FULL;
    }
    if (readErr != 0) {
        return -(int64_t)readErr;
    }
    return n;
}

int64_t lrawdir_rename_utf8(const char *dirpath, const uint8_t *rawname,
                            int64_t rawlen, const char *newname) {
    if (dirpath == NULL || rawname == NULL || rawlen <= 0 || newname == NULL) {
        return -(int64_t)EINVAL;
    }

    size_t dlen = strlen(dirpath);
    int sep = (dlen > 0 && dirpath[dlen - 1] != '/') ? 1 : 0;
    size_t newlen = strlen(newname);

    size_t fromLen = dlen + (size_t)sep + (size_t)rawlen;
    size_t toLen = dlen + (size_t)sep + newlen;
    char *from = (char *)malloc(fromLen + 1);
    char *to = (char *)malloc(toLen + 1);
    if (from == NULL || to == NULL) {
        free(from);
        free(to);
        return -(int64_t)ENOMEM;
    }

    memcpy(from, dirpath, dlen);
    if (sep) {
        from[dlen] = '/';
    }
    memcpy(from + dlen + sep, rawname, (size_t)rawlen);
    from[fromLen] = '\0';

    memcpy(to, dirpath, dlen);
    if (sep) {
        to[dlen] = '/';
    }
    memcpy(to + dlen + sep, newname, newlen);
    to[toLen] = '\0';

    int rc = rename(from, to);
    int saved = errno;
    free(from);
    free(to);
    return rc == 0 ? 0 : -(int64_t)saved;
}

int64_t lrawdir_convert(const char *fromcode, const uint8_t *in, int64_t inlen,
                        uint8_t *out, int64_t outcap) {
    if (fromcode == NULL || in == NULL || inlen < 0 || out == NULL || outcap <= 0) {
        return -(int64_t)EINVAL;
    }

    iconv_t cd = iconv_open("UTF-8", fromcode);
    if (cd == (iconv_t)-1) {
        return RAWDIR_CHARSET_UNAVAILABLE;
    }

    char *inp = (char *)(uintptr_t)in; /* iconv API is not const-correct */
    size_t inleft = (size_t)inlen;
    char *outp = (char *)out;
    size_t outleft = (size_t)outcap;
    size_t rc = iconv(cd, &inp, &inleft, &outp, &outleft);
    int err = (rc == (size_t)-1) ? errno : 0;
    iconv_close(cd);

    if (err != 0) {
        return -(int64_t)err;
    }
    if (inleft != 0) {
        return -(int64_t)EILSEQ; /* incomplete trailing sequence */
    }
    return (int64_t)((size_t)outcap - outleft);
}
