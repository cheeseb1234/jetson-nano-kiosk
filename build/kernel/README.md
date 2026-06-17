# Kernel Build Artifacts
These are pre-built binary files from our custom kernel build.
- `Image` — Custom OC kernel (36 MB)
- `nvgpu.ko` — Rebuilt GPU module (77 MB)
- `tegra210-p3448-0003-p3542-0000.dtb` — Device tree blob

## Building from source

See `BUILD.md` for full cross-compilation instructions. The kernel source is at:
https://github.com/mrcmunir/jetson_nano_overclock

To rebuild these artifacts:
```bash
cd kernel/kernel-4.9
make tegra_defconfig
# Apply OC patches, set MODVERSIONS=n, tegra-udrm=y
make -j$(nproc) zImage dtbs
export KERNEL_OVERLAYS="$(pwd)/../nvgpu $(pwd)/../nvidia"
make M=$(pwd)/../nvgpu/drivers/gpu/nvgpu modules
```
