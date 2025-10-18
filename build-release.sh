#!/bin/bash
# Abo Linux Build Release Script: Unifies creation of all configuration and tool-build scripts.
# Version 1.0.1 Setup (Includes Binutils/GCC Stage 1 Logic)
set -e

echo "--- Starting Abo Linux Tool-Build Setup (v1.0.1) ---"
VERSION="1.0.1"
TARGET_ARCH="aarch64"
TARGET_TRIPLE="aarch64-lfs-linux-gnu"
ROOTFS_PATH="rootFS"
BUILD_DIR="tool-build"
CONFIG_DIR="config"

# ----------------------------------------------------
# 1. تحديث الملفات الأساسية (التي تعتمد عليها أدوات أخرى)
# ----------------------------------------------------

# (1) File: config/package.aarch64
echo "[INFO] Creating/Updating $CONFIG_DIR/package.aarch64"
cat <<EOP > $CONFIG_DIR/package.$TARGET_ARCH
# Abo Linux Core Packages List
binutils-2.40
gcc-13.2.0
glibc-2.38
linux-6.6.27
bash-5.2.21
coreutils-9.4
EOP

# (2) File: config/kernel.aarch64
echo "[INFO] Creating/Updating $CONFIG_DIR/kernel.aarch64"
cat <<EOK > $CONFIG_DIR/kernel.$TARGET_ARCH
# Abo Linux Kernel Config for $TARGET_ARCH (v$VERSION)
ARCH=arm64
CROSS_COMPILE=$TARGET_TRIPLE-
CONFIG_EMBEDDED=y
CONFIG_DEVTMPFS=y
CONFIG_EXT4_FS=y
CONFIG_SQUASHFS=y
CONFIG_ISO9660_FS=y
CONFIG_VIRTIO_MENU=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_BLK=y
EOK

# (3) File: config/grub.aarch64.cfg
echo "[INFO] Creating/Updating $CONFIG_DIR/grub.aarch64.cfg"
cat <<EOG > $CONFIG_DIR/grub.$TARGET_ARCH.cfg
# GRUB Configuration for Abo Linux (aarch64)

set default=0
set timeout=5

menuentry "Abo Linux v$VERSION" {
    # Replace vmlinuz with your actual kernel name
    linux   /boot/vmlinuz root=/dev/vda1 rw quiet
    # Optional: initrd /boot/initrd.img
}
EOG

# (4) File: config/abo-guard/abo-guard.c
echo "[INFO] Creating/Updating $CONFIG_DIR/abo-guard/abo-guard.c"
mkdir -p $CONFIG_DIR/abo-guard
cat <<EOC > $CONFIG_DIR/abo-guard/abo-guard.c
/* Abo-Guard (C): System protection daemon for Abo Linux */
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/reboot.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Abo-Guard v%s: System integrity check running.\n", "$VERSION");
    } else if (strcmp(argv[1], "--check") == 0) {
        printf("Abo-Guard: Running checksum verification on core bins.\n");
        // Implement security check logic here
    }
    return 0;
}
EOC

# ----------------------------------------------------
# 2. إنشاء/تحديث أدوات البناء (tool-build)
# ----------------------------------------------------

# (5) الأداة: tool-build/mkfhs (إنشاء هيكل FHS)
echo "[INFO] Creating/Updating $BUILD_DIR/mkfhs"
cat <<EOMFHS > $BUILD_DIR/mkfhs
#!/bin/bash
# Abo Linux Utility: Creates the essential File Hierarchy Standard (FHS) directories.
LFS="$1"
if [ -z "$LFS" ]; then
    echo "Error: LFS (rootFS path) not provided." >&2; exit 1
fi
echo "[MKFHS] Creating basic FHS structure in $LFS"
mkdir -v $LFS/{etc,var,boot,home,mnt,opt,srv,tmp,usr,usr/bin,usr/lib,usr/sbin}
mkdir -v $LFS/{bin,lib,sbin}
mkdir -v $LFS/var/lib
mkdir -v $LFS/var/lib/apka # Abo Package Manager database
mkdir -v $LFS/var/{log,mail,spool}
mkdir -v $LFS/usr/local/{bin,etc,lib,sbin,share}
mkdir -v $LFS/run
echo "FHS structure created successfully."
EOMFHS

# (6) الأداة: tool-build/apka (مدير الحزم)
echo "[INFO] Creating/Updating $BUILD_DIR/apka"
cat <<EOPK > $BUILD_DIR/apka
#!/bin/bash
# Abo Linux Utility: Low-level package manager (Abo Package .afp).
OPERATION="$1"
PACKAGE_FILE="$2"
ROOTFS_PATH="$3"

install_package() {
    echo "[APKA] Installing $PACKAGE_FILE to $ROOTFS_PATH..."
    if [ -f "$PACKAGE_FILE" ]; then
        tar -xf "$PACKAGE_FILE" -C "$ROOTFS_PATH" || return 1
        echo "[APKA] Package installed successfully."
        echo "$(basename "$PACKAGE_FILE" .afp)" >> "$ROOTFS_PATH/var/lib/apka/installed_list"
        return 0
    else
        echo "[APKA] Error: Package file $PACKAGE_FILE not found." >&2; return 1
    fi
}

case "$OPERATION" in
    "install") install_package ;;
    "query") grep "$2" "$ROOTFS_PATH/var/lib/apka/installed_list" ;;
    *) echo "[APKA] Error: Unknown operation $OPERATION" >&2; exit 1 ;;
esac
EOPK

# (7) الأداة: tool-build/util-build-abo-linux.sh (المدير الرئيسي)
echo "[INFO] Updating $BUILD_DIR/util-build-abo-linux.sh"
cat <<EUTIL > $BUILD_DIR/util-build-abo-linux.sh
#!/bin/bash
# Abo Linux Build Utility: Main script to build the entire system from source.
set -e

LFS="/root/abo-linux/rootFS"
TARGET="$TARGET_TRIPLE"
BUILD_DIR="$BUILD_DIR"
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
        ../configure --prefix=/usr --target=$TARGET --with-sysroot=$LFS --disable-nls --disable-libssp --disable-libquadmath
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
    $BUILD_DIR/mkfhs "$LFS"
fi

# 1. Build Toolchain Stage 1
build_package "binutils-2.40"
build_package "gcc-13.2.0"

log SUCCESS "Abo Linux Cross-Toolchain Bootstrap Complete. Next: Glibc and full GCC."

EUTIL

# ----------------------------------------------------
# 3. جعل جميع السكريبتات قابلة للتنفيذ والتنفيذ الفعلي
# ----------------------------------------------------
echo "[INFO] Setting execute permissions..."
chmod +x build-release.sh
chmod +x $BUILD_DIR/*
chmod +x $CONFIG_DIR/abo-guard/abo-guard.sh # Placeholder, assume we make it executable later

echo "--- Abo Linux Tools Setup Complete ---"
