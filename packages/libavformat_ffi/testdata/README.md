# Subtitle fixtures

These tiny fixtures are original test data created for Lanlu and are licensed under the same
terms as this repository.

- `basic.ass`, `basic.srt`, and `basic.vtt` are hand-written subtitle sources.
- `mixed.mkv` contains a generated 64×64 black MPEG-4 video plus ASS, SubRip, and WebVTT tracks.
- `mov_text.mp4` contains a generated 64×64 black MPEG-4 video plus a mov_text track.

They can be regenerated with a local FFmpeg developer toolchain; product code never invokes
`ffmpeg` or `ffprobe`. The checked-in media files are the CI inputs.
