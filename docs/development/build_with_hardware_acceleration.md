# Building with Hardware Acceleration - Complete Guide

This guide explains how to build FFmpeg and PyAV with VAAPI support for hardware-accelerated video decoding.

## Overview

To achieve optimal hardware acceleration performance, you need to:
1. Build FFmpeg with VAAPI support
2. Build PyAV against the custom FFmpeg
3. Collect VAAPI runtime libraries

This ensures PyAV can use FFmpeg's VAAPI hardware acceleration capabilities.

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+, Debian 11+)
- **Architecture**: x86_64
- **GPU**: Intel (6th Gen+) or AMD GPU with VAAPI support
- **Device Access**: `/dev/dri/renderD128` or `/dev/dri/card0`

### Build Dependencies

```bash
# Build tools
sudo apt-get update
sudo apt-get install -y \
    git \
    wget \
    tar \
    make \
    gcc \
    g++ \
    yasm \
    pkg-config \
    nasm \
    python3 \
    python3-pip

# FFmpeg development libraries
sudo apt-get install -y \
    libva-dev \
    libva-drm2 \
    libdrm-dev

# Python development packages
sudo apt-get install -y \
    python3-dev \
    python3-cython \
    python3-numpy

# Optional: VAAPI drivers
sudo apt-get install -y \
    intel-media-va-driver-non-free \
    i965-va-driver
```

## Build Process

### Step 1: Build FFmpeg with VAAPI Support

Run the FFmpeg build script:

```bash
chmod +x scripts/build_ffmpeg_with_vaapi.sh
./scripts/build_ffmpeg_with_vaapi.sh
```

**What this does:**
- Downloads FFmpeg 6.1.1 source code
- Configures with VAAPI support
- Builds and installs to `third_party/ffmpeg/linux/x86_64/`
- Enables hardware acceleration for H.264, HEVC, VP8, VP9, etc.

**Expected output:**
```
[INFO] Configuring FFmpeg with VAAPI support...
[INFO] Configuration completed successfully
[INFO] Building FFmpeg (this may take a while)...
[INFO] VAAPI hardware acceleration is supported!
[INFO] Build completed successfully!
```

**Verification:**
```bash
# Check FFmpeg version
third_party/ffmpeg/linux/x86_64/bin/ffmpeg -version

# Check VAAPI support
third_party/ffmpeg/linux/x86_64/bin/ffmpeg -hwaccels
# Should list: vaapi
```

### Step 2: Build PyAV Against Custom FFmpeg

Run the PyAV build script:

```bash
chmod +x scripts/build_pyav_with_vaapi.sh
./scripts/build_pyav_with_vaapi.sh
```

**What this does:**
- Clones PyAV repository
- Builds against custom FFmpeg (from Step 1)
- Installs to `third_party/pyav/linux/x86_64/`
- Links PyAV to VAAPI-enabled FFmpeg libraries

**Expected output:**
```
[INFO] Found FFmpeg installation at: .../third_party/ffmpeg/linux/x86_64
[INFO] Using custom FFmpeg for PyAV build
[INFO] FFmpeg libraries detected via pkg-config
[INFO] libavcodec version: 60.31.100
[INFO] Building PyAV...
[INFO] PyAV built against custom FFmpeg successfully!
```

**Verification:**
```bash
cd third_party/pyav/linux/x86_64
./test_pyav.py
# Should show:
# PyAV version: X.Y.Z
# Successfully created h264 decoder
# VAAPI support detected in FFmpeg
```

### Step 3: Collect VAAPI Runtime Libraries

Run the VAAPI library collection script:

```bash
chmod +x scripts/collect_vaapi_libs.sh
./scripts/collect_vaapi_libs.sh
```

**What this does:**
- Collects VAAPI runtime libraries from system
- Copies Intel/AMD GPU drivers
- Installs to `third_party/vaapi/linux/x86_64/`

