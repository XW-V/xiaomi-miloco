# Third Party Libraries

This directory contains third-party libraries required for hardware-accelerated video decoding.

## Directory Structure

- `ffmpeg/` - FFmpeg libraries compiled with VAAPI support
- `vaapi/` - VAAPI runtime libraries for hardware acceleration

## Building FFmpeg with VAAPI Support

See `scripts/build_ffmpeg_with_vaapi.sh` for instructions on building FFmpeg with VAAPI hardware acceleration support.

## Collecting VAAPI Libraries

See `scripts/collect_vaapi_libs.sh` for instructions on collecting VAAPI runtime libraries from the system.

## Platform Support

Currently, the following platforms are supported:
- Linux x86_64 (Intel/AMD GPUs with VAAPI support)

## Notes

These libraries are self-contained and do not depend on system-installed versions. They will be loaded at runtime by setting appropriate environment variables.
