# Third Party Libraries

This directory contains third-party libraries required for hardware-accelerated video decoding.

## Directory Structure

```
third_party/
├── ffmpeg/
│   └── linux/
│       └── x86_64/
│           ├── bin/
│           │   └── ffmpeg
│           ├── lib/
│           │   ├── libavcodec.so
│           │   ├── libavutil.so
│           │   └── ...
│           └── lib/pkgconfig/
│               └── *.pc
├── pyav/
│   └── linux/
│       └── x86_64/
│           └── lib/
│               └── pythonX.Y/
│                   └── site-packages/
│                       └── av/
└── vaapi/
    └── linux/
        └── x86_64/
            └── lib/
                ├── libva.so.2
                ├── libva-drm.so.2
                └── dri/
                    └── iHD_drv_video.so
```

## Components

### FFmpeg
FFmpeg compiled with VAAPI (Video Acceleration API) support for hardware-accelerated video decoding.

**Purpose**: Provides video codec support with hardware acceleration
**Supported Codecs**: H.264, HEVC/H.265, VP8, VP9, MPEG2, MJPEG
**Build Script**: `scripts/build_ffmpeg_with_vaapi.sh`

### PyAV
PyAV (Python bindings for FFmpeg) built against the custom FFmpeg installation.

**Purpose**: Python interface to FFmpeg libraries
**Version**: Latest from PyAV repository
**Build Script**: `scripts/build_pyav_with_vaapi.sh`

### VAAPI Libraries
VAAPI runtime libraries and GPU drivers for hardware acceleration.

**Purpose**: Hardware acceleration interface for Intel/AMD GPUs
**Components**: libva, libva-drm, GPU drivers (iHD, i965, radeonsi, etc.)
**Build Script**: `scripts/collect_vaapi_libs.sh`

## Building

### Step 1: Build FFmpeg

```bash
chmod +x scripts/build_ffmpeg_with_vaapi.sh
./scripts/build_ffmpeg_with_vaapi.sh
```

This downloads FFmpeg source, configures with VAAPI support, and builds it.

### Step 2: Build PyAV

```bash
chmod +x scripts/build_pyav_with_vaapi.sh
./scripts/build_pyav_with_vaapi.sh
```

This clones PyAV, builds it against custom FFmpeg, and installs it.

### Step 3: Collect VAAPI Libraries

```bash
chmod +x scripts/collect_vaapi_libs.sh
./scripts/collect_vaapi_libs.sh
```

This collects VAAPI runtime libraries from the system.

## Usage

### Automatic Loading

The application automatically loads these libraries by setting environment variables:

- `LD_LIBRARY_PATH`: FFmpeg and VAAPI library paths
- `LIBVA_DRIVERS_PATH`: VAAPI driver directory
- `PYTHONPATH`: PyAV package location

See `miot_kit/miot/decoder.py` for implementation details.

### Manual Loading

For development, you can manually set environment variables:

```bash
export LD_LIBRARY_PATH="$PWD/third_party/ffmpeg/linux/x86_64/lib:$PWD/third_party/vaapi/linux/x86_64/lib:$LD_LIBRARY_PATH"
export LIBVA_DRIVERS_PATH="$PWD/third_party/vaapi/linux/x86_64/lib/dri"
export PYTHONPATH="$PWD/third_party/pyav/linux/x86_64/lib/python3.X/site-packages:$PYTHONPATH"
```

## Platform Support

Currently, the following platforms are supported:
- **Linux x86_64**: Intel/AMD GPUs with VAAPI support

## Notes

- These libraries are self-contained and do not depend on system-installed versions
- They will be loaded at runtime by setting appropriate environment variables
- The application automatically detects and uses these libraries when available

## Documentation

For detailed build and usage instructions:
- [Build Guide](../docs/development/build_with_hardware_acceleration.md)
- [Usage Guide](../docs/usage/hardware_acceleration.md)
- [Chinese Usage Guide](../docs/usage/hardware_acceleration.zh-Hans.md)

## References

- [FFmpeg](https://ffmpeg.org/)
- [PyAV](https://github.com/PyAV-Org/PyAV)
- [VAAPI](https://github.com/intel/libva)
- [Intel Quick Sync Video](https://www.intel.com/content/www/us/en/developer/tools-technologies/intel-quick-sync-video)
