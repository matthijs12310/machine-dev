#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timeout_s="${INPUT_WAIT_TIMEOUT:-120}"
mouse_mode="${BRIDGE_MOUSE:-xtest}"
keyboard_mode="${BRIDGE_KEYBOARD:-xdotool}"
input_permission_watch_seconds="${INPUT_PERMISSION_WATCH_SECONDS:-1800}"

pkill -f "${script_dir}/moonlight-input-bridge.py|/workspace/moonlight-input-bridge.py|./moonlight-input-bridge.py" 2>/dev/null || true

modprobe uinput 2>/dev/null || true
if [ ! -e /dev/uinput ]; then
  mknod /dev/uinput c 10 223 2>/dev/null || true
fi

for n in $(seq 4 16); do
  if grep -q "event$n" /proc/bus/input/devices && [ ! -e "/dev/input/event$n" ]; then
    mknod "/dev/input/event$n" c 13 "$((64+n))" || true
  fi
done
chmod -R a+rw /dev/input /dev/uinput 2>/dev/null || true

(
  for _ in $(seq 1 "$input_permission_watch_seconds"); do
    chmod -R a+rw /dev/input /dev/uinput 2>/dev/null || true
    sleep 2
  done
) >/tmp/machine-dev-input-permissions.log 2>&1 &

echo "Starting input bridge. It will wait up to ${timeout_s}s for Moonlight passthrough devices."
echo "Mode: mouse=${mouse_mode}, keyboard=${keyboard_mode}"
echo "If mouse goes weird, run: BRIDGE_MOUSE=prime ${script_dir}/start-input-bridge.sh"
echo "If keyboard is the only broken thing, run: BRIDGE_MOUSE=0 ${script_dir}/start-input-bridge.sh"
exec env INPUT_WAIT_TIMEOUT="$timeout_s" BRIDGE_MOUSE="$mouse_mode" BRIDGE_KEYBOARD="$keyboard_mode" "${script_dir}/moonlight-input-bridge.py"
