#!/usr/bin/env bash
LOG=/tmp/kiosk-x-startup.log
MAX_RETRIES=3
RETRY_DELAY=5

echo "[$(date)] Starting X (attempt 1/$MAX_RETRIES)" >> "$LOG"

for attempt in $(seq 1 $MAX_RETRIES); do
    [ $attempt -gt 1 ] && sleep $RETRY_DELAY
    xinit /home/kiosk/.xinitrc -- /usr/bin/X :0 -s 0 -dpms vt1 2>>"$LOG"
    EXIT_CODE=$?
    [ $EXIT_CODE -eq 0 ] && break
done

exit ${EXIT_CODE:-1}
