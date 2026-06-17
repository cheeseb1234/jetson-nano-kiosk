#!/usr/bin/env bash
set -u

KIOSK_URL="https://homebox.home.arpa:30022/field/"
KIOSK_USER="kiosk"

export DISPLAY=:0

# Re-apply performance governor (X startup sometimes resets it)
echo performance | sudo -n tee /sys/devices/system/cpu/cpufreq/policy0/scaling_governor > /dev/null 2>&1 || true
echo 2014500 | sudo -n tee /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq > /dev/null 2>&1 || true
export XDG_RUNTIME_DIR="/tmp/runtime-kiosk"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

xset s off || true
xset -dpms || true
xset s noblank || true

until getent hosts homebox.home.arpa >/dev/null 2>&1; do
  sleep 2
done

until curl -k --connect-timeout 3 -Is "$KIOSK_URL" >/dev/null 2>&1; do
  sleep 3
done

# Determine which browser to use
CHROME=chromium-browser
type "$CHROME" >/dev/null 2>&1 || CHROME=chromium
type "$CHROME" >/dev/null 2>&1 || CHROME=google-chrome

# Kill leftover crashpad
pkill -f chrome_crashpad 2>/dev/null || true

while true; do
  if [ -f /tmp/kiosk-switch-to-desktop ]; then
    rm -f /tmp/kiosk-switch-to-desktop
    exit 0
  fi

  "$CHROME" \
    --kiosk \
    --noerrdialogs \
    --disable-session-crashed-bubble \
    --overscroll-history-navigation=0 \
    --user-data-dir=/home/kiosk/.config/chromium-kiosk \
    --max_old_space_size=512 \
    --disable-sync \
    --disable-background-networking \
    --disable-default-apps \
    --disable-component-extensions-with-background-pages \
    --no-crash-upload \
    --disable-breakpad \
    --no-first-run \
    --force-device-scale-factor=1 \
    --renderer-process-limit=1 \
    --disable-ipc-flooding-protection \
    --disable-field-trial-config \
    "$KIOSK_URL"

  sleep 5
done
