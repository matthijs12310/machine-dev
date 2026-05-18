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
export AUDIO_RUNTIME_DIR="${AUDIO_RUNTIME_DIR:-/tmp/runtime-${STEAM_USER}}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${AUDIO_RUNTIME_DIR}/pulse/native}"

export SUNSHINE_CONFIG_DIR="${SUNSHINE_CONFIG_DIR:-/root/.config/sunshine}"

START_SUNSHINE="${START_SUNSHINE:-1}"
START_AUDIO="${START_AUDIO:-1}"
START_INPUT="${START_INPUT:-1}"
START_STEAM="${START_STEAM:-1}"
VERIFY_GPU="${VERIFY_GPU:-1}"
START_STEAM_ANYWAY="${START_STEAM_ANYWAY:-0}"
WAIT_FOR_MOONLIGHT="${WAIT_FOR_MOONLIGHT:-0}"

XORG_WAIT_TIMEOUT="${XORG_WAIT_TIMEOUT:-300}"
SUNSHINE_WAIT_TIMEOUT="${SUNSHINE_WAIT_TIMEOUT:-300}"
INPUT_WAIT_TIMEOUT="${INPUT_WAIT_TIMEOUT:-600}"
AUDIO_SINK_WAIT_TIMEOUT="${AUDIO_SINK_WAIT_TIMEOUT:-600}"
INPUT_PERMISSION_WATCH_SECONDS="${INPUT_PERMISSION_WATCH_SECONDS:-1800}"

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

prepare_common() {
  mkdir -p "$LOG_DIR" /dev/shm "/tmp/runtime-${STEAM_USER}"
  chmod 1777 /tmp /dev/shm || true

  modprobe uinput 2>/dev/null || true
  if [ ! -e /dev/uinput ]; then
    mknod /dev/uinput c 10 223 2>/dev/null || true
  fi

  if id "$STEAM_USER" >/dev/null 2>&1; then
    usermod -aG input "$STEAM_USER" 2>/dev/null || true
    chown "$STEAM_USER:$STEAM_USER" "/tmp/runtime-${STEAM_USER}" || true
  fi

  chmod 700 "/tmp/runtime-${STEAM_USER}" || true
  chmod -R a+rw /dev/input /dev/uinput /dev/dri /dev/nvidia* 2>/dev/null || true

  mkdir -p "$SUNSHINE_CONFIG_DIR"
}

start_input_permission_watcher() {
  (
    for _ in $(seq 1 "$INPUT_PERMISSION_WATCH_SECONDS"); do
      chmod -R a+rw /dev/input /dev/uinput 2>/dev/null || true
      sleep 2
    done
  ) >"${LOG_DIR}/input-permissions.log" 2>&1 &
  echo $! >"${LOG_DIR}/input-permissions.pid"
}

find_helper() {
  local name="$1"
  local candidate

  for candidate in \
    "${script_dir}/${name}" \
    "$(pwd)/${name}" \
    "/usr/local/bin/${name}" \
    "/opt/machine-dev-gaming/${name}"
  do
    if [ -f "$candidate" ]; then
      chmod +x "$candidate" 2>/dev/null || true
      echo "$candidate"
      return 0
    fi
  done

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  echo "ERROR: helper script not found: ${name}" >&2
  echo "Looked in:" >&2
  echo "  ${script_dir}/${name}" >&2
  echo "  $(pwd)/${name}" >&2
  echo "  /usr/local/bin/${name}" >&2
  echo "  /opt/machine-dev-gaming/${name}" >&2
  return 1
}

