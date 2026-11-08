# vips_ffi

Cangjie FFI bindings for [libvips](https://www.libvips.org/) — the fast image
processing library. Minimal, hand-written surface covering what lanlu needs:

- decode from file / memory bytes (jpg, png, webp, avif, ... whatever libvips supports)
- thumbnail / resize / crop
- encode to file / memory
- gaussian blur (`gaussblur`, true Gaussian kernel convolution — used by
  lanlu-ui's modal backdrop effect)

## Requirements

System libvips (with its glib/gobject transitive deps):

```sh
# Debian/Ubuntu
apt install libvips-dev
# macOS
brew install vips
```

Link options are already declared in `cjpm.toml` (equivalent to
`pkg-config --libs vips`).

## Usage

```toml
[dependencies]
vips_ffi = { git = "https://git.copur.xyz/ai/vips-ffi.git", branch = "main" }
```

Consumers: lanlu server (image transcoding pipeline), lanlu client-next
(decode pipeline), lanlu-ui sdl package (modal backdrop blur).

## Layout

Single file binding: `src/libvips_ffi.cj`. Cangjie SDK >= 1.1.0.
