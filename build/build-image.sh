#!/usr/bin/env bash
# jetson-nano-kiosk Image Builder
# Builds a flashable SD card image for Jetson Nano 2GB with custom OC kernel + GPU
#
# Usage: ./build-image.sh [--output-dir ./output] [--l4t-dir ./l4t]
#
# Prerequisites:
# - ~8GB free disk space for L4T BSP downloads
# - wget, unzip, sha1sum, sudo
# - Run on x86_64 Linux with binutils for aarch64

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Config ---
L4T_VERSION="32.7.6"
L4T_BSP_URL="https://developer.nvidia.com/downloads/embedded/l4t/r32_release_v7.6/t210ref_release_aarch64/tegra210_linux_r32.7.6_aarch64.tbz2"
L4T_ROOTFS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r32_release_v7.6/t210ref_release_aarch64/tegra_linux_sample-root-filesystem_r32.7.6_aarch64.tbz2"
OUTPUT_DIR="${1:-$SCRIPT_DIR/output}"
L4T_DIR="${2:-$SCRIPT_DIR/l4t}"
IMAGE_NAME="jetson-nano-kiosk-r32.7.6.img"

echo "=== Jetson Nano Kiosk Image Builder ==="
echo "L4T:     $L4T_VERSION"
echo "Output:  $OUTPUT_DIR"
echo "L4T dir: $L4T_DIR"

mkdir -p "$OUTPUT_DIR" "$L4T_DIR"

# --- Step 1: Download L4T BSP ---
echo ""
echo "=== Step 1/7: Downloading L4T BSP ==="
cd "$L4T_DIR"
if [ ! -f "tegra210_linux_r${L4T_VERSION}_aarch64.tbz2" ]; then
    wget -c "$L4T_BSP_URL" -O "tegra210_linux_r${L4T_VERSION}_aarch64.tbz2"
fi
if [ ! -f "tegra_linux_sample-root-filesystem_r${L4T_VERSION}_aarch64.tbz2" ]; then
    wget -c "$L4T_ROOTFS_URL" -O "tegra_linux_sample-root-filesystem_r${L4T_VERSION}_aarch64.tbz2"
fi

# --- Step 2: Extract BSP ---
echo "=== Step 2/7: Extracting BSP ==="
BSP_DIR="$L4T_DIR/tegra210_linux_r${L4T_VERSION}"
if [ ! -d "$BSP_DIR" ]; then
    tar -xf "tegra210_linux_r${L4T_VERSION}_aarch64.tbz2"
fi

ROOTFS_DIR="$L4T_DIR/rootfs"
if [ ! -d "$ROOTFS_DIR" ]; then
    mkdir -p "$ROOTFS_DIR"
    echo "Extracting rootfs (this may take a few minutes)..."
    sudo tar -xf "tegra_linux_sample-root-filesystem_r${L4T_VERSION}_aarch64.tbz2" -C "$ROOTFS_DIR"
fi

# --- Step 3: Apply custom kernel ---
echo "=== Step 3/7: Applying custom OC kernel ==="
sudo cp "$REPO_ROOT/build/kernel/Image" "$BSP_DIR/kernel/Image"
sudo cp "$REPO_ROOT/build/kernel/tegra210-p3448-0003-p3542-0000.dtb" "$BSP_DIR/kernel/dtb/"
echo "  Custom kernel: $(stat --format=%s "$REPO_ROOT/build/kernel/Image" 2>/dev/null || echo "?") bytes"

# --- Step 4: Apply config overlay ---
echo "=== Step 4/7: Applying config overlay ==="
OVERLAY_SRC="$REPO_ROOT/build/overlay"
OVERLAY_DST="$ROOTFS_DIR"

# Xorg
sudo mkdir -p "$OVERLAY_DST/etc/X11"
sudo cp "$OVERLAY_SRC/etc/X11/xorg.conf" "$OVERLAY_DST/etc/X11/"

# systemd services
for svc in "$OVERLAY_SRC"/etc/systemd/system/*.service; do
    [ -f "$svc" ] && sudo cp "$svc" "$OVERLAY_DST/etc/systemd/system/"
done

# sysctl
sudo mkdir -p "$OVERLAY_DST/etc/sysctl.d"
sudo cp "$OVERLAY_SRC/etc/sysctl.d/"*.conf "$OVERLAY_DST/etc/sysctl.d/"

# modules-load
sudo mkdir -p "$OVERLAY_DST/etc/modules-load.d"
sudo cp "$OVERLAY_SRC/etc/modules-load.d/"*.conf "$OVERLAY_DST/etc/modules-load.d/"

# Chromium flags
sudo mkdir -p "$OVERLAY_DST/etc/chromium-browser"
[ -f "$OVERLAY_SRC/etc/chromium-browser/default" ] && \
    sudo cp "$OVERLAY_SRC/etc/chromium-browser/default" "$OVERLAY_DST/etc/chromium-browser/"

# Kiosk startup
sudo mkdir -p "$OVERLAY_DST/home/kiosk"
sudo cp "$OVERLAY_SRC/home/kiosk/"* "$OVERLAY_DST/home/kiosk/" 2>/dev/null || true
sudo cp "$OVERLAY_SRC/home/kiosk/.config/openbox/"* "$OVERLAY_DST/home/kiosk/.config/openbox/" 2>/dev/null || true

# Sudoers
sudo cp "$OVERLAY_SRC/etc/sudoers.d/"* "$OVERLAY_DST/etc/sudoers.d/" 2>/dev/null || true

# nvgpu module
sudo mkdir -p "$OVERLAY_DST/lib/modules/4.9.337-tegra/kernel/drivers/gpu/nvgpu"
sudo cp "$REPO_ROOT/build/kernel/nvgpu.ko" "$OVERLAY_DST/lib/modules/4.9.337-tegra/kernel/drivers/gpu/nvgpu/"

# --- Step 5: Apply nvpmodel for MAXN ---
echo "=== Step 5/7: Setting MAXN power mode ==="
sudo mkdir -p "$OVERLAY_DST/etc/nvpmodel"
# Ensure MAXN mode is default
echo "NVPMODEL_DEFAULT=0" | sudo tee "$OVERLAY_DST/etc/nvpmodel/nvpmodel.conf" > /dev/null

# --- Step 6: Create flashable image ---
echo "=== Step 6/7: Generating flashable image ==="
cd "$BSP_DIR"
sudo ./flash.sh -r -k mmcblk0p1 \
    --no-flash \
    --image "$OUTPUT_DIR/$IMAGE_NAME" \
    jetson-nano-2gb-devkit mmcblk0p1 2>&1 | tail -5

echo ""
echo "=== Step 7/7: Compressing ==="
cd "$OUTPUT_DIR"
xz -T0 -9 "$IMAGE_NAME"
echo "Done! Image: $OUTPUT_DIR/$IMAGE_NAME.xz"

echo ""
echo "=== Flashing Instructions ==="
echo "1. Write to SD card:"
echo "   xzcat $OUTPUT_DIR/$IMAGE_NAME.xz | sudo dd of=/dev/sdX bs=4M status=progress"
echo ""
echo "2. Insert SD card into Jetson Nano 2GB, connect HDMI + power"
echo "3. First boot takes ~2 minutes to resize rootfs"
echo "4. Kiosk starts automatically — URL: https://homebox.home.arpa:30022/field/"
