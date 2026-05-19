#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="${SERVICE_DIR:-/opt/container-services/steam-headless}"
DATA_DIR="${DATA_DIR:-/opt/container-data/steam-headless}"
GAMES_DIR="${GAMES_DIR:-/mnt/games}"
LOG_DIR="${LOG_DIR:-/tmp/machine-dev-steam-headless}"

IMAGE="${STEAM_HEADLESS_IMAGE:-josh5/steam-headless:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-SteamHeadless}"
DISPLAY="${DISPLAY:-:55}"
DISPLAY_SIZEW="${DISPLAY_SIZEW:-1920}"
DISPLAY_SIZEH="${DISPLAY_SIZEH:-1080}"
DISPLAY_REFRESH="${DISPLAY_REFRESH:-144}"
DISPLAY_CDEPTH="${DISPLAY_CDEPTH:-24}"
DISPLAY_VIDEO_PORT="${DISPLAY_VIDEO_PORT:-DFP}"

TZ="${TZ:-Europe/Amsterdam}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
USER_PASSWORD="${USER_PASSWORD:-password}"
SUNSHINE_USER="${SUNSHINE_USER:-admin}"
SUNSHINE_PASS="${SUNSHINE_PASS:-admin}"
PORT_NOVNC_WEB="${PORT_NOVNC_WEB:-8083}"
SHM_SIZE="${SHM_SIZE:-2G}"

STOP_EXISTING_STACKS="${STOP_EXISTING_STACKS:-1}"
FORCE_RECREATE="${FORCE_RECREATE:-1}"
PULL_IMAGE="${PULL_IMAGE:-0}"
CLEAN_DRIVER_CACHE="${CLEAN_DRIVER_CACHE:-1}"
SHOW_LOGS="${SHOW_LOGS:-1}"
FOLLOW_LOGS="${FOLLOW_LOGS:-0}"

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

install_basics() {
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl git docker.io docker-compose-plugin

  if command -v systemctl >/dev/null 2>&1; then
    systemctl start docker 2>/dev/null || true
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: docker compose plugin is not available after install."
    exit 1
  fi
}

stop_existing_stacks() {
  [ "$STOP_EXISTING_STACKS" = "1" ] || return 0

  echo "Stopping existing Wolf/Sunshine/Xorg/Steam processes that may conflict"
  docker rm -f wolf WolfPulseAudio 2>/dev/null || true
  docker ps -a --format '{{.Names}}' | awk '/^Wolf/{print}' | xargs -r docker rm -f 2>/dev/null || true
  pkill sunshine 2>/dev/null || true
  pkill Xorg 2>/dev/null || true
  pkill openbox 2>/dev/null || true
  pkill -u runner -f 'steam|steamwebhelper|wine|gamescope|pressure-vessel|srt-logger|zenity' 2>/dev/null || true
}

prepare_devices() {
  modprobe fuse 2>/dev/null || true
  modprobe uinput 2>/dev/null || true

  [ -e /dev/uinput ] || mknod /dev/uinput c 10 223 2>/dev/null || true

  chmod 666 /dev/fuse /dev/uinput 2>/dev/null || true
  chmod -R a+rw /dev/input /dev/dri /dev/nvidia* 2>/dev/null || true

  if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    echo "WARNING: Docker does not report an nvidia runtime."
    echo "Steam Headless compose uses runtime: nvidia, so start may fail until nvidia-container-toolkit is installed."
  fi
}

detect_nvidia_version() {
  local version=""

  version="$(cat /sys/module/nvidia/version 2>/dev/null || true)"
  if [ -z "$version" ] && command -v nvidia-smi >/dev/null 2>&1; then
    version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
  fi

  if [ -z "$version" ]; then
    echo "ERROR: unable to detect NVIDIA driver version."
    echo "Set NVIDIA_DRIVER_VERSION=... and run again."
    exit 1
  fi

  echo "$version"
}