wait_for_xorg() {
  local i

  echo "Waiting up to ${XORG_WAIT_TIMEOUT}s for Xorg on ${DISPLAY}"

  for i in $(seq 1 "$XORG_WAIT_TIMEOUT"); do
    if DISPLAY="$DISPLAY" xdpyinfo >/dev/null 2>&1; then
      echo "Xorg is ready on ${DISPLAY}"
      return 0
    fi

    if [ "$((i % 15))" -eq 0 ]; then
      if pgrep -a Xorg >/dev/null 2>&1; then
        echo "Xorg process exists, but xdpyinfo cannot access ${DISPLAY} yet..."
      else
        echo "Still waiting for Xorg process..."
      fi
    fi

    sleep 1
  done

  echo "WARNING: Xorg did not report ready via xdpyinfo on ${DISPLAY}."
  echo "Continuing anyway so input/Steam can still start if Xorg finishes asynchronously."
  echo

  echo "Current Xorg processes:"
  pgrep -a Xorg || true
  echo

  echo "Recent Sunshine stack log:"
  tail -120 "${LOG_DIR}/sunshine-stack.log" 2>/dev/null || true
  echo

  return 0
}

wait_for_sunshine() {
  local i

  echo "Waiting up to ${SUNSHINE_WAIT_TIMEOUT}s for Sunshine"

  for i in $(seq 1 "$SUNSHINE_WAIT_TIMEOUT"); do
    if pgrep -x sunshine >/dev/null 2>&1; then
      echo "Sunshine is running"
      return 0
    fi

    if [ "$((i % 15))" -eq 0 ]; then
      echo "Still waiting for Sunshine..."
    fi

    sleep 1
  done

  echo "WARNING: Sunshine did not appear within ${SUNSHINE_WAIT_TIMEOUT}s."
  echo "Continuing anyway so input/Steam can still start if Sunshine finishes asynchronously."
  echo

  echo "Recent Sunshine stack log:"
  tail -120 "${LOG_DIR}/sunshine-stack.log" 2>/dev/null || true
  echo

  return 0
}

wait_for_passthrough_devices() {
  local i

  echo "Waiting for Moonlight passthrough input devices"

  for i in $(seq 1 180); do
    if grep -q 'Keyboard passthrough' /proc/bus/input/devices 2>/dev/null; then
      echo "Moonlight passthrough devices detected"
      return 0
    fi
    sleep 1
  done

  echo "WARNING: Moonlight passthrough devices did not appear yet."
  return 0
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
    echo "GPU checks failed."
    echo "Steam will be skipped unless START_STEAM_ANYWAY=1 is set."
    return 1
  fi

  echo "GPU checks passed."
  return 0
}

start_sunshine_stack() {
  local sunshine_setup

  if ! sunshine_setup="$(find_helper setup-machine-dev-sunshine.sh)"; then
    echo "ERROR: setup-machine-dev-sunshine.sh not found."
    echo "Cannot start Sunshine/Xorg stack."
    return 0
  fi

  echo "Starting Sunshine/Xorg stack on ${DISPLAY} (${GAME_WIDTH}x${GAME_HEIGHT})"
  echo "Sunshine config/state dir: ${SUNSHINE_CONFIG_DIR}"
  echo "Using Sunshine setup script: ${sunshine_setup}"

  pkill -f "$sunshine_setup" 2>/dev/null || true

  nohup env \
    DISPLAY="$DISPLAY" \
    GAME_WIDTH="$GAME_WIDTH" \
    GAME_HEIGHT="$GAME_HEIGHT" \
    GAME_DEPTH="$GAME_DEPTH" \
    STEAM_USER="$STEAM_USER" \
    AUDIO_RUNTIME_DIR="$AUDIO_RUNTIME_DIR" \
    PULSE_SERVER="$PULSE_SERVER" \
    SUNSHINE_CONFIG_DIR="$SUNSHINE_CONFIG_DIR" \
    LOG_DIR=/tmp/machine-dev-sunshine \
    "$sunshine_setup" \
    >"${LOG_DIR}/sunshine-stack.log" 2>&1 &

  echo $! >"${LOG_DIR}/sunshine-stack.pid"

  wait_for_xorg
  wait_for_sunshine
  set_sunshine_default_sink >"${LOG_DIR}/audio-sink-watch.log" 2>&1 &
  echo $! >"${LOG_DIR}/audio-sink-watch.pid"
}