**Expected output:**
```
[INFO] Collecting VAAPI runtime libraries...
[INFO] Copying: /usr/lib/x86_64-linux-gnu/libva.so.2 -> ...
[INFO] Found Intel driver: /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so
[INFO] VAAPI libraries collected successfully
```

**Verification:**
```bash
ls -lh third_party/vaapi/linux/x86_64/lib/
# Should show: libva.so.2, libva-drm.so.2, etc.

ls -lh third_party/vaapi/linux/x86_64/lib/dri/
# Should show: iHD_drv_video.so or radeonsi_drv_video.so
```

## Directory Structure After Build

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
│           │   └── ... (other FFmpeg libraries)
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

## Using the Built Components

### Option 1: Development Environment

For development, you can use the built libraries directly:

```bash
# Set environment variables
export LD_LIBRARY_PATH="$PWD/third_party/ffmpeg/linux/x86_64/lib:$PWD/third_party/vaapi/linux/x86_64/lib:$LD_LIBRARY_PATH"
export LIBVA_DRIVERS_PATH="$PWD/third_party/vaapi/linux/x86_64/lib/dri"
export PYTHONPATH="$PWD/third_party/pyav/linux/x86_64/lib/python3.X/site-packages:$PYTHONPATH"

# Run application
python -m miloco_server.main
```

### Option 2: Production Deployment

For production, include the entire `third_party/` directory in your deployment:

1. Copy entire project including `third_party/`
2. Set `LD_LIBRARY_PATH` to include both FFmpeg and VAAPI libraries
3. The application will automatically detect and use the libraries

The library path setup in `miot_kit/miot/decoder.py` will automatically add these paths.

## Configuration

Edit `config/server_config.yaml`:

```yaml
camera:
  frame_interval: 2000
  enable_hw_accel: true        # Enable hardware acceleration
  hw_accel_type: "vaapi"     # Use VAAPI
  hw_device_path: "/dev/dri/renderD128"  # Intel GPU device
```

## Verification

### 1. Check Library Loading

Start the application and check logs for:

```
[INFO] Added FFmpeg library path: .../third_party/ffmpeg/linux/x86_64/lib
[INFO] Added VAAPI library path: .../third_party/vaapi/linux/x86_64/lib
[INFO] Set VAAPI driver path: .../third_party/vaapi/linux/x86_64/lib/dri
[INFO] Added PyAV to Python path: .../third_party/pyav/linux/x86_64/lib/python3.X/site-packages
```

### 2. Check Hardware Acceleration Detection

```
[INFO] PyAV version: X.Y.Z
[INFO] VAAPI device detected, will attempt hardware acceleration
[INFO] Created decoder for hevc, attempting VAAPI hardware acceleration
```

### 3. Monitor Performance

```bash
# CPU usage
htop

# GPU usage (Intel)
intel_gpu_top

# GPU usage (AMD)
radeontop
```

Expected CPU usage reduction: 50-80% for HEVC streams.

## Troubleshooting

### FFmpeg Build Fails

**Problem**: Missing dependencies during FFmpeg build

**Solution**:
```bash
# Install missing dependencies
sudo apt-get install libva-dev libva-drm2 libdrm-dev
```

### PyAV Build Fails

**Problem**: PyAV cannot find FFmpeg libraries

**Solution**:
```bash
# Verify FFmpeg was built
ls third_party/ffmpeg/linux/x86_64/lib/pkgconfig/

# Check PKG_CONFIG_PATH
echo $PKG_CONFIG_PATH
# Should include: .../third_party/ffmpeg/linux/x86_64/lib/pkgconfig
```

### VAAPI Not Detected

**Problem**: "No VAAPI hardware acceleration available"

**Solution**:
```bash
# Check device exists
ls -l /dev/dri/renderD128

# Check VAAPI installation
vainfo

# Install VAAPI drivers
sudo apt-get install intel-media-va-driver-non-free
```

### PyAV Import Error

