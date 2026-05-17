#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DISPLAY="${DISPLAY:-:99}"
export GAME_WIDTH="${GAME_WIDTH:-1920}"
export GAME_HEIGHT="${GAME_HEIGHT:-1080}"
export GAME_DEPTH="${GAME_DEPTH:-24}"
export STEAM_USER="${STEAM_USER:-runner}"
export STEAM_RUNTIME="${STEAM_RUNTIME:-1}"
export STEAM_LD_LIBRARY_PATH="${STEAM_LD_LIBRARY_PATH:-/usr/lib32:/usr/lib/x86_64-linux-gnu}"
export STEAM_ARGS="${STEAM_ARGS:--cef-disable-gpu -cef-disable-gpu-compositing -cef-disable-dev-shm-usage -no-cef-sandbox}"

START_SUNSHINE="${START_SUNSHINE:-1}"
START_INPUT="${START_INPUT:-1}"
START_STEAM="${START_STEAM:-1}"
VERIFY_GPU="${VERIFY_GPU:-1}"
START_STEAM_ANYWAY="${START_STEAM_ANYWAY:-0}"
WAIT_FOR_MOONLIGHT="${WAIT_FOR_MOONLIGHT:-0}"
LOG_DIR="${LOG_DIR:-/tmp/machine-dev-gaming}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
  fi
}

tailscale_ip() {
  tailscale ip -4 2>/dev/null | head -1 && return 0
  tailscale --socket=/run/tailscale/tailscaled.sock ip -4 2>/dev/null | head -1 && return 0
  tailscale --socket=/tmp/tailscaled.sock ip -4 2>/dev/null | head -1 && return 0
  true
}

wait_for_xorg() {
  for _ in $(seq 1 90); do
    if DISPLAY="$DISPLAY" xdpyinfo >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Xorg did not become ready on ${DISPLAY}"
  return 1
}

wait_for_sunshine() {
  for _ in $(seq 1 90); do
    if pgrep -x sunshine >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Sunshine did not start"
  return 1
}

wait_for_passthrough_devices() {
  for _ in $(seq 1 180); do
    if grep -q 'Keyboard passthrough' /proc/bus/input/devices 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "Moonlight passthrough devices did not appear yet"
  return 1
}

verify_gpu_stack() {
  local failed=0

  echo "Checking NVIDIA OpenGL/Vulkan before Steam"

  if ! DISPLAY="$DISPLAY" glxinfo -B >"${LOG_DIR}/glx-root.log" 2>&1; then
    echo "Root GLX check failed. See ${LOG_DIR}/glx-root.log"
    failed=1
  elif ! grep -q 'OpenGL vendor string: NVIDIA Corporation' "${LOG_DIR}/glx-root.log"; then
    echo "Root GLX is not using NVIDIA. See ${LOG_DIR}/glx-root.log"
    failed=1
  fi

  if id "$STEAM_USER" >/dev/null 2>&1; then
    if ! runuser -u "$STEAM_USER" -- env DISPLAY="$DISPLAY" glxinfo -B >"${LOG_DIR}/glx-${STEAM_USER}.log" 2>&1; then
      echo "${STEAM_USER} GLX check failed. See ${LOG_DIR}/glx-${STEAM_USER}.log"
      failed=1
    elif ! grep -q 'OpenGL vendor string: NVIDIA Corporation' "${LOG_DIR}/glx-${STEAM_USER}.log"; then
      echo "${STEAM_USER} GLX is not using NVIDIA. See ${LOG_DIR}/glx-${STEAM_USER}.log"
      failed=1
    fi
  fi

  if command -v vulkaninfo >/dev/null 2>&1; then
    if ! env -u LD_LIBRARY_PATH VK_LOADER_LAYERS_DISABLE='*' vulkaninfo --summary >"${LOG_DIR}/vulkan.log" 2>&1; then
      echo "Vulkan check failed. See ${LOG_DIR}/vulkan.log"
      failed=1
    elif ! grep -Eiq 'deviceName|GPU' "${LOG_DIR}/vulkan.log"; then
      echo "Vulkan did not report a GPU. See ${LOG_DIR}/vulkan.log"
      failed=1
    fi
  else
    echo "vulkaninfo is not installed, skipping Vulkan check"
  fi

  if [ "$failed" -ne 0 ]; then
    echo "Skipping Steam because the GPU stack is not clean."
    echo "Override only if you really mean it: START_STEAM_ANYWAY=1 $0"
    return 1
  fi

  echo "GPU checks passed."
  return 0
}

