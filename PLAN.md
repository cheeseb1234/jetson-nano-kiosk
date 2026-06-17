# Jetson Nano Kiosk: Performance & Memory Optimization Plan

> **For Hermes:** Execute tasks autonomously via delegate_task per workstream. Tasks in each phase should be executed sequentially (next depends on previous). Phases can proceed in parallel where noted.

**Goal:** Maximize kiosk responsiveness and stability on the Jetson Nano 2GB (custom OC kernel, 2.014 GHz, **full NVIDIA GPU acceleration**).

**Current State (June 17, 2026):**
- Kernel: `4.9.337-tegra` (custom build, GCC 16, MODVERSIONS=n, tegra-udrm built-in)
- CPU: 2.014 GHz (performance governor, systemd service enabled)
- GPU: **nvgpu.ko rebuilt from GPLv2 source** — full acceleration
- Display: 2560×1080 **Xorg NVIDIA driver** — HW 2D accel + GLX
- Browser: Chromium 112 — **NVIDIA GLX hardware rendering** (separate GPU process)
- RAM: 2 GB LPDDR4
- Memory used (kiosk idle): **~510 MB** (was 851 MB with SwiftShader)
- CPU load (kiosk idle): **~0.25** (was 3.87 with SwiftShader)
- Storage: eMMC boot, ZRAM 1 GB (lzo) swap

**Key Constraint:** The 2GB Nano has no barrel jack power — micro-USB only (5V/2.5A stock, 5V/3A+ recommended). EMC overclocking increases power draw. Do NOT proceed with EMC OC unless the power supply can handle it.

**Tech Stack:** Linux 4.9, L4T R32.7.6, systemd, Chromium 112, Openbox

---

## Phase 1: Memory Usage Optimization (Highest Priority)

### Task 1: Audit current memory usage

**Objective:** Establish baseline memory consumption of the kiosk at idle and under load.

**Files:**
- Report saved to `/tmp/jetson-memory-audit-*.txt` on the Jetson

**Steps:**

1. SSH in and capture baseline:
   ```bash
   ssh jetson@192.168.1.164 '
   echo "=== MEMORY OVERVIEW ==="
   free -h
   echo ""
   echo "=== TOP PROCESSES BY MEM ==="
   ps aux --sort=-%mem | head -15
   echo ""
   echo "=== CHROMIUM PROCESSES ==="
   ps aux | grep chromium-browser | grep -v grep | awk "{sum+=\$6} END {print \"Chromium total RSS: \" sum/1024 \" MB\"}"
   echo ""
   echo "=== SWAP ==="
   swapon --show
   echo ""
   echo "=== CACHE PRESSURE ==="
   cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Cached|Active|Inactive"
   '
   ```

2. Save results to the plan's reference data.

### Task 2: Create ZRAM swap (compress swap in RAM)

**Objective:** Replace eMMC swap with ZRAM — compresses pages in RAM instead of writing to slow eMMC. On 2 GB RAM, ZRAM can effectively give ~1 GB extra usable memory under compression.

**Files:**
- Modify: `/etc/systemd/system/zram-swap.service` (create)
- Modify: `/etc/default/zram-swap` or equivalent (Ubuntu 18.04 method)

**Ubuntu 18.04 method (no zram-config package — use systemd service):**

```bash
# Create service
sudo tee /etc/systemd/system/zram-swap.service << 'EOF'
[Unit]
Description=ZRAM swap
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '
    modprobe zram
    echo lz4 > /sys/block/zram0/comp_algorithm
    echo 1024M > /sys/block/zram0/disksize
    mkswap /dev/zram0
    swapon -p 100 /dev/zram0
'
ExecStop=/bin/sh -c '
    swapoff /dev/zram0 2>/dev/null || true
    echo 1 > /sys/block/zram0/reset
'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable zram-swap.service
sudo systemctl start zram-swap.service
```

**Verification:**
```bash
zramctl      # Should show /dev/zram0 with lz4 compression, 1024M size
swapon --show # Should show /dev/zram0 with priority 100
free -h      # Available RAM should increase as eMMC swap is replaced
```

### Task 3: Reduce Chromium memory footprint via flags

**Objective:** Tweak Chromium flags to use less RAM while maintaining acceptable kiosk rendering.

**Files:**
- Modify: `/home/kiosk/start-homebox-kiosk.sh` — add flags to the Chromium command line

**Key flags to add:**
```
--max_old_space_size=512          # V8 heap limit (default is ~1.4 GB on 64-bit)
--disable-features=TranslateUI    # Remove translation engine
--disable-sync                    # Disable Chrome sync
--disable-background-networking   # No background jobs
--disable-default-apps            # No bundled apps
--disable-component-extensions-with-background-pages
--disable-ipc-flooding-protection # Less IPC overhead
--no-crash-upload                 # No crash reporting
--disable-breakpad                # No crash handler
--no-first-run                    # Skip first-run
--force-device-scale-factor=1     # No HiDPI scaling overhead
--disable-software-rasterizer     # We use SwiftShader instead
--renderer-process-limit=1        # Single renderer (kiosk only has one tab)
```