**Problem**: Cannot import PyAV module

**Solution**:
```bash
# Check Python path
python -c "import sys; print('\n'.join(sys.path))"

# Manually add PyAV
export PYTHONPATH="$PWD/third_party/pyav/linux/x86_64/lib/python3.X/site-packages:$PYTHONPATH"
```

## Clean Build

To rebuild from scratch:

```bash
# Remove build directories
rm -rf third_party/ffmpeg/linux/x86_64
rm -rf third_party/pyav/linux/x86_64
rm -rf third_party/vaapi/linux/x86_64
rm -rf third_party/PyAV

# Rebuild
./scripts/build_ffmpeg_with_vaapi.sh
./scripts/build_pyav_with_vaapi.sh
./scripts/collect_vaapi_libs.sh
```

## Advanced Configuration

### Cross-Platform Builds

For different architectures:

```bash
# ARM64
# Modify scripts to use: linux/arm64

# ARM32
# Modify scripts to use: linux/arm
```

### Custom FFmpeg Version

To use a different FFmpeg version:

Edit `scripts/build_ffmpeg_with_vaapi.sh`:
```bash
FFMPEG_VERSION="7.0"  # Or desired version
```

### Additional Codecs

To add more codec support, modify `scripts/build_ffmpeg_with_vaapi.sh`:

```bash
./configure \
    ...existing options... \
    --enable-libvpx \      # VP8/VP9
    --enable-libtheora \   # Theora
    --enable-libvorbis \    # Vorbis audio
    ...
```

## Performance Tuning

### Thread Configuration

Optimize decoder threading for multi-core CPUs:

```python
# In decoder.py, adjust:
decoder.thread_count = 4  # Use 4 threads
decoder.thread_type = 'auto'
```

### Frame Interval

Adjust frame interval to balance quality and performance:

```yaml
# config/server_config.yaml
camera:
  frame_interval: 1000  # 1 second = higher quality, higher CPU
  frame_interval: 2000  # 2 seconds = lower quality, lower CPU
  frame_interval: 5000  # 5 seconds = lowest quality, lowest CPU
```

## Security Considerations

### Library Integrity

- Verify checksums of downloaded FFmpeg source
- Use official PyAV repository
- Collect VAAPI libraries from trusted system

### Device Permissions

Ensure only authorized users can access GPU:

```bash
# Restrict video group membership
sudo gpasswd -a video username

# Remove user if needed
sudo gpasswd -d video username
```

### Container Deployment

For Docker deployments:

```dockerfile
# Dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    libva2 libva-drm2

# Copy built libraries
COPY third_party/ /app/third_party

# Set library paths
ENV LD_LIBRARY_PATH=/app/third_party/ffmpeg/linux/x86_64/lib:/app/third_party/vaapi/linux/x86_64/lib
ENV LIBVA_DRIVERS_PATH=/app/third_party/vaapi/linux/x86_64/lib/dri

# Pass device
--device /dev/dri/renderD128
```

## References

- [FFmpeg Build Guide](https://trac.ffmpeg.org/wiki/CompilationGuide)
- [PyAV Documentation](https://docs.mikeboers.com/pyav/)
- [VAAPI Documentation](https://github.com/intel/libva)
- [Intel Quick Sync Video](https://www.intel.com/content/www/us/en/developer/tools-technologies/intel-quick-sync-video)

## Summary

Building with hardware acceleration involves:

1. ✅ Build FFmpeg with VAAPI support
2. ✅ Build PyAV against custom FFmpeg
3. ✅ Collect VAAPI runtime libraries
4. ✅ Configure application to use hardware acceleration
5. ✅ Verify performance improvement

Expected results:
- 50-80% CPU usage reduction
- Stable video streaming for HEVC/H.265
- Support for 4K resolution with minimal CPU impact

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review build logs for errors
3. Verify system meets all requirements
4. Consult FFmpeg and PyAV documentation
