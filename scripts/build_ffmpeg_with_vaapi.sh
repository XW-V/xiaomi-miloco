#!/bin/bash
# Build FFmpeg with VAAPI support for hardware-accelerated video decoding
# This script downloads FFmpeg source, configures it with VAAPI support, and builds it

set -e

# Configuration
FFMPEG_VERSION="6.1.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
FFMPEG_BUILD_DIR="$THIRD_PARTY_DIR/ffmpeg/linux/x86_64"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo_error "This script is designed for Linux. Current OS: $OSTYPE"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    echo_warn "This script is designed for x86_64. Current architecture: $ARCH"
    echo_warn "You may need to modify the script for your architecture."
fi

# Check dependencies
echo_info "Checking dependencies..."
DEPS=("git" "wget" "tar" "make" "gcc" "g++" "yasm" "pkg-config" "nasm")
MISSING_DEPS=()

for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo_error "Missing dependencies: ${MISSING_DEPS[*]}"
    echo_error "Please install them using your package manager:"
    echo_error "  Ubuntu/Debian: sudo apt-get install ${MISSING_DEPS[*]}"
    exit 1
fi

# Check for VAAPI development libraries
echo_info "Checking for VAAPI development libraries..."
if ! pkg-config --exists libva libva-drm; then
    echo_error "VAAPI development libraries not found!"
    echo_error "Please install them:"
    echo_error "  Ubuntu/Debian: sudo apt-get install libva-dev libva-drm2 libva-intel-driver"
    exit 1
fi

# Create build directory
mkdir -p "$FFMPEG_BUILD_DIR"
cd "$THIRD_PARTY_DIR"

# Download FFmpeg source
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    echo_info "Downloading FFmpeg ${FFMPEG_VERSION}..."
    wget "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -O "ffmpeg.tar.xz"
    tar -xf "ffmpeg.tar.xz"
    rm "ffmpeg.tar.xz"
    echo_info "FFmpeg source extracted successfully"
else
    echo_info "FFmpeg source already exists, skipping download"
fi

cd "ffmpeg-${FFMPEG_VERSION}"

# Configure FFmpeg
echo_info "Configuring FFmpeg with VAAPI support..."
./configure \
    --prefix="$FFMPEG_BUILD_DIR" \
    --enable-shared \
    --disable-static \
    --enable-gpl \
    --enable-version3 \
    --disable-nonfree \
    --enable-libva \
    --enable-libdrm \
    --enable-hwaccel=h264_vaapi \
    --enable-hwaccel=hevc_vaapi \
    --enable-hwaccel=mjpeg_vaapi \
    --enable-hwaccel=mpeg2_vaapi \
    --enable-hwaccel=vp8_vaapi \
    --enable-hwaccel=vp9_vaapi \
    --enable-libx264 \
    --enable-libx265 \
    --disable-doc \
    --disable-debug \
    --enable-pic

echo_info "Configuration completed successfully"

# Build FFmpeg
echo_info "Building FFmpeg (this may take a while)..."
make -j"$(nproc)"

# Install FFmpeg
echo_info "Installing FFmpeg to $FFMPEG_BUILD_DIR..."
make install

# Copy pkg-config files
echo_info "Copying pkg-config files..."
mkdir -p "$FFMPEG_BUILD_DIR/lib/pkgconfig"
cp -f *.pc "$FFMPEG_BUILD_DIR/lib/pkgconfig/" 2>/dev/null || true

# Verify installation
echo_info "Verifying installation..."
if [ -f "$FFMPEG_BUILD_DIR/bin/ffmpeg" ]; then
    echo_info "FFmpeg binary found"
    "$FFMPEG_BUILD_DIR/bin/ffmpeg" -version | head -n 3
fi

if [ -f "$FFMPEG_BUILD_DIR/lib/libavcodec.so" ]; then
    echo_info "libavcodec.so found"
fi

if [ -f "$FFMPEG_BUILD_DIR/lib/libavutil.so" ]; then
    echo_info "libavutil.so found"
fi

# Check VAAPI support
echo_info "Checking VAAPI support in built FFmpeg..."
if "$FFMPEG_BUILD_DIR/bin/ffmpeg" -hwaccels 2>&1 | grep -q vaapi; then
    echo_info "VAAPI hardware acceleration is supported!"
else
    echo_warn "VAAPI support not detected in built FFmpeg"
fi

echo_info "Build completed successfully!"
echo_info "FFmpeg with VAAPI support installed to: $FFMPEG_BUILD_DIR"
echo_info ""
echo_info "Next steps:"
echo_info "1. Run scripts/collect_vaapi_libs.sh to collect VAAPI runtime libraries"
echo_info "2. The libraries will be ready for use in the application"