prepare_common() {
  mkdir -p "$LOG_DIR" /dev/shm "/tmp/runtime-${STEAM_USER}"
  chmod 1777 /tmp /dev/shm || true
  if id "$STEAM_USER" >/dev/null 2>&1; then
    chown "$STEAM_USER:$STEAM_USER" "/tmp/runtime-${STEAM_USER}"
  fi
  chmod 700 "/tmp/runtime-${STEAM_USER}" || true
  chmod -R a+rw /dev/input /dev/uinput /dev/dri /dev/nvidia* 2>/dev/null || true
}

start_sunshine_stack() {
  echo "Starting Sunshine/Xorg stack on ${DISPLAY} (${GAME_WIDTH}x${GAME_HEIGHT})"
  pkill -f "${script_dir}/setup-machine-dev-sunshine.sh" 2>/dev/null || true
  nohup env \
    DISPLAY="$DISPLAY" \
    GAME_WIDTH="$GAME_WIDTH" \
    GAME_HEIGHT="$GAME_HEIGHT" \
    GAME_DEPTH="$GAME_DEPTH" \
    LOG_DIR=/tmp/machine-dev-sunshine \
    "${script_dir}/setup-machine-dev-sunshine.sh" \
    >"${LOG_DIR}/sunshine-stack.log" 2>&1 &
  echo $! >"${LOG_DIR}/sunshine-stack.pid"
  wait_for_xorg
  wait_for_sunshine
}

start_input_bridge() {
  echo "Starting Moonlight input bridge"
  nohup env \
    DISPLAY="$DISPLAY" \
    INPUT_WAIT_TIMEOUT="${INPUT_WAIT_TIMEOUT:-600}" \
    BRIDGE_MOUSE="${BRIDGE_MOUSE:-xtest}" \
    BRIDGE_KEYBOARD="${BRIDGE_KEYBOARD:-xdotool}" \
    "${script_dir}/start-input-bridge.sh" \
    >"${LOG_DIR}/input-bridge.log" 2>&1 &
  echo $! >"${LOG_DIR}/input-bridge.pid"
}

start_steam() {
  echo "Starting Steam"
  DISPLAY="$DISPLAY" xhost "+SI:localuser:${STEAM_USER}" >/dev/null 2>&1 || true
  pkill -u "$STEAM_USER" -f 'steam|steamwebhelper|srt-logger|zenity' 2>/dev/null || true
  rm -f /dev/shm/Steam* /dev/shm/steam* /dev/shm/.org.chromium.* /tmp/.org.chromium.* 2>/dev/null || true
  nohup env \
    DISPLAY="$DISPLAY" \
    STEAM_USER="$STEAM_USER" \
    STEAM_RUNTIME="$STEAM_RUNTIME" \
    STEAM_LD_LIBRARY_PATH="$STEAM_LD_LIBRARY_PATH" \
    STEAM_ARGS="$STEAM_ARGS" \
    "${script_dir}/start-steam.sh" \
    >"${LOG_DIR}/steam.log" 2>&1 &
  echo $! >"${LOG_DIR}/steam.pid"
}

print_status() {
  tsip="$(tailscale_ip | tr -d '[:space:]')"
  echo
  echo "Gaming stack started."
  echo "Logs:"
  echo "  Sunshine: ${LOG_DIR}/sunshine-stack.log"
  echo "  Input:    ${LOG_DIR}/input-bridge.log"
  echo "  Steam:    ${LOG_DIR}/steam.log"
  echo
  echo "Useful commands:"
  echo "  tail -f ${LOG_DIR}/sunshine-stack.log"
  echo "  tail -f ${LOG_DIR}/input-bridge.log"
  echo "  tail -f ${LOG_DIR}/steam.log"
  echo
  if [ -n "$tsip" ]; then
    echo "Sunshine Web UI: https://${tsip}:47990"
  fi
  echo "Steam user: ${STEAM_USER}"
  echo "DISPLAY: ${DISPLAY}"
}

main() {
  need_root
  prepare_common

  if [ "$START_SUNSHINE" != "0" ]; then
    start_sunshine_stack
  else
    wait_for_xorg
  fi

  if [ "$WAIT_FOR_MOONLIGHT" = "1" ]; then
    echo "Waiting for Moonlight to connect before starting input/Steam"
    wait_for_passthrough_devices || true
  fi

  if [ "$VERIFY_GPU" != "0" ]; then
    verify_gpu_stack || {
      if [ "$START_STEAM_ANYWAY" != "1" ]; then
        START_STEAM=0
      fi
    }
  fi

  if [ "$START_INPUT" != "0" ]; then
    start_input_bridge
  fi

  if [ "$START_STEAM" != "0" ]; then
    start_steam
  fi

  print_status
}

main "$@"
