#!/bin/bash
# Abo Linux Build Utility: Main script to build the entire system from source.
set -e

# === المتغيرات المضافة لضمان العمل المستقل ===
TARGET_ARCH="aarch64"
TARGET_TRIPLE="aarch64-lfs-linux-gnu"
BUILD_DIR="tool-build"
# ==========================================

LFS="/root/abo-linux/rootFS" # يجب أن يكون هذا المسار هو الأساس
TARGET="$TARGET_TRIPLE"
LOG_FILE="$BUILD_DIR/build-log-$(date +%F).log"
export PATH="/usr/bin:/bin" # Ensure minimal, clean PATH for cross-compilation

# --- Helper Functions ---
log() {
    echo "$(date +%H:%M:%S) [$1] $2" | tee -a $LOG_FILE
}

build_package() {
    PKG_NAME="$1"
    SRC_FILE="source/$PKG_NAME.tar.xz"
    
    log INFO "Starting build for $PKG_NAME..."
    
    if [ ! -f "$SRC_FILE" ]; then
        log ERROR "$PKG_NAME source file not found: $SRC_FILE. Please run wget."
        exit 1
    fi
    
    # Extract
    # يجب أن يتم استخراج الملفات إلى مجلد مؤقت آمن
    rm -rf /tmp/$PKG_NAME
    tar -xf "$SRC_FILE" -C /tmp
    cd /tmp/$PKG_NAME
    
    # 1. Binutils (Stage 1 - Cross-Compiler)
    if [ "$PKG_NAME" = "binutils-2.40" ]; then
        mkdir -p build && cd build
        log INFO "Configuring Binutils..."
        ../configure --prefix=/usr --target=$TARGET --with-sysroot=$LFS --disable-nls --disable-werror
        log INFO "Compiling Binutils (using -j1)..."
        make -j1 # Use -j1 to avoid OOM errors
        log INFO "Installing Binutils..."
        make install
        log SUCCESS "Binutils installed. Ready for GCC Stage 1."
    fi
    
    # 2. GCC (Stage 1 - First pass)
    if [ "$PKG_NAME" = "gcc-13.2.0" ]; then
        mkdir -p build && cd build
        # We need symlinks for GCC build
        ln -sfv /usr/bin/ld $LFS/usr/bin/$TARGET-ld
        
        log INFO "Configuring GCC Stage 1..."
        # NOTE: We only build the necessary components (GCC and C/C++ libs)
        ../configure --prefix=/usr --target=$TARGET --with-sysroot=$LFS                      --disable-nls --disable-libssp --disable-libquadmath                      --enable-languages=c,c++
        log INFO "Compiling GCC Stage 1 (using -j1)..."
        make -j1 all-gcc
        log INFO "Installing GCC Stage 1..."
        make install-gcc
        log SUCCESS "GCC Stage 1 installed. Ready for Glibc."
    fi

    # Cleanup
    cd /root/abo-linux
    rm -rf /tmp/$PKG_NAME
}

# --- Main Build Process ---

# 0. Setup FHS
if [ ! -d "$LFS/etc" ]; then
    log INFO "Running mkfhs to create $LFS structure."
    # === التعديل هنا: التأكد من تمرير المتغير LFS ===
    $BUILD_DIR/mkfhs "$LFS"
    # ========================================
fi

# 1. Build Toolchain Stage 1
build_package "binutils-2.40"
build_package "gcc-13.2.0"

log SUCCESS "Abo Linux Cross-Toolchain Bootstrap Complete. Next: Glibc and full GCC."