start_audio() {
  local audio_start

  if ! audio_start="$(find_helper start-pulseaudio.sh)"; then
    echo "WARNING: start-pulseaudio.sh not found; audio setup skipped."
    return 0
  fi

  echo "Starting PulseAudio using: ${audio_start}"
  "$audio_start" >"${LOG_DIR}/pulseaudio.log" 2>&1 || {
    echo "WARNING: PulseAudio setup failed. See ${LOG_DIR}/pulseaudio.log"
    return 0
  }
}

set_sunshine_default_sink() {
  if [ "$START_AUDIO" = "0" ] || ! id "$STEAM_USER" >/dev/null 2>&1; then
    return 0
  fi

  for _ in $(seq 1 "$AUDIO_SINK_WAIT_TIMEOUT"); do
    if runuser -u "$STEAM_USER" -- env \
      HOME="/home/${STEAM_USER}" \
      XDG_CONFIG_HOME="/home/${STEAM_USER}/.config" \
      XDG_RUNTIME_DIR="$AUDIO_RUNTIME_DIR" \
      PULSE_SERVER="$PULSE_SERVER" \
      pactl list short sinks 2>/dev/null | grep -q 'sink-sunshine-stereo'; then
      runuser -u "$STEAM_USER" -- env \
        HOME="/home/${STEAM_USER}" \
        XDG_CONFIG_HOME="/home/${STEAM_USER}/.config" \
        XDG_RUNTIME_DIR="$AUDIO_RUNTIME_DIR" \
        PULSE_SERVER="$PULSE_SERVER" \
        pactl set-default-sink sink-sunshine-stereo >/dev/null 2>&1 || true
      echo "Default PulseAudio sink: sink-sunshine-stereo"
      return 0
    fi
    sleep 1
  done

  echo "WARNING: sink-sunshine-stereo did not appear within ${AUDIO_SINK_WAIT_TIMEOUT}s."
  return 0
}

start_input_bridge() {
  local input_bridge

  if ! input_bridge="$(find_helper start-input-bridge.sh)"; then
    echo "ERROR: start-input-bridge.sh not found."
    echo "Moonlight input bridge was not started."
    echo
    echo "Files in script directory:"
    ls -la "$script_dir" || true
    echo
    return 0
  fi

  echo "Starting Moonlight input bridge: ${input_bridge}"

  nohup env \
    DISPLAY="$DISPLAY" \
    INPUT_WAIT_TIMEOUT="$INPUT_WAIT_TIMEOUT" \
    BRIDGE_MOUSE="${BRIDGE_MOUSE:-xtest}" \
    BRIDGE_KEYBOARD="${BRIDGE_KEYBOARD:-xdotool}" \
    "$input_bridge" \
    >"${LOG_DIR}/input-bridge.log" 2>&1 &

  echo $! >"${LOG_DIR}/input-bridge.pid"

  sleep 2

  if ! kill -0 "$(cat "${LOG_DIR}/input-bridge.pid")" 2>/dev/null; then
    echo "WARNING: input bridge exited immediately."
    echo "Recent input bridge log:"
    tail -120 "${LOG_DIR}/input-bridge.log" 2>/dev/null || true
    echo
  else
    echo "Input bridge started. Log: ${LOG_DIR}/input-bridge.log"
  fi
}

