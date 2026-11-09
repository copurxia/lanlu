// lanlu ohos: libvlc-compatible shim backed by ffmpeg (avformat/avcodec/swscale).
// Implements the subset of the libvlc C API that libvlc_ffi uses: media open,
// player play/pause/stop/seek/time/length, video callbacks protocol
// (format setup + lock/unlock/display) delivering RGBA (RV32) frames, and
// subtitle-track stubs. Audio is accepted but silent (no OHOS audio yet).
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
static FILE* vlc_log(void){ static FILE* f=0; if(!f){ const char* p=getenv("LANLU_VLC_LOG"); if(p) f=fopen(p,"a"); } return f; }
// 播放统计（LANLU_VLC_STATS=1 时每 ~3s 打印一次音频采样数与视频帧数）：
// 真机验证“确实在持续播放”需要这类计数，正常使用保持静默。
static int stats_enabled(void) {
    static int cached = -1;
    if (cached < 0) { const char* v = getenv("LANLU_VLC_STATS"); cached = (v && v[0] == '1') ? 1 : 0; }
    return cached;
}

#define VLOG(...) do{ FILE*_f=vlc_log(); if(_f){ fprintf(_f,__VA_ARGS__); fprintf(_f,"\n"); fflush(_f);} }while(0)

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
#include <ohaudio/native_audiostreambuilder.h>
#include <ohaudio/native_audio_session_manager.h>
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostream_base.h>

typedef void* InstancePtr;
typedef void* MediaPtr;
typedef void* PlayerPtr;

typedef void* (*LockCb)(void*, void**);
typedef void  (*UnlockCb)(void*, void*, void**);
typedef void  (*DisplayCb)(void*, void*);
typedef unsigned (*SetupCb)(void**, char*, unsigned*, unsigned*, unsigned*, unsigned*);
typedef void  (*CleanupCb)(void*);

typedef struct {
    char path[1024];
} VlcMedia;

typedef struct {
    char path[1024];
    AVFormatContext* fmt;
    AVCodecContext* codec;
    int stream;
    struct SwsContext* sws;
    AVPacket* pkt;
    AVFrame* frm;

    LockCb lock; UnlockCb unlock; DisplayCb display; void* opaque;
    SetupCb setup; CleanupCb cleanup;

    atomic_int running;      // playing
    atomic_int paused;
    atomic_int stop_req;
    atomic_int seek_ms;      // -1 = none
    atomic_int audio_seek_ms; // audio thread has its own AVFormatContext; -1 = none
    atomic_long position_ms;
    atomic_long duration_ms;
    long last_tick_ms;       // pacing clock
    double next_pts_ms;      // next frame pts to render

    int out_w, out_h;
    int format_done;         // setup callback invoked

    // audio：与视频共用同一个 AVFormatContext（单连接单 demuxer），
    // 音频包在 pump() 里解码后写入 ring，由 OH_AudioRenderer 回调消费。
    int astream;                 // 音频流索引，-1 = 无
    AVCodecContext* acodec;
    struct SwrContext* aswr;   // 已不再使用（保留字段以免破坏 ABI 布局）
    double apos;               // 自研重采样相位
    int aprimed;
    AVFrame* fctx_tmp;           // 音频解码输出帧（复用，避免每次 malloc）
    int aswr_ok;
    OH_AudioRenderer* renderer;
    pthread_t athread;
    int athread_started;
    atomic_int muted;
    volatile int astop;
    pthread_mutex_t amu;
    pthread_cond_t  acv;
    unsigned char* ring; size_t rcap, rhead, rtail, rsize;
} VlcPlayer;

static void audio_stop(VlcPlayer* p);
static long now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

InstancePtr libvlc_new(int argc, void* argv) { (void)argc; (void)argv; avformat_network_init(); return (InstancePtr)(uintptr_t)0x11; }
void libvlc_release(InstancePtr i) { (void)i; }

MediaPtr libvlc_media_new_path(InstancePtr i, const char* path) {
    (void)i;
    VlcMedia* m = calloc(1, sizeof(VlcMedia));
    if (!m) return 0;
    snprintf(m->path, sizeof m->path, "%s", path ? path : "");
    return m;
}
MediaPtr libvlc_media_new_location(InstancePtr i, const char* loc) { return libvlc_media_new_path(i, loc); }
void libvlc_media_add_option(MediaPtr m, const char* o) { (void)m; (void)o; }
void libvlc_media_release(MediaPtr m) { free(m); }

static void* decode_loop(void* arg);

