#!/bin/bash
# Abo Linux Build Utility: Main script to build the entire system from source.
set -e

LFS="/root/abo-linux/rootFS"
TARGET="aarch64-lfs-linux-gnu"
BUILD_DIR="tool-build"
LOG_FILE="tool-build/build-log-2025-10-17.log"
export PATH="/usr/bin:/bin" # Ensure minimal, clean PATH for cross-compilation

# --- Helper Functions ---
log() {
    echo "19:01:35 [] " | tee -a 
}

build_package() {
    PKG_NAME=""
    SRC_FILE="source/.tar.xz"
    
    log INFO "Starting build for ..."
    
    if [ ! -f "" ]; then
        log ERROR " source file not found: . Please run wget."
        exit 1
    fi
    
    # Extract
    tar -xf "" -C /tmp
    cd /tmp/
    
    # 1. Binutils (Stage 1 - Cross-Compiler)
    if [ "" = "binutils-2.40" ]; then
        mkdir -p build && cd build
        log INFO "Configuring Binutils..."
        ../configure --prefix=/usr --target= --with-sysroot= --disable-nls --disable-werror
        log INFO "Compiling Binutils (using -j1)..."
        make -j1 # Use -j1 to avoid OOM errors
        log INFO "Installing Binutils..."
        make install
        log SUCCESS "Binutils installed. Ready for GCC Stage 1."
    fi
    
    # 2. GCC (Stage 1 - First pass)
    if [ "" = "gcc-13.2.0" ]; then
        mkdir -p build && cd build
        # We need symlinks for GCC build
        ln -sfv /usr/bin/ld /usr/bin/-ld
        
        log INFO "Configuring GCC Stage 1..."
        ../configure --prefix=/usr --target= --with-sysroot= --disable-nls --disable-libssp --disable-libquadmath
        log INFO "Compiling GCC Stage 1 (using -j1)..."
        make -j1 all-gcc
        log INFO "Installing GCC Stage 1..."
        make install-gcc
        log SUCCESS "GCC Stage 1 installed. Ready for Glibc."
    fi

    # Cleanup
    cd /root/abo-linux
    rm -rf /tmp/
}

# --- Main Build Process ---

# 0. Setup FHS
if [ ! -d "/etc" ]; then
    log INFO "Running mkfhs to create  structure."
    tool-build/mkfhs ""
fi

# 1. Build Toolchain Stage 1
build_package "binutils-2.40"
build_package "gcc-13.2.0"

log SUCCESS "Abo Linux Cross-Toolchain Bootstrap Complete. Next: Glibc and full GCC."