**Remove crashpad handler entirely** — on a 2GB system, every MB counts:
```bash
# In start-homebox-kiosk.sh, before launching chrome:
# Kill crashpad if it's running (it forks and sits around)
pkill -f chrome_crashpad 2>/dev/null || true
```

**Verification:**
```bash
ps aux | grep chromium-browser | grep -v grep | wc -l   # Fewer processes
free -h                                                    # More free RAM
```

### Task 4: Reduce Openbox/desktop bloat

**Objective:** The kiosk has unnecessary desktop services running (nm-applet, gvfsd, deja-dup, system-config-printer-applet). Strip these.

**Files:**
- Modify: `/home/kiosk/.config/openbox/autostart` (or `/etc/xdg/openbox/autostart`)
- Check: `/home/kiosk/.config/autostart/` for desktop files

**Approach:**
1. Check what's auto-starting with openbox:
   ```bash
   ls -la /home/kiosk/.config/autostart/
   cat /etc/xdg/openbox/autostart
   ```

2. Remove/disable unnecessary services:
   - `nm-applet` — network manager applet (not needed — network is already configured)
   - `deja-dup-monitor` — backup monitor (not needed on kiosk)
   - `system-config-printer-applet` — printer applet (print-bridge.py handles printing)
   - `gvfsd` — GNOME virtual filesystem (probably needed for Chromium file access)

3. Create a minimal openbox autostart:
   ```bash
   mkdir -p /home/kiosk/.config/openbox
   cat > /home/kiosk/.config/openbox/autostart << 'EOF'
   # Minimal kiosk autostart
   # No nm-applet, no deja-dup, no printer-applet
   # Chromium is launched by start-homebox-kiosk.sh
   EOF
   ```

**Verification:** Reboot and check `ps aux | wc -l` — should drop significantly.

### Task 5: Trim system services and enable early OOM

**Objective:** Reduce background services that consume RAM, and enable kernel OOM killing earlier to prevent the system from freezing under memory pressure.

**Files:**
- Modify: `/etc/sysctl.d/99-jetson-kiosk.conf` (create)

**Systemd services to disable (not needed for kiosk):**
```bash
sudo systemctl disable whoopsie          # Error reporting
sudo systemctl disable apport            # Crash reporting  
sudo systemctl disable cups-browsed      # Printer browsing (print-bridge handles this)
sudo systemctl disable bluetooth         # No BT needed
sudo systemctl disable ModemManager      # No cellular
sudo systemctl disable avahi-daemon      # .local resolution (keep if print-bridge needs it)
```

**OOM tuning:**
```ini
# /etc/sysctl.d/99-jetson-kiosk.conf
vm.vfs_cache_pressure=200           # Reclaim dentry/inode cache more aggressively
vm.swappiness=60                    # Swap earlier (ZRAM makes this less painful)
vm.dirty_ratio=5                    # Less dirty page cache
vm.dirty_background_ratio=2         # Write back dirty pages sooner
vm.min_free_kbytes=32768            # Keep 32 MB free for emergency
vm.oom_kill_allocating_task=1       # Kill the task that triggered OOM (faster recovery)
```

**Verification:**
```bash
sysctl -a | grep -E "vfs_cache_pressure|swappiness|dirty_ratio|min_free_kbytes|oom_kill"
free -h          # Compare before/after
```

### Task 6: Verify kiosk memory stability under load

**Objective:** Confirm the optimizations actually help under real kiosk use.

**Steps:**
1. Reboot the Jetson
2. Wait for kiosk to fully load (Chromium showing HomeBox)
3. Run memory audit:
   ```bash
   free -h
   ps aux --sort=-%mem | head -10
   zramctl
   swapon --show
   ```
4. Leave running for 30 minutes with the HomeBox scanner page open
5. Re-check memory — if ZRAM compression ratio is good (>2:1), it's working
6. Check `/var/log/syslog` for any OOM killer activity

---

## Phase 2: Chromium Performance Tuning (2.0 GHz Software Rendering)

### Task 7: Benchmark current Chromium performance

**Objective:** Establish baseline FPS/page-load-time for the kiosk URL.

**Approach:**
```bash
# Use Chromium's built-in tracing
# Open about:tracing or chrome://tracing in the kiosk
# Or use the rendering stats from chrome://gpu

# Alternative: measure page load time via curl
time curl -k https://homebox.home.arpa:30022/field/ -o /dev/null 2>&1
```

### Task 8: Tune SwiftShader and GPU emulation flags

**Objective:** Find the optimal `--use-gl` and rendering flags for this specific workload.

**Experiments to run** (one reboot per variant, measure with `chrome://gpu`):
1. `--disable-gpu` (pure CPU rendering, no GL at all) — might be fastest for simple pages
2. `--use-gl=angle --use-angle=swiftshader-webgl` (current — software GL)
3. `--enable-unsafe-swiftshader` (alternative software GL path)
4. `--in-process-gpu` (run GPU in the browser process, saves ~30 MB)
5. `--disable-gpu-compositing` (CPU compositing, might be faster)

