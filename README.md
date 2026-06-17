# Jetson Nano 2GB Kiosk

Custom overclocked kernel and optimized kiosk for HomeBox scanner on Jetson Nano 2GB with **full GPU acceleration**.

## Specs
- **Board:** Jetson Nano 2GB Developer Kit (P3448-0003)
- **Kernel:** 4.9.337-tegra (custom OC build from mrcmunir/jetson_nano_overclock)
- **CPU:** 2.014 GHz (stock: 1.479 GHz) — performance governor
- **GPU:** **Fully accelerated!** nvgpu.ko rebuilt from GPLv2 source
- **Display:** Xorg NVIDIA driver — hardware 2D acceleration + GLX
- **Browser:** Chromium 112 — uses NVIDIA GLX hardware rendering
- **Swap:** 1 GB ZRAM (lzo compression) — replaces 4 GB eMMC swapfile

## Key Modifications
- `CONFIG_MODVERSIONS=n` — nvgpu.ko rebuilt from source with matching vermagic
- `CONFIG_DRM_TEGRA_UDRM=y` — built into kernel
- `/etc/X11/xorg.conf` — uses `Driver "nvidia"` (nvidia_drv.so from stock BSP)
- nvgpu.ko rebuilt via `make M=../nvgpu/drivers/gpu/nvgpu modules` with KERNEL_OVERLAYS
- LightDM masked — kiosk owns display `:0` directly
- ZRAM swap + aggressive sysctl tuning for 2 GB RAM
- 12 Chromium memory-reduction flags

## Results

| Metric | Before (SwiftShader) | After (GPU) | Δ |
|--------|---------------------|-------------|---|
| CPU load (1-min) | **3.87** | **0.25** | **-93%** |
| Memory used | **851 MB** | **510 MB** | **-341 MB** |
| Swap usage | 3.0 MB | **0 MB** | Eliminated |
| Xorg rendering | fbdev (software) | NVIDIA (hardware) | ✅ |
| GLX provider | DRI SWRAST | NVIDIA GLX Module 32.7.6 | ✅ |
| GPU devices | None | 8 nvhost-gpu devices | ✅ |
| CPU frequency | 2.014 GHz | 2.014 GHz | Unchanged |

## Performance Summary
- **CPU:** 1.479 → 2.014 GHz (+36%)
- **GPU:** None → Full acceleration with NVIDIA GLX
- **Memory used:** 851 → 510 MB (-40%)
- **CPU load under kiosk:** 3.87 → 0.25 (-93%)
- **Swap:** Eliminated
- **Storage:** eMMC boot, ZRAM 1 GB (lzo) swap

## Flashable Image

A build script for creating a complete SD card image is in the `build/` directory:

```
build/
├── build-image.sh          # Builds a flashable SD card image from L4T BSP
├── kernel/                 # Pre-built kernel artifacts (Image, DTB, nvgpu.ko)
├── overlay/                # Config files applied to the image
└── .github/workflows/      # CI workflow for automated image building
```

To build: `sudo ./build/build-image.sh`

Output: compressed `.img.xz` ready to `dd` to an SD card.

## Repository Contents
- `PLAN.md` — full optimization plan
- `BUILD.md` — OC kernel build guide

## GPU Driver Architecture

Unlike desktop NVIDIA GPUs, the Jetson Nano has no `nvidia.ko`/`nvidia-modeset.ko`. The display is driven by:
- **tegradc** (display controller, built into kernel)
- **nvgpu.ko** (GPU compute, GPL source — rebuilt for custom kernel)
- **nvidia_drv.so** (Xorg DDX, binary, from stock BSP)

The nvgpu kernel module source is at `kernel/nvgpu/drivers/gpu/nvgpu/` in the mrcmunir repo with full gm20b support.

## SSH Access
- `jetson@192.168.1.164` (password: via memory)
