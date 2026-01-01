#!/bin/bash
# Collect VAAPI runtime libraries from the system
# This script copies VAAPI libraries to the third_party directory for self-contained deployment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
VAAPI_LIB_DIR="$THIRD_PARTY_DIR/vaapi/linux/x86_64/lib"

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

# Create target directory
mkdir -p "$VAAPI_LIB_DIR"

echo_info "Collecting VAAPI runtime libraries..."

# List of libraries to collect
LIBRARIES=(
    "libva.so.2"
    "libva-drm.so.2"
)

# Function to find library
find_library() {
    local lib_name=$1
    local lib_path=$(ldconfig -p | grep "lib${lib_name}" | head -n 1 | awk '{print $4}')
    
    if [ -z "$lib_path" ]; then
        # Try alternative method
        lib_path=$(find /usr/lib /usr/lib64 /lib /lib64 -name "$lib_name" 2>/dev/null | head -n 1)
    fi
    
    echo "$lib_path"
}

# Function to copy library with dependencies
copy_library() {
    local src=$1
    local dest=$2
    
    if [ ! -f "$src" ]; then
        echo_error "Library not found: $src"
        return 1
    fi
    
    # Copy the library
    echo_info "Copying: $src -> $dest"
    cp "$src" "$dest"
    
    # Get the library's soname
    local soname=$(readelf -d "$src" 2>/dev/null | grep "SONAME" | awk '{print $5}' | tr -d '[]')
    
    if [ -n "$soname" ]; then
        # Create symlink if needed
        local symlink_dest="${dest%/*}/$soname"
        if [ ! -e "$symlink_dest" ]; then
            ln -sf "$(basename "$dest")" "$symlink_dest"
            echo_info "Created symlink: $symlink_dest"
        fi
    fi
    
    return 0
}

# Copy core VAAPI libraries
echo_info "Copying core VAAPI libraries..."
for lib in "${LIBRARIES[@]}"; do
    lib_path=$(find_library "$lib")
    
    if [ -n "$lib_path" ]; then
        copy_library "$lib_path" "$VAAPI_LIB_DIR/$(basename "$lib_path")"
    else
        echo_warn "Library not found: $lib (may not be critical)"
    fi
done

# Collect Intel driver if available
echo_info "Checking for Intel VAAPI driver..."
INTEL_DRIVERS=(
    "iHD_drv_video.so"
    "i965_drv_video.so"
)

for driver in "${INTEL_DRIVERS[@]}"; do
    driver_path=$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu/dri -name "$driver" 2>/dev/null | head -n 1)
    
    if [ -n "$driver_path" ]; then
        echo_info "Found Intel driver: $driver_path"
        
        # Create driver directory
        DRIVER_DIR="$VAAPI_LIB_DIR/dri"
        mkdir -p "$DRIVER_DIR"
        
        copy_library "$driver_path" "$DRIVER_DIR/$(basename "$driver_path")"
        echo_info "Intel driver copied successfully"
        break
    fi
done

# Check for AMD driver if available
echo_info "Checking for AMD VAAPI driver..."
AMD_DRIVERS=(
    "radeonsi_drv_video.so"
    "amdgpu_drv_video.so"
)

for driver in "${AMD_DRIVERS[@]}"; do
    driver_path=$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu/dri -name "$driver" 2>/dev/null | head -n 1)
    
    if [ -n "$driver_path" ]; then
        echo_info "Found AMD driver: $driver_path"
        
        # Create driver directory
        DRIVER_DIR="$VAAPI_LIB_DIR/dri"
        mkdir -p "$DRIVER_DIR"
        
        copy_library "$driver_path" "$DRIVER_DIR/$(basename "$driver_path")"
        echo_info "AMD driver copied successfully"
        break
    fi
done

# Check for libdrm (required for VAAPI)
echo_info "Checking for libdrm..."
LIBDRM_LIBS=(
    "libdrm.so.2"
    "libdrm_amdgpu.so.1"
)

for lib in "${LIBDRM_LIBS[@]}"; do
    lib_path=$(find_library "$lib")
    
    if [ -n "$lib_path" ]; then
        copy_library "$lib_path" "$VAAPI_LIB_DIR/$(basename "$lib_path")"
    fi
done

# List collected libraries
echo_info ""
echo_info "Collected libraries:"
ls -lh "$VAAPI_LIB_DIR/"

# Check for driver directory
if [ -d "$VAAPI_LIB_DIR/dri" ]; then
    echo_info ""
    echo_info "Collected drivers:"
    ls -lh "$VAAPI_LIB_DIR/dri/"
fi

# Verify
echo_info ""
echo_info "Verifying VAAPI setup..."
if [ -f "$VAAPI_LIB_DIR/libva.so.2" ]; then
    echo_info "libva.so.2: Found"
else
    echo_warn "libva.so.2: Not found (VAAPI may not work)"
fi

if [ -d "$VAAPI_LIB_DIR/dri" ] && [ "$(ls -A $VAAPI_LIB_DIR/dri)" ]; then
    echo_info "VAAPI drivers: Found"
else
    echo_warn "VAAPI drivers: Not found (hardware acceleration may not work)"
fi

echo_info ""
echo_info "VAAPI libraries collected successfully to: $VAAPI_LIB_DIR"
echo_info ""
echo_info "Note: These libraries are specific to the system they were collected from."
echo_info "If you deploy to a different system, you may need to collect libraries from that system."