PlayerPtr libvlc_media_player_new_from_media(MediaPtr mp) {
    VlcMedia* m = (VlcMedia*)mp;
    if (!m) return 0;
    VlcPlayer* p = calloc(1, sizeof(VlcPlayer));
    if (!p) return 0;
    p->stream = -1;
    atomic_store(&p->seek_ms, -1);
    atomic_store(&p->audio_seek_ms, -1);
    atomic_store(&p->duration_ms, 0);
    snprintf(p->path, sizeof p->path, "%s", m->path);
    p->pkt = av_packet_alloc();
    p->frm = av_frame_alloc();
    p->fctx_tmp = av_frame_alloc();
    p->astream = -1;
    // 音频环形缓冲的锁/条件变量在整个播放器生命周期内只初始化一次：
    // audio_start 可能被多次调用（重开/重播），在那里重复 init 而回调正在使用 → UB（真机 SIGSEGV）。
    pthread_mutex_init(&p->amu, NULL);
    pthread_cond_init(&p->acv, NULL);
    return p;
}
void libvlc_media_player_release(PlayerPtr pp) {
    VlcPlayer* p = (VlcPlayer*)pp;
    if (!p) return;
    atomic_store(&p->stop_req, 1);
    audio_stop(p);
    if (p->sws) sws_freeContext(p->sws);
    if (p->codec) avcodec_free_context(&p->codec);
    if (p->fmt) avformat_close_input(&p->fmt);
    if (p->pkt) av_packet_free(&p->pkt);
    if (p->frm) av_frame_free(&p->frm);
    free(p);
}


