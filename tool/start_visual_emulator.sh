#!/usr/bin/env bash
set -euo pipefail
device=emulator-5554
log="$RUNNER_TEMP/moneytrack-emulator.log"
emulator="$ANDROID_HOME/emulator/emulator"
adb="$ANDROID_HOME/platform-tools/adb"
"$emulator" -version
"$emulator" -accel-check
"$adb" start-server

# The automated-test image has fewer background services. Software rendering keeps
# this UI walkthrough independent of the runner's graphics hardware.
nohup "$emulator" -avd moneytrack -port 5554 -no-snapshot -no-window -noaudio \
  -no-boot-anim -no-metrics -gpu swiftshader -feature -Vulkan -accel on \
  -camera-back none -memory 2048 -cores 2 >"$log" 2>&1 </dev/null &
emulator_pid=$!
deadline=$((SECONDS + 600))
while (( SECONDS < deadline )); do
  if [[ "$(timeout 4 "$adb" -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    "$adb" -s "$device" shell input keyevent 82
    "$adb" -s "$device" shell wm size 780x1560
    "$adb" -s "$device" shell wm density 320
    for setting in window_animation_scale transition_animation_scale animator_duration_scale; do
      "$adb" -s "$device" shell settings put global "$setting" 0
    done
    exit 0
  fi
  kill -0 "$emulator_pid" 2>/dev/null || break
  sleep 3
done

# Limit output to the disposable emulator's boot state and errors.
"$adb" devices -l
timeout 8 "$adb" -s "$device" shell getprop init.svc.bootanim || true
timeout 8 "$adb" -s "$device" logcat -b crash -d -t 25 || true
tail -65 "$log"
df -h "$RUNNER_TEMP"
exit 1
