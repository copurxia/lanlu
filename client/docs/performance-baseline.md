# Client performance baseline

The client writes lightweight `[perf]` marks to a dedicated MMKV ring buffer.
They are always on (independent of diagnostic debug logging) and are shown
together with the normal diagnostic log in **Settings → Diagnostics → View logs**.

## Collecting a baseline

Use the release APK and keep the device unplugged from the debugger.

For the cold-start part, with a device connected over adb:

```bash
./client/scripts/collect-perf-baseline.sh /workspace/lanlu/lanlu-client-1.0-release.apk
```

The script performs three `am force-stop` + `am start -W` runs, one swipe, and
captures `dumpsys gfxinfo` plus logcat. Afterwards share the Diagnostics log;
`[perf]` lines start with `s=<session>` so the three cold-start processes can be
separated. The script cannot pull the perf MMKV buffer from a non-debuggable
release, so the Diagnostics share is still required.

1. Cold start with an existing login and cached Home data.
2. Wait until the first Home row is visible, then idle for 2 seconds.
3. Scroll the Home rows down/up once.
4. Switch to Favorites, wait for the first page, scroll once.
5. Open a collection, wait for the first member page, scroll once.
6. Open Diagnostics and share the log.

Repeat the run three times and compare the same event names. Do not compare a
cold start against a warm foreground resume.

## Event map

| Event | Meaning |
|---|---|
| `app.module` | App JS module graph starts evaluating |
| `app.first_render` | `App` renders for the first time |
| `app.shell_render` | Theme/shell is mounted |
| `auth.boot.start` | AuthProvider starts restoring the session |
| `auth.storage_ready` | Servers + active server read from storage |
| `auth.server_ready` | Token read + in-memory session primed |
| `auth.cached_user` | Cached user is rendered immediately |
| `auth.me_ready` | Background `/api/auth/me` validation finished |
| `auth.offline_restore` | Network probe failed; cached/offline path used |
| `nav.booting_render` | Root navigator renders the boot spinner |
| `nav.authenticated` | Authenticated navigator is ready |
| `home.mount` | HomeScreen first render |
| `home.rows.cache` | Cached row landing page applied |
| `home.discover.ready` | Categories + discover request returned |
| `home.aggregate.ready` | Category aggregate rows applied |
| `home.rows.ready` | All category rows (incl. fallbacks) applied |
| `home.feed.cache` | Flat feed cache applied |
| `home.feed.ready` | Flat feed page returned |
| `favorites.mount` | FavoritesScreen first render |
| `favorites.load.start` | Favorites/History page request starts |
| `favorites.cache` | Cached Favorites/History first page applied |
| `favorites.page.ready` | A Favorites/History page returned |
| `tankoubon.members.ready` | A collection member page returned |
| `scroll.<surface>` | One drag summary: duration, samples, average/max frame gap (ms), slow frames (>50 ms), offset |

The `ms` field on `*_ready`/`discover.ms` marks is the duration since the
relevant start mark (`home.mount` or the matching request start). Scroll marks
are per gesture and intentionally contain no user content.

## Reading the numbers

- Startup: `app.first_render → nav.authenticated → home.mount → home.rows.ready`.
- A large `auth.me_ready` gap usually means the server probe is slow; the cached
  path should already have painted Home before it.
- A large `home.rows.ready` minus `home.discover.ready` means category aggregate
  or fallback requests are the bottleneck.
- Scroll `avgGapMs` near 16 ms is smooth; `slowFrames` counts gaps over 50 ms.
