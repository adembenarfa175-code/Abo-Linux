#!/bin/bash
# util-build-abo-linux.sh - Abo Linux 1 "proxy" Automated Build Tool
# Abo: Arm64 Building Operating System

# ==========================================================
# 1. Configuration: Define Paths and Target Architecture
# ==========================================================

# Determine the absolute path of the abo-linux base directory
ABO_DIR=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_DIR="$ABO_DIR/source"
ROOTFS_DIR="$ABO_DIR/rootFS"
TOOL_BUILD_DIR="$ABO_DIR/tool-build"
LOG_FILE="$TOOL_BUILD_DIR/build-log-$(date +%F).log"

# Define Target Architecture (Default: aarch64 for mobile)
TARGET_ARCH="aarch64" 

# Define Cross-Compilation variables based on the architecture
export LFS_TGT="${TARGET_ARCH}-lfs-linux-gnu"
export LFS="$ROOTFS_DIR"
export PATH="$TOOL_BUILD_DIR/bin:$PATH"

# Configuration Files Lookup (For future steps)
GRUB_CFG="$ABO_DIR/config/grub.${TARGET_ARCH}.cfg"
KERNEL_CFG="$ABO_DIR/config/kernel.${TARGET_ARCH}"
PACKAGE_LIST="$ABO_DIR/config/package.${TARGET_ARCH}"

# ==========================================================
# 2. Logging and Error Handling
# ==========================================================

# Function to log messages
log() {
    echo "$(date +%H:%M:%S) [INFO] $1" | tee -a "$LOG_FILE"
}

# Function to handle build errors
handle_error() {
    log "[ERROR] Build failed at step $1. Check $LOG_FILE for details."
    # Optional: You can add cleanup here if needed
    exit 1
}

# ==========================================================
# 3. Build Core Cross-Toolchain: BINUTILS (LFS Chapter 5.2)
# ==========================================================

build_binutils() {
    log "Starting 5.2: Building Binutils for Cross-Compilation ($LFS_TGT)..."
    
    # 1. Check Source and Extract
    BINUTILS_VERSION="2.40"
    BINUTILS_TARBALL="$SOURCE_DIR/binutils-${BINUTILS_VERSION}.tar.xz"

    if [ ! -f "$BINUTILS_TARBALL" ]; then
        handle_error "Binutils source file not found in $SOURCE_DIR. Please download it first."
    fi
    
    tar -xf "$BINUTILS_TARBALL" -C /tmp/ || handle_error "Extraction of Binutils failed."
    cd "/tmp/binutils-${BINUTILS_VERSION}" || handle_error "cd to Binutils source."

    # 2. Configure for ARM64 (aarch64)
    mkdir -v build
    cd build
    
    log "Configuring Binutils..."
    
    # We use $HOME/abo-linux/tool-build as the prefix (same as $TOOL_BUILD_DIR)
    ../configure --prefix="$TOOL_BUILD_DIR" \
                 --with-sysroot="$ROOTFS_DIR" \
                 --target="$LFS_TGT" \
                 --disable-nls \
                 --enable-gprofng=no \
                 --disable-werror 2>&1 | tee -a "$LOG_FILE" || handle_error "Binutils Configure"

    # 3. Compile and Install
    log "Compiling Binutils (This may take time)..."
    make 2>&1 | tee -a "$LOG_FILE" || handle_error "Binutils Make"
    
    log "Installing Binutils to $TOOL_BUILD_DIR..."
    make install 2>&1 | tee -a "$LOG_FILE" || handle_error "Binutils Install"

    # 4. Cleanup
    cd /tmp
    rm -rf "binutils-${BINUTILS_VERSION}"
    log "Binutils build and cleanup successful. Toolchain is partially ready."
}

# ==========================================================
# 4. Main Execution Flow
# ==========================================================

log "Starting Abo Linux Build Utility (util-build-abo-linux.sh) for $LFS_TGT"
log "Using Kernel Config: $KERNEL_CFG | Package List: $PACKAGE_LIST"

# Check if required directories exist
if [ ! -d "$ROOTFS_DIR" ] || [ ! -d "$TOOL_BUILD_DIR" ]; then
    handle_error "rootFS or tool-build directory not found. Please run initial setup (mkdir) first."
fi

build_binutils

log "Core Toolchain setup is ready for next step: GCC (Chapter 5.3)."

