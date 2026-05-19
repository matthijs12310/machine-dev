#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="${GAMEPAD_FILTER_LOG:-/tmp/machine-dev-gaming/gamepad-filter.log}"

mkdir -p "$(dirname "$log_file")"

modprobe uinput 2>/dev/null || true
if [ ! -e /dev/uinput ]; then
  mknod /dev/uinput c 10 223 2>/dev/null || true
fi

chmod -R a+rw /dev/input /dev/uinput 2>/dev/null || true

pkill -f "${script_dir}/gamepad-filter-bridge.py" 2>/dev/null || true

echo "Starting gamepad filter bridge"
echo "Deadzone: ${GAMEPAD_DEADZONE:-9000}"
echo "Output Hz: ${GAMEPAD_OUTPUT_HZ:-250}"
echo "Smoothing: ${GAMEPAD_SMOOTHING:-0.65}"
echo "Log: ${log_file}"

nohup env \
  GAMEPAD_DEADZONE="${GAMEPAD_DEADZONE:-9000}" \
  GAMEPAD_GRAB="${GAMEPAD_GRAB:-1}" \
  GAMEPAD_WAIT_TIMEOUT="${GAMEPAD_WAIT_TIMEOUT:-120}" \
  GAMEPAD_OUTPUT_HZ="${GAMEPAD_OUTPUT_HZ:-250}" \
  GAMEPAD_SMOOTHING="${GAMEPAD_SMOOTHING:-0.65}" \
  "${script_dir}/gamepad-filter-bridge.py" \
  >"$log_file" 2>&1 &

echo $! >/tmp/machine-dev-gaming/gamepad-filter.pid
sleep 2
tail -40 "$log_file" || true
