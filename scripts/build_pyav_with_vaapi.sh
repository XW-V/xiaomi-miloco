#!/bin/bash
# Build PyAV from source against custom FFmpeg with VAAPI support
# This script builds PyAV and links it to the custom FFmpeg installation

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
FFMPEG_DIR="$THIRD_PARTY_DIR/ffmpeg/linux/x86_64"
PYAV_BUILD_DIR="$THIRD_PARTY_DIR/pyav/linux/x86_64"

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

# Check if FFmpeg was built
if [ ! -d "$FFMPEG_DIR" ] || [ ! -f "$FFMPEG_DIR/lib/pkgconfig/libavcodec.pc" ]; then
    echo_error "FFmpeg not found or not built!"
    echo_error "Please run scripts/build_ffmpeg_with_vaapi.sh first"
    exit 1
fi

echo_info "Found FFmpeg installation at: $FFMPEG_DIR"

# Check dependencies
echo_info "Checking dependencies..."
DEPS=("git" "python3" "pip3" "pkg-config")
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

# Check Python development packages
echo_info "Checking Python development packages..."
python3 -c "import Cython" 2>/dev/null || MISSING_DEPS+=("python3-cython")
python3 -c "import numpy" 2>/dev/null || MISSING_DEPS+=("python3-numpy")

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo_warn "Missing Python packages: ${MISSING_DEPS[*]}"
    echo_warn "Installing missing packages..."
    pip3 install cython numpy
fi

# Create build directory
mkdir -p "$PYAV_BUILD_DIR"
cd "$THIRD_PARTY_DIR"

# Clone PyAV repository
if [ ! -d "PyAV" ]; then
    echo_info "Cloning PyAV repository..."
    git clone https://github.com/PyAV-Org/PyAV.git
    echo_info "PyAV repository cloned successfully"
else
    echo_info "PyAV repository already exists, updating..."
    cd PyAV
    git pull
    cd ..
fi

cd PyAV

# Set environment variables to use custom FFmpeg
export PKG_CONFIG_PATH="$FFMPEG_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$FFMPEG_DIR/lib:$LD_LIBRARY_PATH"

echo_info "Using custom FFmpeg for PyAV build"
echo_info "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
echo_info "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

# Verify FFmpeg detection
echo_info "Verifying FFmpeg detection..."
if pkg-config --exists libavcodec libavutil libavformat libswscale; then
    echo_info "FFmpeg libraries detected via pkg-config"
    echo_info "libavcodec version: $(pkg-config --modversion libavcodec)"
else
    echo_error "Failed to detect FFmpeg libraries via pkg-config"
    exit 1
fi

# Build PyAV
echo_info "Building PyAV..."
python3 setup.py build_ext \
    --ffmpeg-dir="$FFMPEG_DIR" \
    --no-config

# Install PyAV to custom location
echo_info "Installing PyAV to $PYAV_BUILD_DIR..."
python3 setup.py install \
    --prefix="$PYAV_BUILD_DIR" \
    --no-config

# Create site-packages directory structure
SITE_PACKAGES="$PYAV_BUILD_DIR/lib/python$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')/site-packages"
mkdir -p "$SITE_PACKAGES"

# Move PyAV package
if [ -d "build/lib" ]; then
    echo_info "Moving PyAV package to site-packages..."
    cp -r build/lib/* "$SITE_PACKAGES/"
    echo_info "PyAV installed to $SITE_PACKAGES"
else
    echo_error "PyAV build directory not found"
    exit 1
fi

# Copy pkg-config files
echo_info "Copying pkg-config files..."
mkdir -p "$PYAV_BUILD_DIR/lib/pkgconfig"
if [ -f "pyav.pc" ]; then
    cp pyav.pc "$PYAV_BUILD_DIR/lib/pkgconfig/"
    echo_info "pyav.pc copied"
fi

# Create a simple test script
cat > "$PYAV_BUILD_DIR/test_pyav.py" << 'EOF'
#!/usr/bin/env python3
import sys
sys.path.insert(0, '$SITE_PACKAGES')

import av
print(f"PyAV version: {av.__version__}")

# Test if we can create a codec context
try:
    codec = av.CodecContext.create('h264', 'r')
    print(f"Successfully created h264 decoder")
    
    # Check if VAAPI is available
    result = subprocess.run(['ffmpeg', '-hwaccels'], 
                         capture_output=True, text=True)
    if 'vaapi' in result.stdout:
        print("VAAPI support detected in FFmpeg")
    else:
        print("VAAPI support NOT detected in FFmpeg")
        
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)

print("PyAV test successful!")
EOF

chmod +x "$PYAV_BUILD_DIR/test_pyav.py"

# Verify installation
echo_info "Verifying PyAV installation..."
if [ -f "$SITE_PACKAGES/av/__init__.py" ]; then
    echo_info "PyAV package found at $SITE_PACKAGES/av/"
else
    echo_error "PyAV package not found"
    exit 1
fi

echo_info "PyAV built against custom FFmpeg successfully!"
echo_info "PyAV installation: $PYAV_BUILD_DIR"
echo_info ""
echo_info "Next steps:"
echo_info "1. Add PyAV to Python path: export PYTHONPATH=\$PYTHONPATH:$PYAV_BUILD_DIR/lib/pythonX.Y/site-packages"
echo_info "2. Or install to system: sudo python3 setup.py install"
echo_info ""
echo_info "To test PyAV:"
echo_info "  cd $PYAV_BUILD_DIR"
echo_info "  ./test_pyav.py"
