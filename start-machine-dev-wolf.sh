#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/tmp/machine-dev-wolf}"
WOLF_CONFIG_DIR="${WOLF_CONFIG_DIR:-/etc/wolf}"
WOLF_CONTAINER="${WOLF_CONTAINER:-wolf}"
WOLF_IMAGE="${WOLF_IMAGE:-ghcr.io/games-on-whales/wolf:stable}"
WOLF_UI_BASE_IMAGE="${WOLF_UI_BASE_IMAGE:-ghcr.io/games-on-whales/wolf-ui:main}"
WOLF_UI_IMAGE="${WOLF_UI_IMAGE:-wolf-ui-opengl:local}"
NVIDIA_DRIVER_IMAGE="${NVIDIA_DRIVER_IMAGE:-gow/nvidia-driver:latest}"
NVIDIA_DRIVER_VOLUME="${NVIDIA_DRIVER_VOLUME:-nvidia-driver-vol}"
WOLF_INTERNAL_IP="${WOLF_INTERNAL_IP:-}"
WOLF_INTERNAL_MAC="${WOLF_INTERNAL_MAC:-02:00:00:00:00:01}"
STOP_EXISTING_STACKS="${STOP_EXISTING_STACKS:-1}"
PATCH_WOLF_UI="${PATCH_WOLF_UI:-1}"
REBUILD_NVIDIA_DRIVER_VOLUME="${REBUILD_NVIDIA_DRIVER_VOLUME:-0}"
VERIFY_NVIDIA_DOCKER="${VERIFY_NVIDIA_DOCKER:-0}"

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
  if ! command -v docker >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends docker.io
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl start docker 2>/dev/null || true
  fi

  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl
}

stop_existing_stacks() {
  [ "$STOP_EXISTING_STACKS" = "1" ] || return 0

  echo "Stopping existing Sunshine/Xorg/Steam/Wolf processes"
  pkill sunshine 2>/dev/null || true
  pkill Xorg 2>/dev/null || true
  pkill openbox 2>/dev/null || true
  pkill -u runner -f 'steam|steamwebhelper|wine|gamescope|pressure-vessel|srt-logger|zenity' 2>/dev/null || true
  docker rm -f "$WOLF_CONTAINER" WolfPulseAudio 2>/dev/null || true
  docker ps -a --format '{{.Names}}' | awk '/^Wolf/{print}' | xargs -r docker rm -f 2>/dev/null || true
}

ensure_nvidia_modeset() {
  mkdir -p "$LOG_DIR"
  echo 'options nvidia-drm modeset=1' >/etc/modprobe.d/nvidia-drm-modeset.conf

  if [ -r /sys/module/nvidia_drm/parameters/modeset ] && grep -q '^Y$' /sys/module/nvidia_drm/parameters/modeset; then
    echo "nvidia_drm modeset is already enabled"
    return 0
  fi

  echo "Enabling nvidia_drm modeset=1"
  modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia >"${LOG_DIR}/nvidia-module-reload.log" 2>&1 || true
  modprobe nvidia >>"${LOG_DIR}/nvidia-module-reload.log" 2>&1 || true
  modprobe nvidia_uvm >>"${LOG_DIR}/nvidia-module-reload.log" 2>&1 || true
  modprobe nvidia_modeset >>"${LOG_DIR}/nvidia-module-reload.log" 2>&1 || true
  modprobe nvidia_drm modeset=1 >>"${LOG_DIR}/nvidia-module-reload.log" 2>&1 || true

  if [ -r /sys/module/nvidia_drm/parameters/modeset ]; then
    echo "nvidia_drm modeset: $(cat /sys/module/nvidia_drm/parameters/modeset)"
  else
    echo "WARNING: /sys/module/nvidia_drm/parameters/modeset is missing"
  fi
}

ensure_devices() {
  modprobe uinput 2>/dev/null || true
  modprobe uhid 2>/dev/null || true

  [ -e /dev/uinput ] || mknod /dev/uinput c 10 223 2>/dev/null || true
  [ -e /dev/uhid ] || mknod /dev/uhid c 10 239 2>/dev/null || true

  nvidia-container-cli --load-kmods info >/dev/null 2>&1 || true

  chmod 666 /dev/uinput /dev/uhid 2>/dev/null || true
  chmod -R a+rw /dev/input /dev/dri /dev/nvidia* 2>/dev/null || true
}

verify_nvidia_docker() {
  [ "$VERIFY_NVIDIA_DOCKER" = "1" ] || return 0
  echo "Verifying NVIDIA Docker runtime"
  docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi
}

