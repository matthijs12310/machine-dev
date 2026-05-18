#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DISPLAY="${DISPLAY:-:99}"
WIDTH="${GAME_WIDTH:-1920}"
HEIGHT="${GAME_HEIGHT:-1080}"
DEPTH="${GAME_DEPTH:-24}"
SUNSHINE_USER="${SUNSHINE_USER:-admin}"
SUNSHINE_PASS="${SUNSHINE_PASS:-changeme123}"
SUNSHINE_CONFIG_DIR="${SUNSHINE_CONFIG_DIR:-/root/.config/sunshine}"
SUNSHINE_CONF="${SUNSHINE_CONFIG_DIR}/sunshine.conf"
LOG_DIR="${LOG_DIR:-/tmp/machine-dev-sunshine}"

display_num="${DISPLAY#:}"
display_num="${display_num%%.*}"

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

nvidia_busid() {
  local pci bus_hex dev_hex fn_dec bus_dec dev_dec rest
  pci="$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
  [ -n "$pci" ] || return 0
  pci="${pci#00000000:}"
  bus_hex="${pci%%:*}"
  rest="${pci#*:}"
  dev_hex="${rest%%.*}"
  fn_dec="${rest#*.}"
  bus_dec="$(printf '%d' "0x${bus_hex}" 2>/dev/null || true)"
  dev_dec="$(printf '%d' "0x${dev_hex}" 2>/dev/null || true)"
  [ -n "$bus_dec" ] && [ -n "$dev_dec" ] && [ -n "$fn_dec" ] || return 0
  printf 'PCI:%s:%s:%s\n' "$bus_dec" "$dev_dec" "$fn_dec"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg \
    xserver-xorg-core x11-xserver-utils x11-utils \
    openbox mesa-utils vulkan-tools xdotool python3-evdev \
    libgl1 libegl1 libvulkan1 \
    libx11-6 libxtst6 \
    libayatana-appindicator3-1 libnotify4 libevdev2 \
    udev dbus-x11

  if ! find /usr -name nvidia_drv.so -print -quit 2>/dev/null | grep -q .; then
    local driver_version driver_major package package_version
    driver_version="$(awk '/NVRM version:/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }' /proc/driver/nvidia/version 2>/dev/null || true)"
    if [ -z "${driver_version:-}" ] && command -v nvidia-smi >/dev/null 2>&1; then
      driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
    fi
    driver_major="${driver_version%%.*}"
    package="xserver-xorg-video-nvidia-${driver_major}"
    if [ -n "${driver_major:-}" ] && apt-cache show "$package" >/dev/null 2>&1; then
      package_version="$(apt-cache madison "$package" | awk -v want="$driver_version" '$3 ~ "^" want { print $3; exit }')"
      if [ -n "${package_version:-}" ]; then
        apt-get install -y --allow-downgrades --no-install-recommends "${package}=${package_version}" || true
      else
        echo "No exact ${package} package found for host NVIDIA ${driver_version}; not installing a mismatched Xorg driver."
        echo "Set ALLOW_MISMATCHED_NVIDIA_XORG=1 to install the repo default anyway."
        if [ "${ALLOW_MISMATCHED_NVIDIA_XORG:-0}" = "1" ]; then
          apt-get install -y --no-install-recommends "$package" || true
        fi
      fi
    fi
  fi
}

install_sunshine() {
  if command -v sunshine >/dev/null 2>&1; then
    return 0
  fi

  local deb="/tmp/sunshine-ubuntu-22.04-amd64.deb"
  wget -O "$deb" "https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-ubuntu-22.04-amd64.deb"
  apt-get install -y "$deb"
}

write_xorg_config() {
  local busid busid_line
  busid="$(nvidia_busid)"
  busid_line=""
  if [ -n "$busid" ]; then
    busid_line="    BusID \"${busid}\""
  fi

  cat >/etc/X11/xorg-nvidia-headless.conf <<EOF
Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "AllowMouseOpenFail" "true"
EndSection

Section "Device"
    Identifier "NvidiaDevice"
    Driver "nvidia"
${busid_line}
    Option "AllowEmptyInitialConfiguration" "true"
    Option "ProbeAllGpus" "false"
    Option "VirtualHeads" "1"
    Option "ModeValidation" "NoEdidModes,NoMaxPClkCheck,NoHorizSyncCheck,NoVertRefreshCheck,NoDFPNativeResolutionCheck"
EndSection

Section "Monitor"
    Identifier "NvidiaMonitor"
    HorizSync 28.0-255.0
    VertRefresh 24.0-240.0
EndSection

Section "Screen"
    Identifier "NvidiaScreen"
    Device "NvidiaDevice"
    Monitor "NvidiaMonitor"
    DefaultDepth ${DEPTH}
    Option "MetaModes" "${WIDTH}x${HEIGHT} +0+0"
    SubSection "Display"
        Depth ${DEPTH}
        Modes "${WIDTH}x${HEIGHT}"
        Virtual ${WIDTH} ${HEIGHT}
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen "NvidiaScreen"
EndSection
EOF
}

