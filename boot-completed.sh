#!/system/bin/sh
MODDIR="${0%/*}"
SVC="secure_element_hal_service"
BIN="android.hardware.secure_element@1.0-service"
STATE_FILE="$MODDIR/enabled"
LOG_FILE="$MODDIR/watchdog.log"

sleep 20

CUR_PID=$(pidof "$BIN")
CUR_STATE=$(getprop "init.svc.$SVC")

if [ -f "$STATE_FILE" ] && [ -n "$CUR_PID" ] && [ "$CUR_STATE" = "running" ]; then
    echo "Service already verified and running (PID: $CUR_PID) at $(date)" > "$LOG_FILE"
    exit 0
fi

rm -f "$STATE_FILE"
logcat -b crash -c 2>/dev/null

if [ "$CUR_STATE" != "running" ]; then
    setprop ctl.start "$SVC"
    sleep 2
fi

ORIG_PID=$(pidof "$BIN")
SVC_STATE=$(getprop "init.svc.$SVC")

if [ -z "$ORIG_PID" ] || [ "$SVC_STATE" != "running" ]; then
    setprop ctl.stop "$SVC"
    ABORT_MSG=$(logcat -b crash -d 2>/dev/null | grep -m1 "Abort message:" | sed 's/.*Abort message: //')
    echo "Service crashed immediately at $(date) (state=${SVC_STATE:-stopped}) ${ABORT_MSG}" > "$LOG_FILE"
    echo "Disabled $SVC to prevent background crash loops." >> "$LOG_FILE"
    exit 1
fi

CRASHED=0
ELAPSED=0
DURATION=120

echo "Monitoring PID $ORIG_PID for 120s at $(date)" > "$LOG_FILE"

while [ "$ELAPSED" -lt "$DURATION" ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    CUR_PID=$(pidof "$BIN")
    CUR_STATE=$(getprop "init.svc.$SVC")

    if [ -z "$CUR_PID" ] || [ "$CUR_STATE" != "running" ] || [ "$CUR_PID" != "$ORIG_PID" ]; then
        CRASHED=1
        ABORT_MSG=$(logcat -b crash -d 2>/dev/null | grep -m1 "Abort message:" | sed 's/.*Abort message: //')
        echo "Service crashed at ${ELAPSED}s (old_pid=$ORIG_PID, new_pid=${CUR_PID:-none}) ${ABORT_MSG}" >> "$LOG_FILE"
        break
    fi
done

if [ "$CRASHED" -eq 1 ]; then
    setprop ctl.stop "$SVC"
    echo "Disabled $SVC automatically at $(date)" >> "$LOG_FILE"
    exit 1
else
    touch "$STATE_FILE"
    echo "Stable for 120s. Kept $SVC enabled at $(date)" >> "$LOG_FILE"
    exit 0
fi