build_nvidia_driver_volume() {
  mkdir -p "$LOG_DIR"

  if docker volume inspect "$NVIDIA_DRIVER_VOLUME" >/dev/null 2>&1 && [ "$REBUILD_NVIDIA_DRIVER_VOLUME" != "1" ]; then
    echo "NVIDIA driver volume already exists: ${NVIDIA_DRIVER_VOLUME}"
    return 0
  fi

  local nv_version
  nv_version="$(cat /sys/module/nvidia/version 2>/dev/null || true)"
  if [ -z "$nv_version" ]; then
    echo "ERROR: unable to read NVIDIA driver version from /sys/module/nvidia/version"
    exit 1
  fi

  echo "Building NVIDIA driver volume for driver ${nv_version}"
  docker volume rm -f "$NVIDIA_DRIVER_VOLUME" >/dev/null 2>&1 || true

  local build_dir="/tmp/machine-dev-nvidia-driver-build"
  mkdir -p "$build_dir"
  cat >"${build_dir}/Dockerfile" <<'EOF'
FROM ubuntu:22.04
ARG NV_VERSION

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends curl ca-certificates kmod pkg-config libglvnd-dev vulkan-tools && \
    curl -fL -o /tmp/NVIDIA.run "https://us.download.nvidia.com/tesla/${NV_VERSION}/NVIDIA-Linux-x86_64-${NV_VERSION}.run" && \
    chmod +x /tmp/NVIDIA.run && \
    mkdir -p /usr/nvidia && \
    /tmp/NVIDIA.run --silent -z \
      --skip-depmod \
      --skip-module-unload \
      --no-nvidia-modprobe \
      --no-kernel-modules \
      --no-kernel-module-source \
      --opengl-prefix=/usr/nvidia \
      --wine-prefix=/usr/nvidia \
      --utility-prefix=/usr/nvidia \
      --utility-libdir=lib \
      --compat32-prefix=/usr/nvidia \
      --compat32-libdir=lib32 \
      --egl-external-platform-config-path=/usr/nvidia/share/egl/egl_external_platform.d \
      --glvnd-egl-config-path=/usr/nvidia/share/glvnd/egl_vendor.d \
      --no-distro-scripts && \
    rm /tmp/NVIDIA.run
EOF

  docker build \
    -t "$NVIDIA_DRIVER_IMAGE" \
    -f "${build_dir}/Dockerfile" \
    --build-arg NV_VERSION="$nv_version" \
    "$build_dir" >"${LOG_DIR}/nvidia-driver-volume-build.log" 2>&1

  docker run --rm \
    -v "${NVIDIA_DRIVER_VOLUME}:/usr/nvidia" \
    "$NVIDIA_DRIVER_IMAGE" true >/dev/null
}

docker_device_args() {
  for dev in \
    /dev/nvidia-uvm \
    /dev/nvidia-uvm-tools \
    /dev/nvidiactl \
    /dev/nvidia0 \
    /dev/nvidia-modeset \
    /dev/nvidia-caps/nvidia-cap1 \
    /dev/nvidia-caps/nvidia-cap2 \
    /dev/dri \
    /dev/uinput \
    /dev/uhid
  do
    [ -e "$dev" ] && printf ' --device %q' "$dev"
  done
}

build_wolf_ui_opengl_image() {
  [ "$PATCH_WOLF_UI" = "1" ] || return 0

  local build_dir="/tmp/wolf-ui-opengl-build"
  mkdir -p "$build_dir"
  cat >"${build_dir}/Dockerfile" <<EOF
FROM ${WOLF_UI_BASE_IMAGE}
RUN printf '%s\n' '#!/bin/sh' \\
  'exec wolf-ui --display-driver wayland --rendering-driver opengl3 --rendering-method gl_compatibility -f -t "\$@"' \\
  >/usr/local/bin/wolf-ui-opengl && chmod +x /usr/local/bin/wolf-ui-opengl
ENTRYPOINT ["/usr/local/bin/wolf-ui-opengl"]
EOF

  docker build -t "$WOLF_UI_IMAGE" "$build_dir" >"${LOG_DIR}/wolf-ui-opengl-build.log" 2>&1
}