start_steam() {
  local steam_start

  if ! steam_start="$(find_helper start-steam.sh)"; then
    echo "ERROR: start-steam.sh not found."
    echo "Steam was not started."
    return 0
  fi

  echo "Starting Steam using: ${steam_start}"

  DISPLAY="$DISPLAY" xhost "+SI:localuser:${STEAM_USER}" >/dev/null 2>&1 || true

  pkill -u "$STEAM_USER" -f 'steam|steamwebhelper|srt-logger|zenity' 2>/dev/null || true
  rm -f /dev/shm/Steam* /dev/shm/steam* /dev/shm/.org.chromium.* /tmp/.org.chromium.* 2>/dev/null || true

  nohup env \
    DISPLAY="$DISPLAY" \
    STEAM_USER="$STEAM_USER" \
    STEAM_RUNTIME="$STEAM_RUNTIME" \
    STEAM_LD_LIBRARY_PATH="$STEAM_LD_LIBRARY_PATH" \
    XDG_RUNTIME_DIR="$AUDIO_RUNTIME_DIR" \
    PULSE_SERVER="$PULSE_SERVER" \
    STEAM_ARGS="$STEAM_ARGS" \
    "$steam_start" \
    >"${LOG_DIR}/steam.log" 2>&1 &

  echo $! >"${LOG_DIR}/steam.pid"

  sleep 2

  if ! kill -0 "$(cat "${LOG_DIR}/steam.pid")" 2>/dev/null; then
    echo "WARNING: Steam launcher exited immediately."
    echo "Recent Steam log:"
    tail -120 "${LOG_DIR}/steam.log" 2>/dev/null || true
    echo
  else
    echo "Steam started. Log: ${LOG_DIR}/steam.log"
  fi
}

print_status() {
  local tsip
  tsip="$(tailscale_ip | tr -d '[:space:]')"

  echo
  echo "Gaming stack launch finished."
  echo
  echo "Logs:"
  echo "  Sunshine: ${LOG_DIR}/sunshine-stack.log"
  echo "  Audio:    ${LOG_DIR}/pulseaudio.log"
  echo "  Sink set: ${LOG_DIR}/audio-sink-watch.log"
  echo "  Devices:  ${LOG_DIR}/input-permissions.log"
  echo "  Input:    ${LOG_DIR}/input-bridge.log"
  echo "  Steam:    ${LOG_DIR}/steam.log"
  echo
  echo "Useful commands:"
  echo "  tail -f ${LOG_DIR}/sunshine-stack.log"
  echo "  tail -f ${LOG_DIR}/pulseaudio.log"
  echo "  tail -f ${LOG_DIR}/audio-sink-watch.log"
  echo "  tail -f ${LOG_DIR}/input-permissions.log"
  echo "  tail -f ${LOG_DIR}/input-bridge.log"
  echo "  tail -f ${LOG_DIR}/steam.log"
  echo
  echo "Processes:"
  echo "  Xorg:     $(pgrep -a Xorg 2>/dev/null || echo 'not found')"
  echo "  Sunshine: $(pgrep -a sunshine 2>/dev/null || echo 'not found')"
  echo
  echo "Sunshine state dir:"
  echo "  ${SUNSHINE_CONFIG_DIR}"
  ls -la "$SUNSHINE_CONFIG_DIR" 2>/dev/null || true
  echo

  if [ -n "$tsip" ]; then
    echo "Sunshine Web UI: https://${tsip}:47990"
  else
    echo "Sunshine Web UI: https://<host-ip>:47990"
  fi

  echo "Steam user: ${STEAM_USER}"
  echo "DISPLAY: ${DISPLAY}"
}

main() {
  need_root
  prepare_common
  start_input_permission_watcher

  echo "Using script directory: ${script_dir}"
  echo "Using log directory: ${LOG_DIR}"
  echo "Using Sunshine config/state directory: ${SUNSHINE_CONFIG_DIR}"
  echo

  if [ "$START_SUNSHINE" != "0" ]; then
    if [ "$START_AUDIO" != "0" ]; then
      start_audio
    fi
    start_sunshine_stack
  else
    wait_for_xorg
  fi

  if [ "$WAIT_FOR_MOONLIGHT" = "1" ]; then
    wait_for_passthrough_devices
  fi

  if [ "$START_INPUT" != "0" ]; then
    start_input_bridge
  fi

  if [ "$VERIFY_GPU" != "0" ]; then
    if ! verify_gpu_stack; then
      if [ "$START_STEAM_ANYWAY" != "1" ]; then
        START_STEAM=0
      fi
    fi
  fi

  if [ "$START_STEAM" != "0" ]; then
    start_steam
  else
    echo "Steam not started."
  fi

  print_status
}

main "$@"