download_nvidia_driver() {
  local version="$1"
  local downloads_dir="${DATA_DIR}/home/Downloads"
  local target="${downloads_dir}/NVIDIA_${version}.run"

  mkdir -p "$downloads_dir"

  if [ "$CLEAN_DRIVER_CACHE" = "1" ]; then
    find "$downloads_dir" -maxdepth 1 -type f -name 'NVIDIA_*.run' ! -name "NVIDIA_${version}.run" -delete
    rm -f "${downloads_dir}/nvidia_gpu_install.log"
  fi

  if [ -s "$target" ]; then
    echo "NVIDIA driver installer already cached: ${target}"
    chmod +x "$target"
    return 0
  fi

  echo "Downloading NVIDIA driver ${version} for Steam Headless cache"
  local urls=(
    "https://us.download.nvidia.com/tesla/${version}/NVIDIA-Linux-x86_64-${version}.run"
    "https://download.nvidia.com/XFree86/Linux-x86_64/${version}/NVIDIA-Linux-x86_64-${version}.run"
    "https://us.download.nvidia.com/XFree86/Linux-x86_64/${version}/NVIDIA-Linux-x86_64-${version}.run"
  )

  local url
  for url in "${urls[@]}"; do
    echo "Trying ${url}"
    if curl -fL --retry 3 --retry-delay 2 -o "${target}.tmp" "$url"; then
      mv "${target}.tmp" "$target"
      chmod +x "$target"
      echo "Cached NVIDIA driver installer: ${target}"
      return 0
    fi
  done

  rm -f "${target}.tmp"
  echo "ERROR: unable to download NVIDIA driver ${version}."
  exit 1
}

write_env_file() {
  local version="$1"
  local env_file="${SERVICE_DIR}/.env"

  if [ -f "$env_file" ]; then
    cp "$env_file" "${env_file}.bak.$(date +%s)"
  fi

  cat >"$env_file" <<EOF
NAME=${CONTAINER_NAME}
TZ=${TZ}
USER_LOCALES=en_US.UTF-8 UTF-8
DISPLAY=${DISPLAY}
SHM_SIZE=${SHM_SIZE}
HOME_DIR=${DATA_DIR}/home
SHARED_SOCKETS_DIR=${DATA_DIR}/sockets
GAMES_DIR=${GAMES_DIR}

PUID=${PUID}
PGID=${PGID}
UMASK=000
USER_PASSWORD=${USER_PASSWORD}

MODE=primary

WEB_UI_MODE=vnc
ENABLE_VNC_AUDIO=true
PORT_NOVNC_WEB=${PORT_NOVNC_WEB}
NEKO_NAT1TO1=

ENABLE_STEAM=true
STEAM_ARGS=-silent

ENABLE_SUNSHINE=true
SUNSHINE_USER=${SUNSHINE_USER}
SUNSHINE_PASS=${SUNSHINE_PASS}

ENABLE_EVDEV_INPUTS=true
FORCE_X11_DUMMY_CONFIG=true
DISPLAY_SIZEW=${DISPLAY_SIZEW}
DISPLAY_SIZEH=${DISPLAY_SIZEH}
DISPLAY_REFRESH=${DISPLAY_REFRESH}
DISPLAY_CDEPTH=${DISPLAY_CDEPTH}
DISPLAY_VIDEO_PORT=${DISPLAY_VIDEO_PORT}

NVIDIA_DRIVER_CAPABILITIES=all
NVIDIA_VISIBLE_DEVICES=all
NVIDIA_DRIVER_VERSION=${version}
EOF
}

write_compose_file() {
  local compose_file="${SERVICE_DIR}/docker-compose.yml"

  if [ -f "$compose_file" ]; then
    cp "$compose_file" "${compose_file}.bak.$(date +%s)"
  fi

  cat >"$compose_file" <<'EOF'
services:
  steam-headless:
    image: ${STEAM_HEADLESS_IMAGE:-josh5/steam-headless:latest}
    container_name: ${NAME}
    restart: unless-stopped
    shm_size: ${SHM_SIZE}
    ipc: host
    ulimits:
      nofile:
        soft: 1024
        hard: 524288
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
      - SYS_NICE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    runtime: nvidia
    network_mode: host
    hostname: ${NAME}
    extra_hosts:
      - "${NAME}:127.0.0.1"
    environment:
      - TZ=${TZ}
      - USER_LOCALES=${USER_LOCALES}
      - DISPLAY=${DISPLAY}
      - DISPLAY_SIZEW=${DISPLAY_SIZEW}
      - DISPLAY_SIZEH=${DISPLAY_SIZEH}
      - DISPLAY_REFRESH=${DISPLAY_REFRESH}
      - DISPLAY_CDEPTH=${DISPLAY_CDEPTH}
      - DISPLAY_VIDEO_PORT=${DISPLAY_VIDEO_PORT}
      - PUID=${PUID}
      - PGID=${PGID}
      - UMASK=${UMASK}
      - USER_PASSWORD=${USER_PASSWORD}
      - MODE=${MODE}
      - WEB_UI_MODE=${WEB_UI_MODE}
      - ENABLE_VNC_AUDIO=${ENABLE_VNC_AUDIO}
      - PORT_NOVNC_WEB=${PORT_NOVNC_WEB}
      - NEKO_NAT1TO1=${NEKO_NAT1TO1}
      - ENABLE_STEAM=${ENABLE_STEAM}
      - STEAM_ARGS=${STEAM_ARGS}
      - ENABLE_SUNSHINE=${ENABLE_SUNSHINE}
      - SUNSHINE_USER=${SUNSHINE_USER}
      - SUNSHINE_PASS=${SUNSHINE_PASS}
      - ENABLE_EVDEV_INPUTS=${ENABLE_EVDEV_INPUTS}
      - FORCE_X11_DUMMY_CONFIG=${FORCE_X11_DUMMY_CONFIG}
      - NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES}
      - NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES}
      - NVIDIA_DRIVER_VERSION=${NVIDIA_DRIVER_VERSION}
    devices:
      - /dev/fuse
      - /dev/uinput
    device_cgroup_rules:
      - 'c 13:* rmw'
    volumes:
      - ${HOME_DIR}/:/home/default/:rw
      - ${GAMES_DIR}/:/mnt/games/:rw
      - ${SHARED_SOCKETS_DIR}/.X11-unix/:/tmp/.X11-unix/:rw
      - ${SHARED_SOCKETS_DIR}/pulse/:/tmp/pulse/:rw