start_wolf_container() {
  mkdir -p "$WOLF_CONFIG_DIR" "$LOG_DIR"

  if [ -z "$WOLF_INTERNAL_IP" ]; then
    WOLF_INTERNAL_IP="$(tailscale_ip | tr -d '[:space:]')"
  fi

  echo "Starting Wolf container"
  docker rm -f "$WOLF_CONTAINER" 2>/dev/null || true
  local dev_args
  dev_args="$(docker_device_args)"

  # shellcheck disable=SC2086
  docker run -d \
    --name "$WOLF_CONTAINER" \
    --network=host \
    -e NVIDIA_DRIVER_VOLUME_NAME="$NVIDIA_DRIVER_VOLUME" \
    -v "${NVIDIA_DRIVER_VOLUME}:/usr/nvidia:rw" \
    -v "${WOLF_CONFIG_DIR}:/etc/wolf:rw" \
    -v /var/run/docker.sock:/var/run/docker.sock:rw \
    -e WOLF_INTERNAL_IP="$WOLF_INTERNAL_IP" \
    -e WOLF_INTERNAL_MAC="$WOLF_INTERNAL_MAC" \
    -v /dev/:/dev/:rw \
    -v /run/udev:/run/udev:rw \
    --device-cgroup-rule "c 13:* rmw" \
    $dev_args \
    "$WOLF_IMAGE" >/dev/null
}

wait_for_config() {
  local config="${WOLF_CONFIG_DIR}/cfg/config.toml"
  for _ in $(seq 1 60); do
    [ -f "$config" ] && return 0
    sleep 1
  done
  echo "WARNING: Wolf config did not appear at ${config}"
  return 1
}

patch_wolf_config() {
  [ "$PATCH_WOLF_UI" = "1" ] || return 0
  local config="${WOLF_CONFIG_DIR}/cfg/config.toml"
  [ -f "$config" ] || return 0

  cp "$config" "${config}.bak.$(date +%s)"

  python3 - <<PY
from pathlib import Path

config = Path("${config}")
s = config.read_text()

s = s.replace(
    "image = 'ghcr.io/games-on-whales/wolf-ui:main'",
    "image = '${WOLF_UI_IMAGE}'"
)

old_env = """        env = [
            'GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia*',
            'WOLF_SOCKET_PATH=/var/run/wolf/wolf.sock',
            'WOLF_UI_AUTOUPDATE=False',
            'LOGLEVEL=INFO'
        ]"""
new_env = """        env = [
            'GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia*',
            'WOLF_SOCKET_PATH=/var/run/wolf/wolf.sock',
            'WOLF_UI_AUTOUPDATE=False',
            'LOGLEVEL=INFO',
            'GODOT_RENDERING_DRIVER=opengl3',
            'GODOT_RENDERING_METHOD=gl_compatibility'
        ]"""
if old_env in s:
    s = s.replace(old_env, new_env)

config.write_text(s)
PY
}

restart_after_patch() {
  [ "$PATCH_WOLF_UI" = "1" ] || return 0
  docker ps -a --format '{{.Names}}' | awk '/^Wolf-UI_/{print}' | xargs -r docker rm -f 2>/dev/null || true
  docker restart "$WOLF_CONTAINER" >/dev/null
}

print_status() {
  local tsip
  tsip="$(tailscale_ip | tr -d '[:space:]')"

  echo
  echo "Wolf stack launch finished."
  echo
  echo "Moonlight host/IP:"
  if [ -n "$tsip" ]; then
    echo "  ${tsip}"
    echo "Wolf pin URL:"
    echo "  http://${tsip}:47989/pin/"
  else
    echo "  <tailscale-or-host-ip>"
  fi
  echo
  echo "Logs:"
  echo "  docker logs -f ${WOLF_CONTAINER}"
  echo "  docker logs -f \$(docker ps -a --format '{{.Names}}' | grep '^Wolf-UI_' | tail -1)"
  echo "  tail -f ${LOG_DIR}/nvidia-driver-volume-build.log"
  echo "  tail -f ${LOG_DIR}/wolf-ui-opengl-build.log"
  echo
  echo "Containers:"
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | sed -n '1,20p'
  echo
  if [ -r /sys/module/nvidia_drm/parameters/modeset ]; then
    echo "nvidia_drm modeset: $(cat /sys/module/nvidia_drm/parameters/modeset)"
  fi
}

main() {
  need_root
  install_basics
  stop_existing_stacks
  ensure_nvidia_modeset
  ensure_devices
  verify_nvidia_docker
  build_nvidia_driver_volume
  build_wolf_ui_opengl_image
  start_wolf_container
  if wait_for_config; then
    patch_wolf_config
    restart_after_patch
  fi
  print_status
}

main "$@"
