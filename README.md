# Jetson Nano 2GB Kiosk

Custom overclocked kernel and optimized kiosk for HomeBox scanner on Jetson Nano 2GB.

## Specs
- **Board:** Jetson Nano 2GB Developer Kit (P3448-0003)
- **Kernel:** 4.9.337-tegra (custom OC build from mrcmunir/jetson_nano_overclock)
- **CPU:** 2.014 GHz (stock: 1.479 GHz) — performance governor
- **Display:** fbdev Xorg (nvidia nvgpu module incompatible with custom GCC 16 build)
- **Browser:** Chromium 112 + SwiftShader software GL
- **Swap:** 1 GB ZRAM (lzo compression) — replaces 4 GB eMMC swapfile

## Key Modifications
- `CONFIG_MODVERSIONS=n` — custom kernel incompatible with stock NVIDIA modules
- `CONFIG_DRM_TEGRA_UDRM=y` — built into kernel, not loadable module
- `/etc/X11/xorg.conf` — uses `Driver "fbdev"` instead of `Driver "nvidia"`
- LightDM masked — kiosk owns display `:0` directly
- ZRAM swap + aggressive sysctl tuning for 2 GB RAM
- 12 Chromium memory-reduction flags

## Results
- CPU: 1.479 → 2.014 GHz (+36%)
- Memory available: 1.3 → 1.4 GB (+100 MB)
- Wasted applets killed: ~200 MB recovered
- Swap: 4 GB eMMC → 1 GB in-RAM ZRAM (much faster)

## Repository Contents
- `PLAN.md` — full optimization plan with 4 phases
- Issues track remaining work (Phase 2-4)

## SSH Access
- `jetson@192.168.1.164` (password: via memory)