EOF
}

prepare_dirs() {
  mkdir -p \
    "$SERVICE_DIR" \
    "${DATA_DIR}/home/Downloads" \
    "${DATA_DIR}/sockets/.X11-unix" \
    "${DATA_DIR}/sockets/pulse" \
    "$GAMES_DIR" \
    "$LOG_DIR"

  chmod 1777 "${DATA_DIR}/sockets/.X11-unix" 2>/dev/null || true
  chown -R "${PUID}:${PGID}" "${DATA_DIR}/home" "$GAMES_DIR" 2>/dev/null || true
}

start_stack() {
  cd "$SERVICE_DIR"

  docker compose down --remove-orphans >/dev/null 2>&1 || true

  if [ "$PULL_IMAGE" = "1" ]; then
    STEAM_HEADLESS_IMAGE="$IMAGE" docker compose pull
  fi

  local recreate_args=()
  if [ "$FORCE_RECREATE" = "1" ]; then
    recreate_args+=(--force-recreate)
  fi

  STEAM_HEADLESS_IMAGE="$IMAGE" docker compose up -d "${recreate_args[@]}"
}

print_status() {
  local tsip
  tsip="$(tailscale_ip | tr -d '[:space:]')"

  echo
  echo "Steam Headless stack started."
  echo
  echo "Files:"
  echo "  ${SERVICE_DIR}/docker-compose.yml"
  echo "  ${SERVICE_DIR}/.env"
  echo "  ${DATA_DIR}/home/Downloads/NVIDIA_$(cat /sys/module/nvidia/version 2>/dev/null || echo '<version>').run"
  echo
  echo "Logs:"
  echo "  cd ${SERVICE_DIR}"
  echo "  docker compose logs -f --tail=200"
  echo "  docker logs -f ${CONTAINER_NAME}"
  echo
  echo "Shell:"
  echo "  docker exec -it ${CONTAINER_NAME} bash"
  echo
  if [ -n "$tsip" ]; then
    echo "noVNC:"
    echo "  http://${tsip}:${PORT_NOVNC_WEB}"
    echo
    echo "Sunshine:"
    echo "  https://${tsip}:47990"
    echo "  user: ${SUNSHINE_USER}"
    echo "  pass: ${SUNSHINE_PASS}"
  else
    echo "noVNC: http://<host-ip>:${PORT_NOVNC_WEB}"
    echo "Sunshine: https://<host-ip>:47990"
  fi
  echo
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | sed -n '1,15p'
}

show_logs() {
  [ "$SHOW_LOGS" = "1" ] || return 0
  cd "$SERVICE_DIR"
  if [ "$FOLLOW_LOGS" = "1" ]; then
    docker compose logs -f --tail=200
  else
    docker compose logs --tail=200
  fi
}

main() {
  need_root
  install_basics
  stop_existing_stacks
  prepare_devices
  prepare_dirs

  local nvidia_version
  nvidia_version="${NVIDIA_DRIVER_VERSION:-$(detect_nvidia_version)}"

  download_nvidia_driver "$nvidia_version"
  write_env_file "$nvidia_version"
  write_compose_file
  start_stack
  print_status
  show_logs
}

main "$@"