start_xorg() {
  mkdir -p "$LOG_DIR" /tmp/.X11-unix
  pkill -9 Xorg openbox 2>/dev/null || true
  rm -f "/tmp/.X${display_num}-lock" "/tmp/.X11-unix/X${display_num}"

  chmod -R a+rw /dev/uinput /dev/input /dev/dri /dev/nvidia* 2>/dev/null || true

  Xorg "$DISPLAY" \
    -config /etc/X11/xorg-nvidia-headless.conf \
    -noreset -nolisten tcp \
    -logfile "${LOG_DIR}/xorg-nvidia.log" \
    >"${LOG_DIR}/xorg-stdout.log" 2>&1 &

  for _ in $(seq 1 30); do
    if DISPLAY="$DISPLAY" xdpyinfo >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! DISPLAY="$DISPLAY" xdpyinfo >/dev/null 2>&1; then
    echo "NVIDIA Xorg failed to start on ${DISPLAY}"
    echo "=== ${LOG_DIR}/xorg-nvidia.log ==="
    tail -160 "${LOG_DIR}/xorg-nvidia.log" || true
    exit 1
  fi

  DISPLAY="$DISPLAY" openbox >"${LOG_DIR}/openbox.log" 2>&1 &
  DISPLAY="$DISPLAY" xsetroot -cursor_name left_ptr 2>/dev/null || true

  local output_name
  output_name="$(DISPLAY="$DISPLAY" xrandr 2>/dev/null | awk '/ connected/{print $1; exit}' || true)"
  if [ -n "$output_name" ]; then
    DISPLAY="$DISPLAY" xrandr --output "$output_name" --mode "${WIDTH}x${HEIGHT}" --pos 0x0 --primary 2>/dev/null || true
  fi
  DISPLAY="$DISPLAY" xrandr --fb "${WIDTH}x${HEIGHT}" 2>/dev/null || true
}

write_sunshine_config() {
  local tsip origins
  tsip="$(tailscale_ip | tr -d '[:space:]')"
  origins="https://localhost:47990,https://127.0.0.1:47990"
  if [ -n "$tsip" ]; then
    origins="https://${tsip}:47990,${origins}"
  fi

  mkdir -p "$SUNSHINE_CONFIG_DIR"
  mkdir -p "${SUNSHINE_CONFIG_DIR}/credentials"

  cat >"$SUNSHINE_CONF" <<EOF
origin_web_ui_allowed = wan
csrf_allowed_origins = ${origins}
capture = nvfbc
resolutions = [${WIDTH}x${HEIGHT}]
fps = [60]
adapter_name = ${DISPLAY}
output_name = 0

file_state = ${SUNSHINE_CONFIG_DIR}/sunshine_state.json
credentials_file = ${SUNSHINE_CONFIG_DIR}/credentials/sunshine_credentials.json
pkey = ${SUNSHINE_CONFIG_DIR}/credentials/cakey.pem
cert = ${SUNSHINE_CONFIG_DIR}/credentials/cacert.pem
EOF

  if [ -n "$tsip" ]; then
    cat >>"$SUNSHINE_CONF" <<EOF
external_ip = ${tsip}
EOF
  fi

  HOME="/root" sunshine --creds "$SUNSHINE_USER" "$SUNSHINE_PASS" >/dev/null 2>&1 || true
}

print_status() {
  local tsip
  tsip="$(tailscale_ip | tr -d '[:space:]')"
  echo
  echo "Xorg display: ${DISPLAY}"
  echo "Target resolution: ${WIDTH}x${HEIGHT}"
  echo "Sunshine config: ${SUNSHINE_CONF}"
  echo "Sunshine login: ${SUNSHINE_USER} / ${SUNSHINE_PASS}"
  if [ -n "$tsip" ]; then
    echo "Sunshine Web UI: https://${tsip}:47990"
  else
    echo "Sunshine Web UI: https://<host-ip>:47990"
  fi
  echo
  echo "Renderer:"
  DISPLAY="$DISPLAY" glxinfo -B 2>/dev/null | grep -E 'direct rendering|OpenGL vendor|OpenGL renderer' || true
  echo
}

main() {
  need_root
  install_packages
  install_sunshine
  write_xorg_config
  start_xorg
  write_sunshine_config
  print_status

  pkill sunshine 2>/dev/null || true
  echo "Starting Sunshine in foreground. Leave this process running."
  echo "After Moonlight connects, run in another SSH shell:"
  echo "  DISPLAY=${DISPLAY} ${script_dir}/start-input-bridge.sh"
  exec env DISPLAY="$DISPLAY" HOME="/root" sunshine "$SUNSHINE_CONF"
}

main "$@"