**Note:** The current renderers already use `--disable-gpu-compositing` and the GPU process uses `--use-gl=angle --use-angle=swiftshader-webgl`. Test `--in-process-gpu` for memory savings.

### Task 9: HomeBox page-specific optimizations

**Objective:** If the kiosk page is too heavy, suggest front-end tweaks to Corey.

**Check:**
```bash
# Check page weight from SSH
curl -k https://homebox.home.arpa:30022/field/ 2>/dev/null | wc -c
echo ""
# Check number of requests
curl -k -s -o /dev/null -w "Total time: %{time_total}s\n" https://homebox.home.arpa:30022/field/
```

---

## Phase 3: EMC (RAM) Overclock — 1600 → 1866 MHz (Needs Kernel Rebuild)

### Task 10: Research EMC overclock feasibility

**Objective:** Understand whether EMC 1866 MHz is safe and achievable on the 2GB Nano.

**Context:** The P3448-0003 module uses LPDDR4 — single-channel on the 2GB variant. EMC frequency is controlled by the kernel's EMC scaling driver (`drivers/devfreq/tegra-devfreq.c`). The mrcmunir repo may already have EMC tables for higher frequencies.

**Steps:**
1. Check current EMC frequency:
   ```bash
   cat /sys/kernel/debug/emc/emc_clk/cur 2>/dev/null || \
   cat /sys/class/devfreq/emc/cur_freq 2>/dev/null
   ```
2. Check available EMC frequencies:
   ```bash
   cat /sys/class/devfreq/emc/available_frequencies 2>/dev/null
   ```
3. Read the mrcmunir reference doc for EMC OC details
4. **Decision gate:** Only proceed if:
   - Power supply is verified as 5V/3A+
   - CPU OC is stable for >24 hours
   - PMIC temps stay under 60°C under CPU-only OC load

### Task 11: Patch EMC frequency table and rebuild kernel

**Objective:** Add 1866 MHz (and optionally 2133 MHz) to the EMC DVFS table.

**Files:**
- Modify: `kernel/kernel-4.9/drivers/devfreq/tegra-devfreq.c` or equivalent
- Modify: DTS cpufreq node (already has EMC scaling entries from mrcmunir patches)

**Only attempt if Task 10 passes the safety gate.**

### Task 12: Deploy and stress-test EMC OC

**Objective:** Verify stability with memory-intensive workloads.

**Steps:**
1. Build kernel with EMC OC
2. Deploy to Jetson
3. Test with:
   ```bash
   # Memory bandwidth test
   dd if=/dev/zero of=/dev/null bs=1M count=1000
   # Or use sysbench
   sysbench memory --memory-block-size=1M --memory-total-size=512M run
   ```
4. Monitor PMIC temp: `cat /sys/class/thermal/thermal_zone*/temp`
5. Run the kiosk for 1+ hour checking for crashes

---

## Phase 4: GPU Overclock — 921 → 1000 MHz (Runtime sysfs, No Rebuild Needed)

### Task 13: Benchmark current GPU performance

**Objective:** Understand whether GPU OC would help the SwiftShader-rendered kiosk.

**Note:** Since Xorg uses fbdev (not the nvidia driver), the GPU is only used by Chromium's SwiftShader (software GL on CPU). GPU frequency may not affect kiosk performance at all. Measure before bothering.

### Task 14: Apply GPU overclock via sysfs

**Objective:** Increase GPU max frequency at runtime.

**Approach:**
```bash
# Check current GPU frequency
cat /sys/devices/57000000.gpu/devfreq/57000000.gpu/cur_freq
cat /sys/devices/57000000.gpu/devfreq/57000000.gpu/available_frequencies

# Set max to 1.0 GHz
echo 1000000000 | sudo tee /sys/devices/57000000.gpu/devfreq/57000000.gpu/max_freq
```

**Persistence:** Add to the existing `jetson-oc-perf.service` or create a new `jetson-gpu-oc.service`.

### Task 15: Verify GPU OC stability

**Objective:** Ensure no crashes under GPU load.

**Steps:**
1. `cat /sys/devices/57000000.gpu/devfreq/57000000.gpu/cur_freq` — should show 1.0 GHz
2. Run Chromium with a WebGL benchmark page
3. Monitor GPU temp

---

## Risks & Open Questions

| Risk | Impact | Mitigation |
|------|--------|-----------|
| ZRAM uses CPU for compression | Slight perf hit on 2 GHz A57 cores | Use `lz4` (fastest algorithm) |
| EMC OC could corrupt filesystem | Data loss | Always test with read-only fs first, keep backup kernel |
| Power supply inadequate for OC | Random crashes, brownouts | Check PMIC temp, keep stock kernel as fallback |
| Chromium SwiftShader too slow even at 2 GHz | Kiosk unusable | Test `--disable-gpu` mode (pure CPU rendering may be faster) |
| Memory optimizations break kiosk functionality | Printer/scanner stops working | Test each change individually, keep rollback plan |
