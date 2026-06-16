# OC Kernel Build Guide

How to cross-compile the overclocked kernel for Jetson Nano 2GB (L4T R32.7.6) on an x86_64 Arch Linux host.

## Prerequisites

```bash
# Cross-compiler for ARM64 (aarch64)
sudo pacman -S aarch64-linux-gnu-gcc
```

## Clone the Kernel Source

```bash
git clone https://github.com/mrcmunir/jetson_nano_overclock.git
cd jetson_nano_overclock/kernel/kernel-4.9
```

## Fix Incomplete Source Tree

The mrcmunir fork omits a few Kconfig files and Makefile entries. Create stubs:

```bash
# 1. Missing tegra firmware Kconfig
mkdir -p drivers/firmware/tegra
echo "# stub" > drivers/firmware/tegra/Kconfig

# 2. Missing eqos ethernet Kconfig — comment out the reference
sed -i 's|source "drivers/net/ethernet/nvidia/eqos/Kconfig"|# source "drivers/net/ethernet/nvidia/eqos/Kconfig"|' \
  drivers/net/ethernet/nvidia/Kconfig

# 3. Missing tegra-udrm Makefile entry
echo "obj-\$(CONFIG_DRM_TEGRA_UDRM) += tegra_udrm/" >> drivers/gpu/drm/Makefile
```

## Configure

```bash
export CROSS_COMPILE=/usr/bin/aarch64-linux-gnu-
export ARCH=arm64

# Stock L4T defconfig for T210
make tegra_defconfig

# Must match the stock kernel's module directory (/lib/modules/4.9.337-tegra/)
sed -i 's/^CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-tegra"/' .config

# Disable module versioning — the stock nvidia .ko files were compiled with GCC 7.5
# and our GCC 16 build produces incompatible CRCs. Disabling MODVERSIONS lets
# the stock tegra-udrm load, but we build it into the kernel anyway.
sed -i 's/CONFIG_MODVERSIONS=y/# CONFIG_MODVERSIONS is not set/' .config

# Build tegra-udrm into the kernel (not as loadable module)
sed -i 's/CONFIG_DRM_TEGRA_UDRM=m/CONFIG_DRM_TEGRA_UDRM=y/' .config
```

## Build

GCC 16.1 is much stricter than the GCC 7.5 used for the original L4T kernel. Suppress -Werror:

```bash
KCFLAGS="-Wno-error"
KCFLAGS="$KCFLAGS -Wno-error=header-guard"
KCFLAGS="$KCFLAGS -Wno-error=address"
KCFLAGS="$KCFLAGS -Wno-error=stringop-overflow"
KCFLAGS="$KCFLAGS -Wno-error=sizeof-pointer-memaccess"
KCFLAGS="$KCFLAGS -Wno-error=format-truncation"
KCFLAGS="$KCFLAGS -Wno-error=maybe-uninitialized"

# Kernel image
make -j$(nproc) zImage KCFLAGS="$KCFLAGS"

# Device tree blobs (2GB Nano uses tegra210-p3448-0003-p3542-0000.dtb)
make -j$(nproc) dtbs KCFLAGS="$KCFLAGS"
```

Output:
- `arch/arm64/boot/Image` — kernel (~37 MB)
- `arch/arm64/boot/dts/tegra210-p3448-0003-p3542-0000.dtb` — device tree (~224 KB)

## Deploy to Jetson

```bash
# Copy artifacts to Jetson
scp -i ~/.ssh/id_ed25519 arch/arm64/boot/Image \
  jetson@192.168.1.164:/tmp/Image-oc
scp -i ~/.ssh/id_ed25519 arch/arm64/boot/dts/tegra210-p3448-0003-p3542-0000.dtb \
  jetson@192.168.1.164:/tmp/tegra210-p3448-0003-p3542-0000-oc.dtb

# On the Jetson (password for sudo: 1525):
# Backup stock kernel, install OC kernel
echo "1525" | sudo -S cp /boot/Image /boot/Image.backup.stock
echo "1525" | sudo -S cp /boot/tegra210-p3448-0003-p3542-0000.dtb /boot/tegra210-p3448-0003-p3542-0000.dtb.backup.stock
echo "1525" | sudo -S cp /tmp/Image-oc /boot/Image
echo "1525" | sudo -S cp /tmp/tegra210-p3448-0003-p3542-0000-oc.dtb /boot/tegra210-p3448-0003-p3542-0000.dtb
echo "1525" | sudo -S chmod 644 /boot/Image /boot/tegra210-p3448-0003-p3542-0000.dtb
```

## Post-Deploy Configuration

### Switch Xorg to fbdev (required — nvidia driver won't work)

```bash
cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier  "Tegra0"
    Driver      "fbdev"
    Option      "AllowEmptyInitialConfiguration" "true"
EndSection
EOF
```

### Mask LightDM (prevents conflict for display :0)

```bash
sudo systemctl mask lightdm
```

### Create Performance Governor Service

```ini
# /etc/systemd/system/jetson-oc-perf.service
[Unit]
Description=Set Jetson overclock governor to performance
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor && echo 2014500 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq'

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable jetson-oc-perf.service
sudo systemctl start jetson-oc-perf.service
```

### Add extlinux backup boot entry

Already present in `/boot/extlinux/extlinux.conf` from the early deployment:

```
LABEL backup
      MENU LABEL backup kernel (stock)
      LINUX /boot/Image.backup.stock
      INITRD /boot/initrd
      APPEND ${cbootargs} quiet root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 ...
```

## Verify

```bash
uname -r                                    # → 4.9.337-tegra
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq  # → 2014500 (2.014 GHz)
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor   # → performance
```

## Troubleshooting

### "nvidia module not found" / "no screens found"
The NVIDIA nvgpu.ko module is compiled for the stock L4T kernel (GCC 7.5). It cannot
load on a GCC 16 custom kernel. **This is expected.** Switch Xorg to fbdev as above.

### "Server is already active for display 0"
LightDM is running and owns :0. Mask LightDM: `systemctl mask lightdm`

### "Exec format error" on module load
Module vermagic doesn't match kernel. Ensure `CONFIG_MODVERSIONS=n` in .config.
If the module was built with modversions and your kernel doesn't have it, the
module binary format is fundamentally incompatible.

### "tegra_udrm: version magic ... should be ..."
The stock tegra-udrm.ko module has `modversions` in its vermagic. Our kernel
doesn't. **Fix:** compile tegra-udrm into the kernel (CONFIG_DRM_TEGRA_UDRM=y)
instead of loading it as a module. The built-in version won't check vermagic.

### CPU stuck at 1479 MHz after boot
Check governor: `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`.
If `schedutil`, the performance service didn't run. Check:
`systemctl status jetson-oc-perf.service`