static int open_pipeline(VlcPlayer* p) {
    if (avformat_open_input(&p->fmt, p->path, NULL, NULL) != 0) return -1;
    if (avformat_find_stream_info(p->fmt, NULL) < 0) return -1;
    int idx = av_find_best_stream(p->fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (idx < 0) return -1;
    p->stream = idx;
    AVStream* st = p->fmt->streams[idx];
    const AVCodec* dec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!dec) return -1;
    p->codec = avcodec_alloc_context3(dec);
    if (!p->codec) return -1;
    if (avcodec_parameters_to_context(p->codec, st->codecpar) < 0) return -1;
    if (avcodec_open2(p->codec, dec, NULL) < 0) return -1;
    if (p->fmt->duration > 0) atomic_store(&p->duration_ms, p->fmt->duration / (AV_TIME_BASE / 1000));
    // 音频：同一 demuxer 内找音频流并打开解码器（不再单开第二条 HTTP 连接）
    p->astream = av_find_best_stream(p->fmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (p->astream >= 0) {
        const AVCodec* adec = avcodec_find_decoder(p->fmt->streams[p->astream]->codecpar->codec_id);
        if (adec) {
            p->acodec = avcodec_alloc_context3(adec);
            if (p->acodec && avcodec_parameters_to_context(p->acodec, p->fmt->streams[p->astream]->codecpar) >= 0) {
                if (avcodec_open2(p->acodec, adec, NULL) != 0) { avcodec_free_context(&p->acodec); p->astream = -1; }
            } else { p->astream = -1; }
        } else { p->astream = -1; }
    }
    if (stats_enabled()) VLOG("pipeline: video_stream=%d audio_stream=%d", p->stream, p->astream);
    p->out_w = p->codec->width ? p->codec->width : 1280;
    p->out_h = p->codec->height ? p->codec->height : 720;
    return 0;
}

// 视频帧计数：真机验证“画面在持续输出”需要它（stats 开启时每 60 帧打印一次）。
static void note_video_frame(VlcPlayer* p) {
    static atomic_llong counter = 0;
    long long n = atomic_fetch_add(&counter, 1) + 1;
    if (stats_enabled() && (n % 60) == 0) {
        VLOG("video stats frames=%lld", n);
    }
    (void)p;
}

static void push_frame(VlcPlayer* p, AVFrame* f) {
    note_video_frame(p);
    if (!p->format_done && p->setup) {
        VLOG("setup called in_w=%d in_h=%d", p->out_w, p->out_h);
        char chroma[32]; memset(chroma, 0, sizeof chroma);
        unsigned w = (unsigned)p->out_w, h = (unsigned)p->out_h;
        unsigned pitches[4] = {0,0,0,0}, lines[4] = {0,0,0,0};
        void* op = p->opaque;
        unsigned planes = p->setup(&op, chroma, &w, &h, pitches, lines);
        if (planes == 0) return;  // engine rejected
        p->opaque = op;
        p->out_w = (int)w; p->out_h = (int)h;
        VLOG("setup ret planes=%u out=%ux%u chroma=%s", planes, w, h, chroma);
        p->format_done = 1;
    }
    if (!p->lock) { VLOG("no lock cb"); return; }
    void* planes[4] = {0,0,0,0};
    void* pic = p->lock(p->opaque, planes);
    if (!planes[0]) { VLOG("lock no plane"); if (p->unlock) p->unlock(p->opaque, pic, planes); return; }
    int target = AV_PIX_FMT_RGBA;
    // chroma negotiated by engine is RV32/RGBA family; convert accordingly
    p->sws = sws_getCachedContext(p->sws, f->width, f->height, f->format,
                                  p->out_w, p->out_h, target, SWS_BILINEAR, NULL, NULL, NULL);
    if (p->sws) {
        uint8_t* dst[4] = { (uint8_t*)planes[0], 0, 0, 0 };
        int dstlines[4] = { p->out_w * 4, 0, 0, 0 };
        sws_scale(p->sws, (const uint8_t* const*)f->data, f->linesize, 0, f->height, dst, dstlines);
    }
    if (p->unlock) p->unlock(p->opaque, pic, planes);
    if (p->display) p->display(p->opaque, pic);
    if (f->pts != AV_NOPTS_VALUE) {
        AVStream* st = p->fmt->streams[p->stream];
        long ms = (long)(f->pts * 1000.0 * av_q2d(st->time_base));
        atomic_store(&p->position_ms, ms);
    }
}

// ---- pull model: decode advanced on the caller (Cangjie) thread ----
// Called from libvlc_media_player_get_time, which the UI tick invokes; running
// the Cangjie frame callbacks on that thread avoids foreign-thread runtime
// attach problems entirely.
static void ring_write(VlcPlayer* p, const unsigned char* d, size_t n);
static void audio_decode_packet(VlcPlayer* p, AVPacket* pkt);

// 自带音频转换/重采样（输出固定 s16 交错 48k 立体声）。
// 为什么不用 libswresample：真机上 swr_convert 在 44100→48000 场景直接 SIGSEGV
// （同一构建下 48k 直通正常），排查成本高于自己实现。这里覆盖常见 PCM/AAC 解码输出
// 格式：s16/s16p/s32/s32p/f32/f32p/u8，采样率用线性插值重采样，声道做单声道复制/多声道取前两路。
typedef struct {
    double pos;        // 重采样相位（输入采样点，全局推进）
    int primed;
} AudioConvState;

static double conv_read_sample(const AVFrame* f, int ch, int i, int64_t n) {
    if (i < 0 || i >= n) return 0.0;
    switch (f->format) {
        case AV_SAMPLE_FMT_S16:  return ((const int16_t*)f->data[0])[i * f->ch_layout.nb_channels + (ch < f->ch_layout.nb_channels ? ch : 0)] / 32768.0;
        case AV_SAMPLE_FMT_S16P: return ((const int16_t*)f->data[ch < f->ch_layout.nb_channels ? ch : 0])[i] / 32768.0;
        case AV_SAMPLE_FMT_S32:  return ((const int32_t*)f->data[0])[i * f->ch_layout.nb_channels + (ch < f->ch_layout.nb_channels ? ch : 0)] / 2147483648.0;
        case AV_SAMPLE_FMT_S32P: return ((const int32_t*)f->data[ch < f->ch_layout.nb_channels ? ch : 0])[i] / 2147483648.0;
        case AV_SAMPLE_FMT_FLT:  return ((const float*)f->data[0])[i * f->ch_layout.nb_channels + (ch < f->ch_layout.nb_channels ? ch : 0)];
        case AV_SAMPLE_FMT_FLTP: return ((const float*)f->data[ch < f->ch_layout.nb_channels ? ch : 0])[i];
        case AV_SAMPLE_FMT_U8:   return (((const uint8_t*)f->data[0])[i * f->ch_layout.nb_channels + (ch < f->ch_layout.nb_channels ? ch : 0)] - 128) / 128.0;
        case AV_SAMPLE_FMT_U8P:  return (((const uint8_t*)f->data[ch < f->ch_layout.nb_channels ? ch : 0])[i] - 128) / 128.0;
        default: return 0.0;
    }
}

// 把一帧转换成 s16 交错 48k 立体声写进环形缓冲。返回写入的帧数。
static int audio_convert_frame(VlcPlayer* p, AudioConvState* st, const AVFrame* f) {
    int in_rate = f->sample_rate > 0 ? f->sample_rate : 48000;
    int64_t n = f->nb_samples;
    if (n <= 0) return 0;
    double step = (double)in_rate / 48000.0;
    if (step < 0.0001) step = 1.0;
    if (!st->primed) { st->pos = 0.0; st->primed = 1; }

    size_t cap_frames = (size_t)(n / step) + 4;
    int16_t* out = (int16_t*)malloc(cap_frames * 2 * sizeof(int16_t));
    if (!out) return 0;
    size_t o = 0;
    while (st->pos < (double)(n - 1) && o < cap_frames) {
        int i0 = (int)st->pos;
        double frac = st->pos - (double)i0;
        for (int ch = 0; ch < 2; ch++) {
            double s0 = conv_read_sample(f, ch, i0, n);
            double s1 = conv_read_sample(f, ch, i0 + 1, n);
            double v = s0 + (s1 - s0) * frac;
            if (v > 1.0) v = 1.0;
            if (v < -1.0) v = -1.0;
            out[o * 2 + ch] = (int16_t)(v * 32767.0);
        }
        o++;
        st->pos += step;
    }
    st->pos -= (double)n;      // 保留相位余量给下一帧
    if (st->pos < 0.0) st->pos = 0.0;

    size_t bytes = o * 2 * sizeof(int16_t);
    if (bytes > 0) {
        for (;;) {
            pthread_mutex_lock(&p->amu);
            int full = (p->rcap == 0) || (p->rsize + bytes) > p->rcap;
            pthread_mutex_unlock(&p->amu);
            if (full == 0 || p->astop) break;
            usleep(2000);
        }
        if (!p->astop) ring_write(p, (const unsigned char*)out, bytes);
    }
    free(out);
    return (int)o;
}

// 音频包解码：与视频共用同一个 demuxer（pump 里调用），解码 → 重采样 → 环形缓冲。
// 渲染器回调从环形缓冲取数据；不再需要独立的音频线程/第二条连接。
static void audio_decode_packet(VlcPlayer* p, AVPacket* pkt) {
    if (!p->acodec || !p->fctx_tmp) return;
    if (avcodec_send_packet(p->acodec, pkt) != 0) return;
    while (avcodec_receive_frame(p->acodec, p->fctx_tmp) == 0) {
        if (!p->aswr_ok) {
            AVChannelLayout out_ch; av_channel_layout_default(&out_ch, 2);
            AVChannelLayout in_ch;
            if (p->fctx_tmp->ch_layout.nb_channels > 0) av_channel_layout_copy(&in_ch, &p->fctx_tmp->ch_layout);
            else av_channel_layout_default(&in_ch, 2);
            int rate = p->fctx_tmp->sample_rate > 0 ? p->fctx_tmp->sample_rate : 48000;
            if (stats_enabled()) VLOG("swr alloc call in_ch=%d rate=%d fmt=%d", in_ch.nb_channels, rate, p->fctx_tmp->format);
            int rc = swr_alloc_set_opts2(&p->aswr, &out_ch, AV_SAMPLE_FMT_S16, 48000,
                &in_ch, (enum AVSampleFormat)p->fctx_tmp->format, rate, 0, NULL);
            if (rc == 0 && p->aswr && swr_init(p->aswr) == 0) {
                p->aswr_ok = 1;
                if (stats_enabled()) VLOG("audio swr ready: in_ch=%d rate=%d fmt=%d", in_ch.nb_channels, rate, p->fctx_tmp->format);
            } else {
                VLOG("audio swr init failed rc=%d", rc);
            }
        }
        {
            AudioConvState st; st.pos = p->apos; st.primed = p->aprimed;
            audio_convert_frame(p, &st, p->fctx_tmp);
            p->apos = st.pos; p->aprimed = st.primed;
        }
        av_frame_unref(p->fctx_tmp);
    }
}

// 联调钩子：LANLU_SEEK_LOOP_MS=<毫秒> + LANLU_SEEK_TARGETS="2000,8000,..."
// 让播放循环周期性跳转到给定位置，用来在真机上验证 seek 后音画是否继续、是否同步。
static int seek_test_next(long now) {
    static long last = 0;
    static int idx = 0;
    static int parsed = 0;
    static int count = 0;
    static long targets[16];
    const char* loop_env = getenv("LANLU_SEEK_LOOP_MS");
    const char* tgt_env = getenv("LANLU_SEEK_TARGETS");
    if (!loop_env || !tgt_env) return -1;
    if (!parsed) {
        parsed = 1;
        const char* c = tgt_env;
        while (*c && count < 16) {
            long v = strtol(c, (char**)&c, 10);
            targets[count++] = v;
            if (*c == ',') c++;
            else break;
        }
    }
    if (count == 0) return -1;
    long period = strtol(loop_env, NULL, 10);
    if (period <= 0) period = 5000;
    if (last == 0) { last = now; return -1; }
    if (now - last < period) return -1;
    last = now;
    int t = (int)targets[idx % count];
    idx++;
    return t;
}

static void pump(VlcPlayer* p) {
    if (!p->fmt || atomic_load(&p->paused)) { p->last_tick_ms = now_ms(); return; }
    int sk = atomic_exchange(&p->seek_ms, -1);
    if (sk < 0) {
        int t = seek_test_next(now_ms());
        if (t >= 0) { sk = t; VLOG("seek-test -> %d ms", t); }
    }
    if (sk >= 0) {
        AVRational tb = av_make_q(1, 1000);
        avformat_seek_file(p->fmt, p->stream, INT64_MIN,
            av_rescale_q(sk, tb, p->fmt->streams[p->stream]->time_base), INT64_MAX, 0);
        avcodec_flush_buffers(p->codec);
        if (p->acodec) avcodec_flush_buffers(p->acodec);
        if (p->aswr) swr_convert(p->aswr, NULL, 0, NULL, 0);   // 丢弃重采样残留
        pthread_mutex_lock(&p->amu); p->rhead = p->rtail = p->rsize = 0; pthread_mutex_unlock(&p->amu);
        p->next_pts_ms = (double)sk;
        p->last_tick_ms = now_ms();
    }
    long now = now_ms();
    if (p->last_tick_ms == 0) p->last_tick_ms = now;
    double elapsed = (double)(now - p->last_tick_ms);
    // decode at most ~3 frames of catch-up per tick
    int budget = 3;
    while (budget-- > 0) {
        if (av_read_frame(p->fmt, p->pkt) < 0) { atomic_store(&p->running, 0); break; }
        if (p->pkt->stream_index == p->astream && p->acodec) {
            audio_decode_packet(p, p->pkt);
            av_packet_unref(p->pkt);
            continue;                     // 音频包不打断视频预算，继续读下一个
        }
        if (p->pkt->stream_index != p->stream) { av_packet_unref(p->pkt); continue; }
        int got = 0;
        if (avcodec_send_packet(p->codec, p->pkt) == 0) {
            while (avcodec_receive_frame(p->codec, p->frm) == 0) {
                if (p->frm->pts != AV_NOPTS_VALUE) {
                    double ms = p->frm->pts * 1000.0 * av_q2d(p->fmt->streams[p->stream]->time_base);
                    p->next_pts_ms = ms;
                    atomic_store(&p->position_ms, (long)ms);
                }
                push_frame(p, p->frm);
                av_frame_unref(p->frm);
                got = 1;
                break;  // one frame per packet; pace across ticks
            }
        }
        av_packet_unref(p->pkt);
        if (got) break;
    }
    p->last_tick_ms = now;
    (void)elapsed;
}


// ---------------- audio (OH_AudioRenderer + ffmpeg, pure-C thread) -------------
// 写入环形缓冲：memcpy 分两段（跨尾部时），临界区只包住指针与 memcpy，
// 避免逐字节持锁把音频回调线程饿死（真机曾表现为回调 3 次后不再被拉取）。
static void ring_write(VlcPlayer* p, const unsigned char* d, size_t n) {
    if (!p || n == 0) return;
    if (n > p->rcap) {           // 超过整圈：只保留最后 rcap 字节
        d += (n - p->rcap);
        n = p->rcap;
    }
    pthread_mutex_lock(&p->amu);
    if (!p->ring) { pthread_mutex_unlock(&p->amu); return; }
    while (p->rsize + n > p->rcap) {   // 满：丢最旧，保证新数据完整写入
        size_t drop = p->rsize + n - p->rcap;
        if (drop > p->rsize) drop = p->rsize;
        p->rtail = (p->rtail + drop) % p->rcap;
        p->rsize -= drop;
    }
    size_t first = p->rcap - p->rhead;
    if (first > n) first = n;
    memcpy(p->ring + p->rhead, d, first);
    if (n > first) memcpy(p->ring, d + first, n - first);
    p->rhead = (p->rhead + n) % p->rcap;
    p->rsize += n;
    pthread_cond_signal(&p->acv);
    pthread_mutex_unlock(&p->amu);
}
static void audio_write_cb(OH_AudioRenderer* r, void* user, void* data, int32_t size) {
    (void)r; VlcPlayer* p = (VlcPlayer*)user;
    if (stats_enabled()) {
        static long long cb_calls = 0;
        cb_calls++;
        if (cb_calls <= 3 || (cb_calls % 200) == 0) {
            int64_t fw = 0;
            if (p && p->renderer) OH_AudioRenderer_GetFramesWritten(p->renderer, &fw);
            VLOG("audio write cb calls=%lld frames=%lld", cb_calls, (long long)fw);
        }
    }
    unsigned char* out = (unsigned char*)data;
    int32_t got = 0;
    if (p && !atomic_load(&p->muted)) {
        size_t want = (size_t)size;
        pthread_mutex_lock(&p->amu);
        // p->ring 可能已被 audio_stop 释放：必须在锁内判空后再访问，
        // 否则回调线程会读到已释放内存（真机表现为播放约 4s 后 SIGSEGV）。
        if (!p->ring) {
            pthread_mutex_unlock(&p->amu);
            for (; got < size; got++) out[got] = 0;
            return;
        }
        size_t avail0 = 0; (void)avail0;
        size_t avail = p->rsize < want ? p->rsize : want;
        size_t first = p->rcap - p->rtail;
        if (first > avail) first = avail;
        if (avail) {
            memcpy(out, p->ring + p->rtail, first);
            if (avail > first) memcpy(out + first, p->ring, avail - first);
            p->rtail = (p->rtail + avail) % p->rcap;
            p->rsize -= avail;
        }
        got = (int32_t)avail;
        pthread_mutex_unlock(&p->amu);
    }
    for (; got < size; got++) out[got] = 0;
}
static void* audio_loop(void* arg) {
    VlcPlayer* p = (VlcPlayer*)arg;
    AVFormatContext* af = NULL; AVCodecContext* ac = NULL;
    struct SwrContext* swr = NULL; AVPacket* pkt = av_packet_alloc(); AVFrame* fr = av_frame_alloc();
    if (avformat_open_input(&af, p->path, NULL, NULL) == 0 && avformat_find_stream_info(af, NULL) >= 0) {
        int ai = av_find_best_stream(af, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
        if (stats_enabled()) VLOG("audio open: streams=%u best_audio=%d", af->nb_streams, ai);
        const AVCodec* dec = ai >= 0 ? avcodec_find_decoder(af->streams[ai]->codecpar->codec_id) : NULL;
        if (stats_enabled()) {
            VLOG("audio codec=%s dec=%p", ai >= 0 ? avcodec_get_name(af->streams[ai]->codecpar->codec_id) : "none", (void*)dec);
        }
        if (dec) {
            ac = avcodec_alloc_context3(dec);
            avcodec_parameters_to_context(ac, af->streams[ai]->codecpar);
            int open_rc = avcodec_open2(ac, dec, NULL);
            if (stats_enabled()) VLOG("audio dec_open rc=%d", open_rc);
            if (open_rc == 0) {
                // swr 惰性初始化：PCM 等流在 avcodec_open2 后 ch_layout/sample_rate 可能仍为空，
                // 用首帧的真实参数建立重采样器（此前直接初始化会导致 swr_convert 崩溃）。
                int swr_ok = 0;
                if (stats_enabled()) VLOG("audio params before first frame: ch=%d rate=%d fmt=%d",
                    ac->ch_layout.nb_channels, ac->sample_rate, (int)ac->sample_fmt);
                struct timespec stat_ts; clock_gettime(CLOCK_MONOTONIC, &stat_ts);
                long long stat_next = (long long)stat_ts.tv_sec + 3;
                while (!p->astop) {
                    if (stats_enabled()) {
                        struct timespec now_ts; clock_gettime(CLOCK_MONOTONIC, &now_ts);
                        if ((long long)now_ts.tv_sec >= stat_next) {
                            stat_next = (long long)now_ts.tv_sec + 3;
                            int64_t fw = 0;
                            if (p->renderer) OH_AudioRenderer_GetFramesWritten(p->renderer, &fw);
                            VLOG("audio stats frames_written=%lld ring=%u", (long long)fw, p->rsize);
                        }
                    }
                    // 跟随视频 seek：音频有自己的 demuxer/decoder，必须自行 seek，
                    // 否则 seek 后画面跳转而声音停在原位置。
                    int ask = atomic_exchange(&p->audio_seek_ms, -1);
                    if (ask >= 0) {
                        avformat_seek_file(af, ai, INT64_MIN, (int64_t)ask * 1000, INT64_MAX, 0);
                        avcodec_flush_buffers(ac);
                        // 丢弃已排队旧音频，避免 seek 后先听到旧片段
                        pthread_mutex_lock(&p->amu); p->rsize = 0; p->rhead = p->rtail = 0; pthread_mutex_unlock(&p->amu);
                        VLOG("audio seek to %d ms", ask);
                    }
                    if (av_read_frame(af, pkt) < 0) break;
                    if (pkt->stream_index != ai) { av_packet_unref(pkt); continue; }
                    if (avcodec_send_packet(ac, pkt) == 0) {
                        while (avcodec_receive_frame(ac, fr) == 0) {
                            if (!swr_ok) {
                                AVChannelLayout out_ch; av_channel_layout_default(&out_ch, 2);
                                AVChannelLayout in_ch;
                                if (fr->ch_layout.nb_channels > 0) {
                                    av_channel_layout_copy(&in_ch, &fr->ch_layout);
                                } else {
                                    av_channel_layout_default(&in_ch, 2);
                                }
                                int rate = fr->sample_rate > 0 ? fr->sample_rate : ac->sample_rate;
                                if (rate <= 0) rate = 48000;
                                int rc2 = swr_alloc_set_opts2(&swr, &out_ch, AV_SAMPLE_FMT_S16, 48000,
                                    &in_ch, (enum AVSampleFormat)fr->format, rate, 0, NULL);
                                if (rc2 == 0 && swr && swr_init(swr) == 0) {
                                    swr_ok = 1;
                                    if (stats_enabled()) VLOG("audio swr ready: in_ch=%d rate=%d fmt=%d",
                                        in_ch.nb_channels, rate, fr->format);
                                } else {
                                    VLOG("audio swr init failed rc=%d", rc2);
                                }
                            }
                            if (!swr_ok) { av_frame_unref(fr); continue; }
                            // 规范用法：固定输出容量 + 排空 swr 内部缓冲，避免以
                            // nb_samples 作为 out_count 时因重采样比例导致的越界。
                            const int out_cap = 2048;   // 帧
                            uint8_t* obuf = NULL;
                            int outn = swr_convert(swr, &obuf, out_cap,
                                (const uint8_t**)fr->data, fr->nb_samples);
                            while (outn > 0) {
                                size_t bytes = (size_t)outn * 2 * 2;  // 2ch s16
                                for (;;) {
                                    pthread_mutex_lock(&p->amu);
                                    int full = (p->rcap == 0) || (p->rsize + bytes) > p->rcap;
                                    pthread_mutex_unlock(&p->amu);
                                    if (full == 0 || p->astop) break;
                                    usleep(5000);
                                }
                                if (p->astop) break;
                                ring_write(p, obuf, bytes);
                                if (swr_get_out_samples(swr, 0) <= 0) break;
                                outn = swr_convert(swr, &obuf, out_cap, NULL, 0);
                            }
                            av_frame_unref(fr);
                        }
                    }
                    av_packet_unref(pkt);
                }
            }
        }
    } else {
        VLOG("audio: open_input/find_stream_info failed");
    }
    VLOG("audio loop exit: astop=%d", p->astop);
    if (swr) swr_free(&swr);
    if (ac) avcodec_free_context(&ac);
    if (af) avformat_close_input(&af);
    if (pkt) av_packet_free(&pkt);
    if (fr) av_frame_free(&fr);
    return 0;
}
// 音频中断回调：被其它应用抢占/系统打断时至少留下痕迹（后续可在此恢复）。
static void audio_interrupt_cb(OH_AudioRenderer* r, void* user, OH_AudioInterrupt_ForceType type, OH_AudioInterrupt_Hint hint) {
    (void)r; (void)user;
    VLOG("audio interrupt type=%d hint=%d", (int)type, (int)hint);
}

static void audio_start(VlcPlayer* p) {
    // 调试开关：完全跳过音频线程（用于二分定位音视频问题）
    if (getenv("LANLU_VLC_NO_AUDIO")) { VLOG("audio disabled by LANLU_VLC_NO_AUDIO"); return; }
    if (p->athread_started) return;
    p->astop = 0; atomic_store(&p->muted, 0);
    { size_t cap = 1024 * 1024; unsigned char* buf = malloc(cap);
      pthread_mutex_lock(&p->amu);
      p->ring = buf; p->rcap = cap; p->rhead = p->rtail = p->rsize = 0;
      pthread_mutex_unlock(&p->amu); }
    OH_AudioStreamBuilder* b = NULL;
    if (OH_AudioStreamBuilder_Create(&b, AUDIOSTREAM_TYPE_RENDERER) == AUDIOSTREAM_SUCCESS && b) {
        OH_AudioStreamBuilder_SetSamplingRate(b, 48000);
        OH_AudioStreamBuilder_SetChannelCount(b, 2);
        OH_AudioStreamBuilder_SetSampleFormat(b, AUDIOSTREAM_SAMPLE_S16LE);
        OH_AudioStreamBuilder_SetEncodingType(b, AUDIOSTREAM_ENCODING_TYPE_RAW);
        OH_AudioStreamBuilder_SetRendererInfo(b, AUDIOSTREAM_USAGE_MUSIC);
        OH_AudioStreamBuilder_SetRendererWriteDataCallback(b, audio_write_cb, p);
        OH_AudioStreamBuilder_SetRendererInterruptCallback(b, audio_interrupt_cb, p);
        // 20ms/次（960 帧）：块大一些，回调频率降低，抗调度抖动
        OH_AudioStreamBuilder_SetFrameSizeInCallback(b, 960);
        OH_AudioStreamBuilder_GenerateRenderer(b, &p->renderer);
        OH_AudioStreamBuilder_Destroy(b);
    }
    static OH_AudioSessionManager* sess_mgr = NULL;
    if (!sess_mgr) OH_AudioManager_GetAudioSessionManager(&sess_mgr);
    int scene_rc = -1, act_rc = -1;
    if (sess_mgr) {
        scene_rc = (int)OH_AudioSessionManager_SetScene(sess_mgr, AUDIO_SESSION_SCENE_MEDIA);
        OH_AudioSession_Strategy st;
        memset(&st, 0, sizeof st);
        st.concurrencyMode = CONCURRENCY_DEFAULT;   /* 与其它应用共存的默认并发策略 */
        act_rc = (int)OH_AudioSessionManager_ActivateAudioSession(sess_mgr, &st);
    }
    VLOG("audio session mgr=%p scene_rc=%d activate_rc=%d", (void*)sess_mgr, scene_rc, act_rc);
    int start_rc = -1;
    if (p->renderer) start_rc = (int)OH_AudioRenderer_Start(p->renderer);
    // 音频解码已并入 pump（单 demuxer），这里只负责渲染器与环形缓冲。
    VLOG("audio started renderer=%p start_rc=%d (decode in pump)", (void*)p->renderer, start_rc);
}
static void audio_stop(VlcPlayer* p) {
    p->astop = 1;
    if (p->athread_started) { pthread_join(p->athread, NULL); p->athread_started = 0; }
    if (p->renderer) { int64_t fw = 0; OH_AudioRenderer_GetFramesWritten(p->renderer, &fw); VLOG("audio frames_written=%lld", (long long)fw); OH_AudioRenderer_Stop(p->renderer); OH_AudioRenderer_Release(p->renderer); p->renderer = NULL; }
    pthread_mutex_lock(&p->amu);
    if (p->ring) { free(p->ring); p->ring = NULL; p->rcap = 0; p->rhead = p->rtail = p->rsize = 0; }
    pthread_mutex_unlock(&p->amu);
}

int32_t libvlc_media_player_play(PlayerPtr pp) {
    VlcPlayer* p = (VlcPlayer*)pp;
    if (!p) return -1;
    if (!p->fmt) { if (open_pipeline(p) != 0) return -1; }
    atomic_store(&p->running, 1);
    atomic_store(&p->paused, 0);
    p->last_tick_ms = 0;
    audio_start(p);
    return 0;
}
void libvlc_media_player_set_pause(PlayerPtr pp, int paused) { VlcPlayer* p=(VlcPlayer*)pp; if(p) atomic_store(&p->paused, paused?1:0); }
void libvlc_media_player_stop(PlayerPtr pp) { VlcPlayer* p=(VlcPlayer*)pp; if(p){ atomic_store(&p->running,0); audio_stop(p); } }
int32_t libvlc_media_player_set_time(PlayerPtr pp, int64_t ms) { VlcPlayer* p=(VlcPlayer*)pp; if(!p) return -1; atomic_store(&p->seek_ms,(int)ms); atomic_store(&p->audio_seek_ms,(int)ms); return 0; }
int64_t libvlc_media_player_get_time(PlayerPtr pp) { VlcPlayer* p=(VlcPlayer*)pp; if(!p) return 0; if(atomic_load(&p->running)) pump(p); return atomic_load(&p->position_ms); }
int64_t libvlc_media_player_get_length(PlayerPtr pp) { VlcPlayer* p=(VlcPlayer*)pp; return p? atomic_load(&p->duration_ms):0; }
int32_t libvlc_audio_set_mute(PlayerPtr pp, int m) { VlcPlayer* p=(VlcPlayer*)pp; if(p) atomic_store(&p->muted, m?1:0); return 0; }
int32_t libvlc_audio_set_volume(PlayerPtr pp, int v) { VlcPlayer* p=(VlcPlayer*)pp; if(p&&p->renderer) OH_AudioRenderer_SetVolume(p->renderer, (float)v/100.0f); return 0; }
int32_t libvlc_video_get_spu(PlayerPtr pp) { (void)pp; return -1; }
void* libvlc_video_get_spu_description(PlayerPtr pp) { (void)pp; return 0; }
int32_t libvlc_video_set_spu(PlayerPtr pp, int id) { (void)pp; (void)id; return -1; }
void libvlc_track_description_list_release(void* d) { (void)d; }

void libvlc_video_set_callbacks(PlayerPtr pp, LockCb lock, UnlockCb unlock, DisplayCb display, void* opaque) {
    VlcPlayer* p = (VlcPlayer*)pp;
    if (!p) return;
    // keep media path: opaque points to it until now; move to path buffer
    if (p->opaque && p->opaque != (void*)p->path && !p->lock) {
        snprintf(p->path, sizeof p->path, "%s", (const char*)p->opaque);
        free(p->opaque);
    }
    p->lock = lock; p->unlock = unlock; p->display = display; p->opaque = opaque;
}
void libvlc_video_set_format_callbacks(PlayerPtr pp, SetupCb setup, CleanupCb cleanup) {
    VlcPlayer* p = (VlcPlayer*)pp;
    if (!p) return;
    p->setup = setup; p->cleanup = cleanup;
}
