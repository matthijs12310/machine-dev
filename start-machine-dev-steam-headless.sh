#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="${SERVICE_DIR:-/opt/container-services/steam-headless}"
DATA_DIR="${DATA_DIR:-/opt/container-data/steam-headless}"
GAMES_DIR="${GAMES_DIR:-/mnt/games}"
LOG_DIR="${LOG_DIR:-/tmp/machine-dev-steam-headless}"

IMAGE="${STEAM_HEADLESS_IMAGE:-josh5/steam-headless:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-SteamHeadless}"

# hybrid is the Machine.dev/AWS L4 path that works with Proton/DXVK:
# host Xorg provides Vulkan presentation, Steam Headless runs in secondary mode,
# and XFCE/Steam/Sunshine are started manually inside the container on host Xorg.
STEAM_HEADLESS_MODE="${STEAM_HEADLESS_MODE:-hybrid}" # hybrid or primary
HOST_DISPLAY="${HOST_DISPLAY:-:99}"
CONTAINER_DISPLAY="${CONTAINER_DISPLAY:-:55}"
DISPLAY="${DISPLAY:-$HOST_DISPLAY}"

DISPLAY_SIZEW="${DISPLAY_SIZEW:-1920}"
DISPLAY_SIZEH="${DISPLAY_SIZEH:-1080}"
DISPLAY_REFRESH="${DISPLAY_REFRESH:-120}"
DISPLAY_CDEPTH="${DISPLAY_CDEPTH:-24}"
DISPLAY_VIDEO_PORT="${DISPLAY_VIDEO_PORT:-DFP}"
FORCE_X11_DUMMY_CONFIG="${FORCE_X11_DUMMY_CONFIG:-true}"

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
PATCH_UDEV_XORG_RESTART_LOOP="${PATCH_UDEV_XORG_RESTART_LOOP:-1}"
RESTORE_STEAM_SESSION="${RESTORE_STEAM_SESSION:-1}"
STEAM_SESSION_ARCHIVE="${STEAM_SESSION_ARCHIVE:-/root/machine-dev/steam-session.tar.gz}"

START_HOST_XORG="${START_HOST_XORG:-1}"
START_CONTAINER_XFCE="${START_CONTAINER_XFCE:-1}"
START_CONTAINER_SUNSHINE="${START_CONTAINER_SUNSHINE:-1}"
START_CONTAINER_STEAM="${START_CONTAINER_STEAM:-1}"
INSTALL_CONTAINER_BROWSER="${INSTALL_CONTAINER_BROWSER:-1}"
INSTALL_CONTAINER_STEAM_DEPS="${INSTALL_CONTAINER_STEAM_DEPS:-1}"
AUTO_CLICK_STEAM_INSTALL="${AUTO_CLICK_STEAM_INSTALL:-1}"
STEAM_SKIP_PACKAGE_CHECK="${STEAM_SKIP_PACKAGE_CHECK:-1}"
AUTO_ACCEPT_STEAM_INSTALLER="${AUTO_ACCEPT_STEAM_INSTALLER:-1}"
START_STEAM_QR_SERVER="${START_STEAM_QR_SERVER:-1}"
STEAM_QR_HOST="${STEAM_QR_HOST:-0.0.0.0}"
STEAM_QR_PORT="${STEAM_QR_PORT:-8765}"
STEAM_QR_CROP="${STEAM_QR_CROP:-}"
STEAM_QR_TOKEN="${STEAM_QR_TOKEN:-}"
STEAM_QR_SERVER_SOURCE="${STEAM_QR_SERVER_SOURCE:-${SCRIPT_DIR}/steam_qr_server.py}"
STEAM_QR_PYTHON="${STEAM_QR_PYTHON:-/opt/machine-dev/qr-venv/bin/python}"
VERIFY_HOST_VULKAN="${VERIFY_HOST_VULKAN:-1}"
ENABLE_DEBUG_VNC="${ENABLE_DEBUG_VNC:-0}"
HOST_VNC_PORT="${HOST_VNC_PORT:-5901}"
HOST_XORG_CONFIG="${HOST_XORG_CONFIG:-/etc/X11/xorg-host-vulkan.conf}"
HOST_XORG_LOG="${HOST_XORG_LOG:-${LOG_DIR}/host-xorg-99.log}"
HOST_XORG_BUS_ID="${HOST_XORG_BUS_ID:-}"
HOST_XORG_CONNECTED_MONITOR="${HOST_XORG_CONNECTED_MONITOR:-DFP-0}"
HOST_XORG_OUTPUT="${HOST_XORG_OUTPUT:-}"
PULSE_SERVER_PATH="${PULSE_SERVER_PATH:-/tmp/.X11-unix/run/pulse/native}"
MOUSE_PASSTHROUGH_ACCEL="${MOUSE_PASSTHROUGH_ACCEL:-0}"
SUNSHINE_STATE_SOURCE_DIR="${SUNSHINE_STATE_SOURCE_DIR:-${SCRIPT_DIR}/sunshine}"
SUNSHINE_CSRF_ALLOWED_ORIGINS="${SUNSHINE_CSRF_ALLOWED_ORIGINS:-}"
STEAM_COMPAT_MOUNTS="${STEAM_COMPAT_MOUNTS:-/mnt/games}"
ENABLE_PROTON_LOGS="${ENABLE_PROTON_LOGS:-0}"
WAIT_FOR_SUPERVISOR_SECONDS="${WAIT_FOR_SUPERVISOR_SECONDS:-20}"
WAIT_FOR_PULSE_SECONDS="${WAIT_FOR_PULSE_SECONDS:-25}"

TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-}"
TAILSCALE_EXIT_NODE_ALLOW_LAN="${TAILSCALE_EXIT_NODE_ALLOW_LAN:-1}"
TAILSCALE_EXIT_NODE_ACCEPT_ROUTES="${TAILSCALE_EXIT_NODE_ACCEPT_ROUTES:-1}"
TAILSCALE_EXIT_NODE_EXCLUDE_FRP_RELAY="${TAILSCALE_EXIT_NODE_EXCLUDE_FRP_RELAY:-1}"

ENABLE_FRP_SUNSHINE_RELAY="${ENABLE_FRP_SUNSHINE_RELAY:-0}"
FRP_VERSION="${FRP_VERSION:-0.68.1}"
FRP_RELAY_HOST="${FRP_RELAY_HOST:-}"
FRP_RELAY_PORT="${FRP_RELAY_PORT:-443}"
FRP_TOKEN="${FRP_TOKEN:-}"
FRP_SERVICE_NAME="${FRP_SERVICE_NAME:-frpc-sunshine}"
FRP_CONFIG_DIR="${FRP_CONFIG_DIR:-/etc/frp}"
FRP_REMOTE_PORT_47984="${FRP_REMOTE_PORT_47984:-47984}"
FRP_REMOTE_PORT_47989="${FRP_REMOTE_PORT_47989:-47989}"
FRP_REMOTE_PORT_47990="${FRP_REMOTE_PORT_47990:-47990}"
FRP_REMOTE_PORT_48010="${FRP_REMOTE_PORT_48010:-48010}"
FRP_REMOTE_PORT_47998="${FRP_REMOTE_PORT_47998:-47998}"
FRP_REMOTE_PORT_47999="${FRP_REMOTE_PORT_47999:-47999}"
FRP_REMOTE_PORT_48000="${FRP_REMOTE_PORT_48000:-48000}"
FRP_REMOTE_PORT_48002="${FRP_REMOTE_PORT_48002:-48002}"
ENABLE_FRP_STEAM_QR_RELAY="${ENABLE_FRP_STEAM_QR_RELAY:-1}"
FRP_REMOTE_PORT_STEAM_QR="${FRP_REMOTE_PORT_STEAM_QR:-8765}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
  fi
}

is_hybrid() {
  [ "$STEAM_HEADLESS_MODE" = "hybrid" ]
}

prepare_local_steam_library() {
  local library_dir="${GAMES_DIR}/SteamLibrary"

  mkdir -p "${library_dir}/steamapps"
  chown -R "${PUID}:${PGID}" "$library_dir" 2>/dev/null || true
  chmod -R ugo+rwX "$library_dir" 2>/dev/null || true
}

fix_steam_home_ownership() {
  local steam_home="${DATA_DIR}/home/.steam"

  [ -e "$steam_home" ] || return 0
  chown -R "${PUID}:${PGID}" "$steam_home" 2>/dev/null || true
  chmod u+rwX "$steam_home" 2>/dev/null || true
}

seed_local_steam_library_config() {
  local steam_root="${DATA_DIR}/home/.steam/steam"
  local library_path="/mnt/games/SteamLibrary"
  local host_library_path="${GAMES_DIR}/SteamLibrary"
  local default_apps_block=""
  local games_apps_block=""
  local file

  prepare_local_steam_library

  if [ -d "${steam_root}/steamapps" ]; then
    while IFS= read -r manifest; do
      local appid size
      appid="$(basename "$manifest" | sed -n 's/^appmanifest_\([0-9][0-9]*\)\.acf$/\1/p')"
      [ -n "$appid" ] || continue
      size="$(awk -F'"' '/"SizeOnDisk"/ { print $4; exit }' "$manifest" 2>/dev/null)"
      [ -n "$size" ] || size=0
      default_apps_block="${default_apps_block}			\"${appid}\"		\"${size}\"
"
    done < <(find "${steam_root}/steamapps" -maxdepth 1 -type f -name 'appmanifest_*.acf' | sort)
  fi

  if [ -d "${host_library_path}/steamapps" ]; then
    while IFS= read -r manifest; do
      local appid size
      appid="$(basename "$manifest" | sed -n 's/^appmanifest_\([0-9][0-9]*\)\.acf$/\1/p')"
      [ -n "$appid" ] || continue
      size="$(awk -F'"' '/"SizeOnDisk"/ { print $4; exit }' "$manifest" 2>/dev/null)"
      [ -n "$size" ] || size=0
      games_apps_block="${games_apps_block}			\"${appid}\"		\"${size}\"
"
    done < <(find "${host_library_path}/steamapps" -maxdepth 1 -type f -name 'appmanifest_*.acf' | sort)
  fi

  for file in \
    "${steam_root}/steamapps/libraryfolders.vdf" \
    "${steam_root}/config/libraryfolders.vdf"; do
    mkdir -p "$(dirname "$file")"
    cp "$file" "${file}.bak.$(date +%s)" 2>/dev/null || true
    cat >"$file" <<EOF
"libraryfolders"
{
	"0"
	{
		"path"		"/home/default/.steam/steam"
		"label"		""
		"contentid"		"8666328081242447945"
		"totalsize"		"0"
		"apps"
		{
${default_apps_block}
		}
	}
	"1"
	{
		"path"		"$library_path"
		"label"		"Games"
		"contentid"		"1111111111111111111"
		"totalsize"		"0"
		"apps"
		{
${games_apps_block}
		}
	}
}
EOF
  done

  fix_steam_home_ownership
}

tailscale_ip() {
  tailscale ip -4 2>/dev/null | head -1 && return 0
  tailscale --socket=/run/tailscale/tailscaled.sock ip -4 2>/dev/null | head -1 && return 0
  tailscale --socket=/tmp/tailscaled.sock ip -4 2>/dev/null | head -1 && return 0
  true
}

resolve_ipv4s() {
  local host="$1"

  if printf '%s\n' "$host" | grep -Eq '^[0-9]+(\.[0-9]+){3}$'; then
    printf '%s\n' "$host"
    return 0
  fi

  getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u
}

append_csv_unique() {
  local list="$1"
  local value="$2"

  [ -n "$value" ] || {
    printf '%s' "$list"
    return 0
  }

  case ",${list}," in
    *",${value},"*) printf '%s' "$list" ;;
    *)
      if [ -n "$list" ]; then
        printf '%s,%s' "$list" "$value"
      else
        printf '%s' "$value"
      fi
      ;;
  esac
}

sunshine_csrf_allowed_origins() {
  if [ -n "$SUNSHINE_CSRF_ALLOWED_ORIGINS" ]; then
    printf '%s' "$SUNSHINE_CSRF_ALLOWED_ORIGINS"
    return 0
  fi

  local origins=""
  local tsip
  origins="$(append_csv_unique "$origins" "https://localhost:47990")"
  origins="$(append_csv_unique "$origins" "https://127.0.0.1:47990")"

  tsip="$(tailscale_ip | tr -d '[:space:]')"
  if [ -n "$tsip" ]; then
    origins="$(append_csv_unique "$origins" "https://${tsip}:47990")"
  fi

  if [ -n "$FRP_RELAY_HOST" ]; then
    origins="$(append_csv_unique "$origins" "https://${FRP_RELAY_HOST}:${FRP_REMOTE_PORT_47990}")"
  fi

  printf '%s' "$origins"
}

configure_tailscale_exit_node() {
  [ -n "$TAILSCALE_EXIT_NODE" ] || return 0

  if ! command -v tailscale >/dev/null 2>&1; then
    echo "WARNING: TAILSCALE_EXIT_NODE=${TAILSCALE_EXIT_NODE}, but tailscale is not installed"
    return 0
  fi

  local allow_lan="false"
  local accept_routes="false"
  local up_args=(--exit-node="$TAILSCALE_EXIT_NODE" --ssh=false)

  [ "$TAILSCALE_EXIT_NODE_ALLOW_LAN" = "1" ] && allow_lan="true"
  [ "$TAILSCALE_EXIT_NODE_ACCEPT_ROUTES" = "1" ] && accept_routes="true"

  if [ "$TAILSCALE_EXIT_NODE_ALLOW_LAN" = "1" ]; then
    up_args+=(--exit-node-allow-lan-access)
  fi
  if [ "$TAILSCALE_EXIT_NODE_ACCEPT_ROUTES" = "1" ]; then
    up_args+=(--accept-routes)
  fi

  echo "Setting Tailscale exit node to ${TAILSCALE_EXIT_NODE}"
  if tailscale set \
    --exit-node="$TAILSCALE_EXIT_NODE" \
    --exit-node-allow-lan-access="$allow_lan" \
    --accept-routes="$accept_routes" >/dev/null 2>&1; then
    return 0
  fi

  tailscale up "${up_args[@]}" >/dev/null 2>&1 ||
    echo "WARNING: unable to set Tailscale exit node ${TAILSCALE_EXIT_NODE}"
}

exclude_frp_relay_from_tailscale_exit_node() {
  [ "$TAILSCALE_EXIT_NODE_EXCLUDE_FRP_RELAY" = "1" ] || return 0
  [ "$ENABLE_FRP_SUNSHINE_RELAY" = "1" ] || return 0
  [ -n "$FRP_RELAY_HOST" ] || return 0

  local default_route
  local gw
  local dev
  default_route="$(ip route show table main default 2>/dev/null | awk '$0 !~ /tailscale0/ {print; exit}')"
  [ -n "$default_route" ] || return 0

  gw="$(printf '%s\n' "$default_route" | awk '{for (i=1; i<=NF; i++) if ($i=="via") {print $(i+1); exit}}')"
  dev="$(printf '%s\n' "$default_route" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  [ -n "$dev" ] || return 0

  local ip
  while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    echo "Keeping FRP relay ${ip} off Tailscale exit node via ${dev}${gw:+/${gw}}"
    if [ -n "$gw" ]; then
      ip route replace "${ip}/32" via "$gw" dev "$dev" table 52 2>/dev/null || true
    else
      ip route replace "${ip}/32" dev "$dev" table 52 2>/dev/null || true
    fi
  done < <(resolve_ipv4s "$FRP_RELAY_HOST")
}

install_basics() {
  export DEBIAN_FRONTEND=noninteractive
  local packages=()
  local need_update=0

  add_pkg_if_missing() {
    local binary="$1"
    shift

    if ! command -v "$binary" >/dev/null 2>&1; then
      packages+=("$@")
    fi
  }

  add_file_pkg_if_missing() {
    local path="$1"
    shift

    if [ ! -e "$path" ]; then
      packages+=("$@")
    fi
  }

  add_pkg_if_missing curl ca-certificates curl
  add_pkg_if_missing git git
  add_file_pkg_if_missing /bin/fusermount3 fuse3

  if ! command -v docker >/dev/null 2>&1; then
    packages+=(docker.io containerd)
  fi

  if command -v docker >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    packages+=(docker-compose-plugin)
  fi

  if is_hybrid; then
    add_pkg_if_missing dbus-run-session dbus-x11
    add_pkg_if_missing pactl pulseaudio-utils
    add_pkg_if_missing vulkaninfo vulkan-tools
    add_pkg_if_missing xrandr x11-xserver-utils
    add_pkg_if_missing xdpyinfo x11-utils
    add_pkg_if_missing xinput xinput
    add_pkg_if_missing xinit xinit
    add_pkg_if_missing Xorg xserver-xorg-core
    add_file_pkg_if_missing /usr/lib/xorg/modules/input/evdev_drv.so xserver-xorg-input-evdev
    add_file_pkg_if_missing /usr/lib/xorg/modules/input/libinput_drv.so xserver-xorg-input-libinput

    if [ "$ENABLE_DEBUG_VNC" = "1" ]; then
      add_pkg_if_missing x11vnc x11vnc
    fi
  fi

  if [ "${#packages[@]}" -gt 0 ]; then
    need_update=1
  fi

  if [ "$need_update" = "1" ]; then
    apt-get update
    if ! apt-get install -y --no-install-recommends "${packages[@]}"; then
      if printf '%s\n' "${packages[@]}" | grep -qx docker-compose-plugin; then
        packages=("${packages[@]/docker-compose-plugin/docker-compose}")
        apt-get install -y --no-install-recommends "${packages[@]}"
      else
        return 1
      fi
    fi
  else
    echo "Host packages already available; skipping apt install"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl start docker 2>/dev/null || true
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: docker compose plugin is not available after install."
    exit 1
  fi
}

frp_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l) echo arm ;;
    *)
      echo "ERROR: unsupported FRP architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

install_frp_client() {
  [ "$ENABLE_FRP_SUNSHINE_RELAY" = "1" ] || return 0

  if command -v frpc >/dev/null 2>&1; then
    return 0
  fi

  local arch
  local archive
  local url
  local tmpdir
  arch="$(frp_arch)"
  archive="frp_${FRP_VERSION}_linux_${arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${archive}"
  tmpdir="$(mktemp -d)"

  echo "Installing FRP client ${FRP_VERSION} (${arch})"
  curl -fL --retry 3 --retry-delay 2 -o "${tmpdir}/${archive}" "$url"
  tar -xzf "${tmpdir}/${archive}" -C "$tmpdir"
  install -m 0755 "${tmpdir}/frp_${FRP_VERSION}_linux_${arch}/frpc" /usr/local/bin/frpc
  rm -rf "$tmpdir"
}

write_frp_sunshine_relay_config() {
  [ "$ENABLE_FRP_SUNSHINE_RELAY" = "1" ] || return 0

  local relay_host
  local relay_token
  relay_host="$(printf '%s' "$FRP_RELAY_HOST" | tr -d '\r\n')"
  relay_token="$(printf '%s' "$FRP_TOKEN" | tr -d '\r\n')"

  if [ -z "$relay_host" ] || [ -z "$relay_token" ]; then
    echo "WARNING: ENABLE_FRP_SUNSHINE_RELAY=1 but FRP_RELAY_HOST or FRP_TOKEN is empty; skipping FRP relay"
    return 0
  fi

  mkdir -p "$FRP_CONFIG_DIR"
  chmod 700 "$FRP_CONFIG_DIR" 2>/dev/null || true

  cat >"${FRP_CONFIG_DIR}/frpc-sunshine.env" <<EOF
FRP_TOKEN=${relay_token}
EOF
  chmod 600 "${FRP_CONFIG_DIR}/frpc-sunshine.env"

  cat >"${FRP_CONFIG_DIR}/frpc-sunshine.toml" <<EOF
serverAddr = "${relay_host}"
serverPort = ${FRP_RELAY_PORT}

auth.method = "token"
auth.token = "{{ .Envs.FRP_TOKEN }}"

loginFailExit = false
transport.tcpMux = true

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_47984}-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = 47984
remotePort = ${FRP_REMOTE_PORT_47984}

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_47989}-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = 47989
remotePort = ${FRP_REMOTE_PORT_47989}

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_47990}-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = 47990
remotePort = ${FRP_REMOTE_PORT_47990}

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_48010}-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = 48010
remotePort = ${FRP_REMOTE_PORT_48010}

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_47998}-udp"
type = "udp"
localIP = "127.0.0.1"
localPort = 47998
remotePort = ${FRP_REMOTE_PORT_47998}

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_47999}-udp"
type = "udp"
localIP = "127.0.0.1"
localPort = 47999
remotePort = ${FRP_REMOTE_PORT_47999}

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_48000}-udp"
type = "udp"
localIP = "127.0.0.1"
localPort = 48000
remotePort = ${FRP_REMOTE_PORT_48000}

[[proxies]]
name = "sunshine-${FRP_REMOTE_PORT_48002}-udp"
type = "udp"
localIP = "127.0.0.1"
localPort = 48002
remotePort = ${FRP_REMOTE_PORT_48002}
EOF

  if [ "$START_STEAM_QR_SERVER" = "1" ] && [ "$ENABLE_FRP_STEAM_QR_RELAY" = "1" ]; then
    cat >>"${FRP_CONFIG_DIR}/frpc-sunshine.toml" <<EOF

[[proxies]]
name = "steam-qr-${FRP_REMOTE_PORT_STEAM_QR}-tcp"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${STEAM_QR_PORT}
remotePort = ${FRP_REMOTE_PORT_STEAM_QR}
EOF
  fi

  cat >"/etc/systemd/system/${FRP_SERVICE_NAME}.service" <<EOF
[Unit]
Description=FRP Sunshine reverse relay client
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=${FRP_CONFIG_DIR}/frpc-sunshine.env
ExecStart=/usr/local/bin/frpc -c ${FRP_CONFIG_DIR}/frpc-sunshine.toml
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

start_frp_sunshine_relay() {
  [ "$ENABLE_FRP_SUNSHINE_RELAY" = "1" ] || return 0

  if [ -z "$FRP_RELAY_HOST" ] || [ -z "$FRP_TOKEN" ]; then
    return 0
  fi

  install_frp_client
  write_frp_sunshine_relay_config

  echo "Starting FRP Sunshine relay client to ${FRP_RELAY_HOST}:${FRP_RELAY_PORT}"
  systemctl daemon-reload
  systemctl enable --now "$FRP_SERVICE_NAME"
  systemctl restart "$FRP_SERVICE_NAME"
  sleep 1
  systemctl status "$FRP_SERVICE_NAME" --no-pager || true
}

stop_existing_stacks() {
  [ "$STOP_EXISTING_STACKS" = "1" ] || return 0

  echo "Stopping existing Wolf/Sunshine/Xorg/Steam processes that may conflict"
  systemctl stop "$FRP_SERVICE_NAME" 2>/dev/null || true
  docker rm -f wolf WolfPulseAudio 2>/dev/null || true
  docker ps -a --format '{{.Names}}' | awk '/^Wolf/{print}' | xargs -r docker rm -f 2>/dev/null || true
  pkill sunshine 2>/dev/null || true
  pkill Xorg 2>/dev/null || true
  pkill openbox 2>/dev/null || true
  pkill x11vnc 2>/dev/null || true
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

detect_nvidia_xorg_bus_id() {
  if [ -n "$HOST_XORG_BUS_ID" ]; then
    echo "$HOST_XORG_BUS_ID"
    return 0
  fi

  local pci=""
  pci="$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
  if [ -n "$pci" ]; then
    local bus_hex dev_func dev_hex func_hex
    bus_hex="$(printf '%s\n' "$pci" | awk -F: '{print $2}')"
    dev_func="$(printf '%s\n' "$pci" | awk -F: '{print $3}')"
    dev_hex="${dev_func%%.*}"
    func_hex="${dev_func##*.}"
    echo "PCI:$((16#$bus_hex)):$((16#$dev_hex)):$((16#$func_hex))"
    return 0
  fi

  echo "PCI:53:0:0"
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

restore_steam_session() {
  [ "$RESTORE_STEAM_SESSION" = "1" ] || return 0
  [ -f "$STEAM_SESSION_ARCHIVE" ] || return 0

  echo "Restoring Steam session archive into Steam Headless home"
  tar -xzf "$STEAM_SESSION_ARCHIVE" -C "${DATA_DIR}/home"
  chown -R "${PUID}:${PGID}" "${DATA_DIR}/home" 2>/dev/null || true
}

restore_sunshine_state() {
  [ -d "$SUNSHINE_STATE_SOURCE_DIR" ] || return 0

  local target="${DATA_DIR}/home/.config/sunshine"
  local file

  echo "Restoring Sunshine state from ${SUNSHINE_STATE_SOURCE_DIR}"
  mkdir -p "$target"

  for file in sunshine_state.json cacert.pem cakey.pem H; do
    if [ -f "${SUNSHINE_STATE_SOURCE_DIR}/${file}" ]; then
      cp "${SUNSHINE_STATE_SOURCE_DIR}/${file}" "${target}/${file}"
    fi
  done

  chown -R "${PUID}:${PGID}" "$target" 2>/dev/null || true
  chmod 700 "$target" 2>/dev/null || true
  chmod 600 "$target"/sunshine_state.json "$target"/cacert.pem "$target"/cakey.pem "$target"/H 2>/dev/null || true
}

write_env_file() {
  local version="$1"
  local env_file="${SERVICE_DIR}/.env"
  local mode="primary"
  local web_ui_mode="vnc"
  local enable_vnc_audio="true"
  local enable_steam="true"
  local enable_sunshine="true"
  local display="$CONTAINER_DISPLAY"
  local force_dummy="$FORCE_X11_DUMMY_CONFIG"

  if is_hybrid; then
    mode="secondary"
    web_ui_mode="none"
    enable_vnc_audio="false"
    enable_steam="false"
    enable_sunshine="false"
    display="$HOST_DISPLAY"
    force_dummy="false"
  fi

  if [ -f "$env_file" ]; then
    cp "$env_file" "${env_file}.bak.$(date +%s)"
  fi

  cat >"$env_file" <<EOF
NAME=${CONTAINER_NAME}
TZ=${TZ}
USER_LOCALES=en_US.UTF-8 UTF-8
DISPLAY=${display}
SHM_SIZE=${SHM_SIZE}
HOME_DIR=${DATA_DIR}/home
SHARED_SOCKETS_DIR=${DATA_DIR}/sockets
GAMES_DIR=${GAMES_DIR}

PUID=${PUID}
PGID=${PGID}
UMASK=000
USER_PASSWORD=${USER_PASSWORD}

MODE=${mode}

WEB_UI_MODE=${web_ui_mode}
ENABLE_VNC_AUDIO=${enable_vnc_audio}
PORT_NOVNC_WEB=${PORT_NOVNC_WEB}
NEKO_NAT1TO1=

ENABLE_STEAM=${enable_steam}
STEAM_ARGS=-silent

ENABLE_SUNSHINE=${enable_sunshine}
SUNSHINE_USER=${SUNSHINE_USER}
SUNSHINE_PASS=${SUNSHINE_PASS}

ENABLE_EVDEV_INPUTS=true
FORCE_X11_DUMMY_CONFIG=${force_dummy}
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
  local x11_source='${SHARED_SOCKETS_DIR}/.X11-unix/'

  if is_hybrid; then
    x11_source='/tmp/.X11-unix/'
  fi

  if [ -f "$compose_file" ]; then
    cp "$compose_file" "${compose_file}.bak.$(date +%s)"
  fi

  cat >"$compose_file" <<EOF
services:
  steam-headless:
    image: \${STEAM_HEADLESS_IMAGE:-josh5/steam-headless:latest}
    container_name: \${NAME}
    restart: unless-stopped
    shm_size: \${SHM_SIZE}
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
    hostname: \${NAME}
    extra_hosts:
      - "\${NAME}:127.0.0.1"
    environment:
      - TZ=\${TZ}
      - USER_LOCALES=\${USER_LOCALES}
      - DISPLAY=\${DISPLAY}
      - DISPLAY_SIZEW=\${DISPLAY_SIZEW}
      - DISPLAY_SIZEH=\${DISPLAY_SIZEH}
      - DISPLAY_REFRESH=\${DISPLAY_REFRESH}
      - DISPLAY_CDEPTH=\${DISPLAY_CDEPTH}
      - DISPLAY_VIDEO_PORT=\${DISPLAY_VIDEO_PORT}
      - PUID=\${PUID}
      - PGID=\${PGID}
      - UMASK=\${UMASK}
      - USER_PASSWORD=\${USER_PASSWORD}
      - MODE=\${MODE}
      - WEB_UI_MODE=\${WEB_UI_MODE}
      - ENABLE_VNC_AUDIO=\${ENABLE_VNC_AUDIO}
      - PORT_NOVNC_WEB=\${PORT_NOVNC_WEB}
      - NEKO_NAT1TO1=\${NEKO_NAT1TO1}
      - ENABLE_STEAM=\${ENABLE_STEAM}
      - STEAM_ARGS=\${STEAM_ARGS}
      - ENABLE_SUNSHINE=\${ENABLE_SUNSHINE}
      - SUNSHINE_USER=\${SUNSHINE_USER}
      - SUNSHINE_PASS=\${SUNSHINE_PASS}
      - ENABLE_EVDEV_INPUTS=\${ENABLE_EVDEV_INPUTS}
      - FORCE_X11_DUMMY_CONFIG=\${FORCE_X11_DUMMY_CONFIG}
      - NVIDIA_DRIVER_CAPABILITIES=\${NVIDIA_DRIVER_CAPABILITIES}
      - NVIDIA_VISIBLE_DEVICES=\${NVIDIA_VISIBLE_DEVICES}
      - NVIDIA_DRIVER_VERSION=\${NVIDIA_DRIVER_VERSION}
    devices:
      - /dev/fuse
      - /dev/uinput
    device_cgroup_rules:
      - 'c 13:* rmw'
    volumes:
      - \${HOME_DIR}/:/home/default/:rw
      - \${GAMES_DIR}/:/mnt/games/:rw
      - ${x11_source}:/tmp/.X11-unix/:rw
      - \${SHARED_SOCKETS_DIR}/pulse/:/tmp/pulse/:rw
EOF
}

prepare_dirs() {
  mkdir -p \
    "$SERVICE_DIR" \
    "${DATA_DIR}/home/Downloads" \
    "${DATA_DIR}/sockets/.X11-unix" \
    "${DATA_DIR}/sockets/pulse" \
    "$GAMES_DIR" \
    "$LOG_DIR" \
    /tmp/.X11-unix \
    /etc/X11/xorg.conf.d

  chmod 1777 "${DATA_DIR}/sockets/.X11-unix" /tmp/.X11-unix 2>/dev/null || true
  chown -R "${PUID}:${PGID}" "${DATA_DIR}/home" "$GAMES_DIR" 2>/dev/null || true

  prepare_local_steam_library
}

write_host_input_config() {
  is_hybrid || return 0

  cat >/etc/X11/xorg.conf.d/10-evdev-sunshine.conf <<'EOF'
Section "InputClass"
    Identifier "Sunshine keyboard"
    MatchProduct "Keyboard passthrough"
    Driver "evdev"
EndSection

Section "InputClass"
    Identifier "Sunshine mouse"
    MatchProduct "Mouse passthrough"
    Driver "evdev"
    Option "AccelerationScheme" "none"
    Option "AccelerationNumerator" "1"
    Option "AccelerationDenominator" "1"
    Option "AccelerationThreshold" "0"
EndSection

Section "InputClass"
    Identifier "Sunshine touch and pen"
    MatchProduct "Touch passthrough|Pen passthrough"
    Driver "evdev"
EndSection
EOF
}

make_modeline() {
  local width="$1"
  local height="$2"
  local refresh="$3"
  local modeline=""

  if command -v cvt >/dev/null 2>&1; then
    modeline="$(cvt "$width" "$height" "$refresh" | awk -F'Modeline ' '/Modeline/{print $2; exit}' || true)"
  fi

  if [ -z "$modeline" ] && command -v gtf >/dev/null 2>&1; then
    modeline="$(gtf "$width" "$height" "$refresh" | awk -F'Modeline ' '/Modeline/{print $2; exit}' || true)"
  fi

  echo "$modeline"
}

write_host_xorg_config() {
  is_hybrid || return 0

  local bus_id
  local modeline
  local mode_name
  bus_id="$(detect_nvidia_xorg_bus_id)"
  modeline="$(make_modeline "$DISPLAY_SIZEW" "$DISPLAY_SIZEH" "$DISPLAY_REFRESH")"

  if [ -n "$modeline" ]; then
    mode_name="$(printf '%s\n' "$modeline" | awk '{print $1}' | tr -d '"')"
  else
    mode_name="${DISPLAY_SIZEW}x${DISPLAY_SIZEH}"
  fi

  echo "Writing host Xorg config ${HOST_XORG_CONFIG} with ${bus_id}, mode ${mode_name}"

  cp "$HOST_XORG_CONFIG" "${HOST_XORG_CONFIG}.bak.$(date +%s)" 2>/dev/null || true

  cat >"$HOST_XORG_CONFIG" <<EOF
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0" 0 0
EndSection

Section "Device"
    Identifier "Device0"
    Driver "nvidia"
    BusID "${bus_id}"
    Option "AllowEmptyInitialConfiguration" "True"
    Option "UseDisplayDevice" "${HOST_XORG_CONNECTED_MONITOR}"
    Option "ConnectedMonitor" "${HOST_XORG_CONNECTED_MONITOR}"
    Option "ModeValidation" "NoMaxPClkCheck, NoEdidMaxPClkCheck, NoHorizSyncCheck, NoVertRefreshCheck, NoMaxSizeCheck, NoVirtualSizeCheck"
EndSection

Section "Monitor"
    Identifier "Monitor0"
    HorizSync 30.0 - 255.0
    VertRefresh 24.0 - 240.0
EOF

  if [ -n "$modeline" ]; then
    printf '    Modeline %s\n' "$modeline" >>"$HOST_XORG_CONFIG"
    printf '    Option "PreferredMode" "%s"\n' "$mode_name" >>"$HOST_XORG_CONFIG"
  fi

  cat >>"$HOST_XORG_CONFIG" <<EOF
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Device0"
    Monitor "Monitor0"
    DefaultDepth ${DISPLAY_CDEPTH}
    Option "MetaModes" "${HOST_XORG_CONNECTED_MONITOR}: ${mode_name}"
    SubSection "Display"
        Depth ${DISPLAY_CDEPTH}
        Modes "${mode_name}" "${DISPLAY_SIZEW}x${DISPLAY_SIZEH}"
        Virtual ${DISPLAY_SIZEW} ${DISPLAY_SIZEH}
    EndSubSection
EndSection
EOF
}

start_host_xorg() {
  is_hybrid || return 0
  [ "$START_HOST_XORG" = "1" ] || return 0

  mkdir -p "$LOG_DIR" /tmp/.X11-unix
  chmod 1777 /tmp/.X11-unix 2>/dev/null || true

  pkill Xorg 2>/dev/null || true
  sleep 2

  echo "Starting host Xorg ${HOST_DISPLAY}"
  Xorg "$HOST_DISPLAY" -config "$HOST_XORG_CONFIG" -noreset -nolisten tcp >"$HOST_XORG_LOG" 2>&1 &

  local socket="/tmp/.X11-unix/X${HOST_DISPLAY#:}"
  for _ in $(seq 1 30); do
    [ -S "$socket" ] && break
    sleep 1
  done

  if [ ! -S "$socket" ]; then
    echo "ERROR: host Xorg socket did not appear: ${socket}"
    tail -160 "$HOST_XORG_LOG" || true
    exit 1
  fi

  DISPLAY="$HOST_DISPLAY" xhost +local:root +local:default >/dev/null 2>&1 || true
  apply_host_resolution || true
  verify_host_vulkan || true
}

apply_host_resolution() {
  is_hybrid || return 0

  local output="$HOST_XORG_OUTPUT"
  if [ -z "$output" ]; then
    output="$(DISPLAY="$HOST_DISPLAY" xrandr --query | awk '/ connected/{print $1; exit}' || true)"
  fi
  [ -n "$output" ] || return 0

  echo "Host Xorg output: ${output}"

  local modeline
  local mode_name
  modeline="$(make_modeline "$DISPLAY_SIZEW" "$DISPLAY_SIZEH" "$DISPLAY_REFRESH")"
  mode_name="$(printf '%s\n' "$modeline" | awk '{print $1}' | tr -d '"')"

  if [ -n "$modeline" ] && [ -n "$mode_name" ]; then
    DISPLAY="$HOST_DISPLAY" xrandr --newmode $modeline 2>/dev/null || true
    DISPLAY="$HOST_DISPLAY" xrandr --addmode "$output" "$mode_name" 2>/dev/null || true
    DISPLAY="$HOST_DISPLAY" xrandr --output "$output" --mode "$mode_name" 2>/dev/null || true
  fi

  DISPLAY="$HOST_DISPLAY" xrandr --output "$output" --mode "${DISPLAY_SIZEW}x${DISPLAY_SIZEH}" --rate "$DISPLAY_REFRESH" 2>/dev/null || true
  DISPLAY="$HOST_DISPLAY" xrandr --query | sed -n '1,45p' || true
}

verify_host_vulkan() {
  is_hybrid || return 0
  [ "$VERIFY_HOST_VULKAN" = "1" ] || return 0

  echo "Checking host Vulkan surface on ${HOST_DISPLAY}"
  DISPLAY="$HOST_DISPLAY" vulkaninfo --summary 2>&1 \
    | grep -Ei 'ERROR|deviceName|driverInfo|NVIDIA|surface|present' -A2 -B2 || true
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

wait_for_container() {
  echo "Waiting for ${CONTAINER_NAME} to accept docker exec"
  for _ in $(seq 1 90); do
    if timeout 5 docker exec "$CONTAINER_NAME" true >/dev/null 2>&1; then
      echo "${CONTAINER_NAME} accepts docker exec"
      return 0
    fi
    sleep 1
  done

  echo "ERROR: container did not become ready: ${CONTAINER_NAME}"
  docker ps -a
  exit 1
}

wait_for_supervisor() {
  echo "Waiting for supervisord inside ${CONTAINER_NAME}"
  for _ in $(seq 1 "$WAIT_FOR_SUPERVISOR_SECONDS"); do
    if timeout 2 docker exec "$CONTAINER_NAME" supervisorctl pid >/dev/null 2>&1; then
      echo "supervisord is ready"
      return 0
    fi
    if docker logs --tail=80 "$CONTAINER_NAME" 2>/dev/null | grep -q 'supervisord started with pid'; then
      echo "supervisord is ready according to container logs"
      return 0
    fi
    sleep 1
  done

  echo "WARNING: supervisorctl did not become ready in ${CONTAINER_NAME} after ${WAIT_FOR_SUPERVISOR_SECONDS}s; continuing with best-effort hybrid startup"
  docker logs --tail=40 "$CONTAINER_NAME" || true
}

patch_udev_xorg_restart_loop() {
  [ "$PATCH_UDEV_XORG_RESTART_LOOP" = "1" ] || return 0

  echo "Patching Steam Headless udev Xorg restart-loop workaround"

  if ! docker exec "$CONTAINER_NAME" test -f /usr/bin/start-dumb-udev.sh >/dev/null 2>&1; then
    echo "WARNING: /usr/bin/start-dumb-udev.sh not found in ${CONTAINER_NAME}; skipping patch"
    return 0
  fi

  timeout 20 docker exec "$CONTAINER_NAME" bash -lc '
set -e
if grep -q "supervisorctl restart xorg" /usr/bin/start-dumb-udev.sh; then
  cp -n /usr/bin/start-dumb-udev.sh /usr/bin/start-dumb-udev.sh.orig 2>/dev/null || true
  sed -i "s|supervisorctl restart xorg|true # disabled by machine-dev Steam Headless launcher|" /usr/bin/start-dumb-udev.sh
fi
supervisorctl restart udev >/dev/null 2>&1 || pkill -f start-dumb-udev.sh 2>/dev/null || true
' || echo "WARNING: udev Xorg restart-loop patch timed out or failed; continuing"
}

stop_supervisor_desktop_services() {
  is_hybrid || return 0

  echo "Stopping container-managed desktop services for hybrid mode"

  docker exec "$CONTAINER_NAME" bash -lc '
supervisorctl stop steam sunshine xorg xvfb desktop x11vnc audiostream frontend neko vnc vnc-audio accounts-daemon polkit >/dev/null 2>&1 || true
true
'
}

container_exec_default_detached() {
  docker exec \
    -u default \
    -e DISPLAY="$HOST_DISPLAY" \
    -e PULSE_SERVER="unix:${PULSE_SERVER_PATH}" \
    -e SDL_AUDIODRIVER="pulseaudio" \
    -e PULSE_LATENCY_MSEC="60" \
    -e STEAM_COMPAT_MOUNTS="$STEAM_COMPAT_MOUNTS" \
    -e PROTON_LOG="$ENABLE_PROTON_LOGS" \
    -e PROTON_LOG_DIR="/home/default" \
    -e XDG_RUNTIME_DIR="/tmp/.X11-unix/run" \
    -e BROWSER="/usr/bin/x-www-browser" \
    -d "$CONTAINER_NAME" \
    bash -lc "$1"
}

wait_for_pulse() {
  is_hybrid || return 0

  for _ in $(seq 1 "$WAIT_FOR_PULSE_SECONDS"); do
    if timeout 2 docker exec -u default -e PULSE_SERVER="unix:${PULSE_SERVER_PATH}" "$CONTAINER_NAME" pactl info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "WARNING: PulseAudio did not answer on ${PULSE_SERVER_PATH}"
  docker exec "$CONTAINER_NAME" bash -lc 'find /tmp /run /home/default -maxdepth 4 -type s 2>/dev/null | grep -Ei "pulse|native|audio" || true'
}

install_container_runtime_packages() {
  if [ "$INSTALL_CONTAINER_BROWSER" != "1" ] && [ "$INSTALL_CONTAINER_STEAM_DEPS" != "1" ]; then
    return 0
  fi

  echo "Ensuring container runtime packages are installed inside ${CONTAINER_NAME}"
  timeout 420 docker exec "$CONTAINER_NAME" bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive

browser_ready=0
if command -v firefox >/dev/null 2>&1 ||
  command -v firefox-esr >/dev/null 2>&1 ||
  command -v chromium >/dev/null 2>&1; then
  browser_ready=1
fi

steam_deps_ready=0
steam_deps_missing=0
for pkg in \
  libc6:i386 libcurl4t64:i386 libvulkan1:i386 libpulse0:i386 \
  libnss3:i386 libgl1:i386 libx11-6:i386 libstdc++6:i386; do
  if ! dpkg-query -W -f="\${Status}" "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    steam_deps_missing=1
    break
  fi
done
if [ "$steam_deps_missing" = "0" ]; then
  steam_deps_ready=1
fi

if { [ "'"$INSTALL_CONTAINER_BROWSER"'" != "1" ] || [ "$browser_ready" = "1" ]; } &&
  { [ "'"$INSTALL_CONTAINER_STEAM_DEPS"'" != "1" ] || [ "$steam_deps_ready" = "1" ]; }; then
  exit 0
fi

if [ "'"$INSTALL_CONTAINER_STEAM_DEPS"'" = "1" ]; then
  dpkg --add-architecture i386 2>/dev/null || true
fi

apt-get update

if [ "'"$INSTALL_CONTAINER_STEAM_DEPS"'" = "1" ]; then
  pick_pkg() {
    for pkg in "$@"; do
      if apt-cache show "$pkg" >/dev/null 2>&1; then
        printf "%s\n" "$pkg"
        return 0
      fi
    done
    return 1
  }
  asound_pkg="$(pick_pkg libasound2t64:i386 libasound2:i386 || printf "libasound2:i386")"
  curl_pkg="$(pick_pkg libcurl4t64:i386 libcurl4:i386 || printf "libcurl4:i386")"
  apt-get install -y --no-install-recommends \
    ca-certificates curl file xdg-user-dirs xdg-utils \
    "$asound_pkg" libc6:i386 "$curl_pkg" libdbus-1-3:i386 \
    libdrm2:i386 libegl1:i386 libgbm1:i386 libgcc-s1:i386 libgl1:i386 \
    libglvnd0:i386 libglx0:i386 libnm0:i386 libnss3:i386 libpulse0:i386 \
    libstdc++6:i386 libudev1:i386 libvulkan1:i386 libx11-6:i386 \
    libxcb-dri3-0:i386 libxcb1:i386 libxcomposite1:i386 libxdamage1:i386 \
    libxext6:i386 libxfixes3:i386 libxrandr2:i386 libxrender1:i386 \
    libxtst6:i386

  if command -v steamdeps >/dev/null 2>&1; then
    yes y | steamdeps >/tmp/machine-dev-steamdeps.log 2>&1 || true
  elif [ -x /usr/lib/steam/steamdeps ]; then
    yes y | /usr/lib/steam/steamdeps >/tmp/machine-dev-steamdeps.log 2>&1 || true
  fi
fi

if [ "'"$INSTALL_CONTAINER_BROWSER"'" = "1" ] &&
  ! command -v firefox >/dev/null 2>&1 &&
  ! command -v firefox-esr >/dev/null 2>&1 &&
  ! command -v chromium >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends xdotool firefox-esr ||
    apt-get install -y --no-install-recommends xdotool chromium
fi
' || echo "WARNING: container runtime package install inside ${CONTAINER_NAME} failed or timed out"
}

configure_container_default_browser() {
  is_hybrid || return 0
  [ "$INSTALL_CONTAINER_BROWSER" = "1" ] || return 0

  echo "Configuring default browser inside ${CONTAINER_NAME}"
  docker exec "$CONTAINER_NAME" bash -lc '
set -e

browser_bin=""
browser_desktop=""
if command -v firefox-esr >/dev/null 2>&1; then
  browser_bin="$(command -v firefox-esr)"
  browser_desktop="firefox-esr.desktop"
elif command -v firefox >/dev/null 2>&1; then
  browser_bin="$(command -v firefox)"
  browser_desktop="firefox.desktop"
elif command -v chromium >/dev/null 2>&1; then
  browser_bin="$(command -v chromium)"
  browser_desktop="chromium.desktop"
fi

[ -n "$browser_bin" ] || exit 0

update-alternatives --set x-www-browser "$browser_bin" >/dev/null 2>&1 || true
update-alternatives --set gnome-www-browser "$browser_bin" >/dev/null 2>&1 || true

su - default -s /bin/bash -c "
set -e
mkdir -p ~/.config ~/.local/share/applications
cat >~/.config/mimeapps.list <<EOF
[Default Applications]
text/html=${browser_desktop}
x-scheme-handler/http=${browser_desktop}
x-scheme-handler/https=${browser_desktop}
x-scheme-handler/about=${browser_desktop}
x-scheme-handler/unknown=${browser_desktop}
EOF
ln -sf ~/.config/mimeapps.list ~/.local/share/applications/mimeapps.list
xdg-settings set default-web-browser ${browser_desktop} >/dev/null 2>&1 || true
"
'
}

install_container_steam_qr_server() {
  is_hybrid || return 0
  [ "$START_STEAM_QR_SERVER" = "1" ] || return 0

  if [ ! -f "$STEAM_QR_SERVER_SOURCE" ]; then
    echo "WARNING: Steam QR server source not found: ${STEAM_QR_SERVER_SOURCE}"
    return 0
  fi

  echo "Installing Steam QR server inside ${CONTAINER_NAME}"
  docker exec "$CONTAINER_NAME" mkdir -p /opt/machine-dev
  docker cp "$STEAM_QR_SERVER_SOURCE" "${CONTAINER_NAME}:/opt/machine-dev/steam_qr_server.py"
  docker exec "$CONTAINER_NAME" chmod 755 /opt/machine-dev/steam_qr_server.py

  if docker exec "$CONTAINER_NAME" test -x "$STEAM_QR_PYTHON" >/dev/null 2>&1; then
    return 0
  fi

  timeout 420 docker exec "$CONTAINER_NAME" bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive

if ! command -v python3 >/dev/null 2>&1 || ! python3 -m venv --help >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates python3 python3-pip python3-venv
fi

python3 -m venv /opt/machine-dev/qr-venv
/opt/machine-dev/qr-venv/bin/pip install --no-cache-dir \
  flask \
  mss \
  numpy \
  opencv-python-headless \
  pillow
' || echo "WARNING: Steam QR server dependency install failed or timed out"
}

start_steam_qr_server() {
  is_hybrid || return 0
  [ "$START_STEAM_QR_SERVER" = "1" ] || return 0

  if ! docker exec "$CONTAINER_NAME" test -f /opt/machine-dev/steam_qr_server.py >/dev/null 2>&1; then
    echo "WARNING: Steam QR server is not installed in ${CONTAINER_NAME}"
    return 0
  fi

  echo "Starting Steam QR server on ${STEAM_QR_HOST}:${STEAM_QR_PORT}"
  docker exec "$CONTAINER_NAME" bash -lc 'pkill -u default -f steam_qr_server.py 2>/dev/null || true'
  docker exec \
    -u default \
    -e DISPLAY="$HOST_DISPLAY" \
    -e QR_HOST="$STEAM_QR_HOST" \
    -e QR_PORT="$STEAM_QR_PORT" \
    -e QR_CROP="$STEAM_QR_CROP" \
    -e QR_TOKEN="$STEAM_QR_TOKEN" \
    -e PYTHONUNBUFFERED=1 \
    -d "$CONTAINER_NAME" \
    bash -lc '
mkdir -p /home/default/.cache/log
python_bin="/opt/machine-dev/qr-venv/bin/python"
if [ ! -x "$python_bin" ]; then
  python_bin="$(command -v python3 || true)"
fi
if [ -z "$python_bin" ]; then
  echo "python3 not available for Steam QR server"
  exit 1
fi
exec "$python_bin" /opt/machine-dev/steam_qr_server.py >/home/default/.cache/log/steam-qr-server.log 2>&1
'
}

set_mouse_passthrough_accel() {
  is_hybrid || return 0
  [ -n "$MOUSE_PASSTHROUGH_ACCEL" ] || return 0
  command -v xinput >/dev/null 2>&1 || return 0

  local ids
  ids="$(DISPLAY="$HOST_DISPLAY" xinput list --id-only 'Mouse passthrough' 2>/dev/null || true)"
  [ -n "$ids" ] || return 0

  printf '%s\n' "$ids" | while read -r id; do
    [ -n "$id" ] || continue
    DISPLAY="$HOST_DISPLAY" xinput set-prop "$id" 'libinput Accel Speed' "$MOUSE_PASSTHROUGH_ACCEL" 2>/dev/null || true
    DISPLAY="$HOST_DISPLAY" xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 2>/dev/null || true
    DISPLAY="$HOST_DISPLAY" xinput set-prop "$id" 'Device Accel Constant Deceleration' 1 2>/dev/null || true
    DISPLAY="$HOST_DISPLAY" xinput set-prop "$id" 'Device Accel Velocity Scaling' "$MOUSE_PASSTHROUGH_ACCEL" 2>/dev/null || true
  done
}

start_hybrid_container_services() {
  is_hybrid || return 0

  echo "Starting container XFCE/Sunshine/Steam on host Xorg ${HOST_DISPLAY}"
  mkdir -p "$LOG_DIR"
  printf '%s\n' "hybrid post-start begin $(date -Is)" >"${LOG_DIR}/hybrid-post-start.log"

  docker exec "$CONTAINER_NAME" bash -lc 'supervisorctl restart pulseaudio >/dev/null 2>&1 || true'
  wait_for_pulse
  printf '%s\n' "pulse ready/checked $(date -Is)" >>"${LOG_DIR}/hybrid-post-start.log"

  if [ "$START_CONTAINER_XFCE" = "1" ]; then
    docker exec "$CONTAINER_NAME" bash -lc 'pkill -u default -f "xfce4|xfwm4|xfdesktop|xfce4-panel" 2>/dev/null || true'
    container_exec_default_detached '
mkdir -p /home/default/.cache/log /tmp/.X11-unix/run
dbus-run-session startxfce4 >/home/default/.cache/log/xfce-hostx.log 2>&1
'
    printf '%s\n' "xfce launched $(date -Is)" >>"${LOG_DIR}/hybrid-post-start.log"
  fi
  set_mouse_passthrough_accel

  if [ "$START_CONTAINER_SUNSHINE" = "1" ]; then
    local csrf_allowed_origins
    csrf_allowed_origins="$(sunshine_csrf_allowed_origins)"
    docker exec "$CONTAINER_NAME" bash -lc 'pkill -u default -f sunshine 2>/dev/null || true'
    docker exec -u default "$CONTAINER_NAME" bash -lc "sunshine --creds '${SUNSHINE_USER}' '${SUNSHINE_PASS}' >/dev/null 2>&1 || true"
    docker exec -u default -e SUNSHINE_CSRF_ALLOWED_ORIGINS="$csrf_allowed_origins" "$CONTAINER_NAME" bash -lc '
CONF=/home/default/.config/sunshine/sunshine.conf
mkdir -p "$(dirname "$CONF")"
touch "$CONF"
set_conf() {
  key="$1"
  value="$2"
  if grep -q "^${key}" "$CONF"; then
    sed -i "s|^${key}.*|${key} = ${value}|" "$CONF"
  else
    printf "\n%s = %s\n" "$key" "$value" >>"$CONF"
  fi
}
set_conf audio_sink sink-sunshine-stereo
set_conf csrf_allowed_origins "$SUNSHINE_CSRF_ALLOWED_ORIGINS"
set_conf file_state /home/default/.config/sunshine/sunshine_state.json
set_conf cert /home/default/.config/sunshine/cacert.pem
set_conf pkey /home/default/.config/sunshine/cakey.pem
'
    container_exec_default_detached '
mkdir -p /home/default/.cache/log
sunshine >/home/default/.cache/log/sunshine-hostx.log 2>&1
'
    printf '%s\n' "sunshine launched $(date -Is)" >>"${LOG_DIR}/hybrid-post-start.log"

    for _ in $(seq 1 20); do
      if docker exec -u default -e PULSE_SERVER="unix:${PULSE_SERVER_PATH}" "$CONTAINER_NAME" pactl list short sinks 2>/dev/null | grep -q '^.*sink-sunshine-stereo'; then
        break
      fi
      sleep 1
    done
  fi

  docker exec -u default -e PULSE_SERVER="unix:${PULSE_SERVER_PATH}" "$CONTAINER_NAME" bash -lc '
pactl set-default-sink sink-sunshine-stereo 2>/dev/null || pactl set-default-sink auto_null 2>/dev/null || true
pactl set-default-source sink-sunshine-stereo.monitor 2>/dev/null || pactl set-default-source auto_null.monitor 2>/dev/null || true
'
  docker exec -u default -e PULSE_SERVER="unix:${PULSE_SERVER_PATH}" "$CONTAINER_NAME" bash -lc '
echo "==== pulse after sunshine ===="
pactl info 2>/dev/null | grep -E "Server String|Default Sink|Default Source" || true
pactl list short sinks 2>/dev/null || true
pactl list short sources 2>/dev/null || true
' >>"${LOG_DIR}/hybrid-post-start.log" 2>&1 || true

  docker exec -u default "$CONTAINER_NAME" bash -lc "
echo '==== steam library mount probes ===='
echo STEAM_COMPAT_MOUNTS='${STEAM_COMPAT_MOUNTS}'
d=/mnt/games
echo \"-- \$d\"
stat -c '%U:%G %a %F %n' \"\$d\" 2>/dev/null || true
df -h \"\$d\" 2>/dev/null || true
mkdir -p \"\$d/SteamLibrary\" 2>/dev/null || true
touch \"\$d/SteamLibrary/.machine-dev-write-test\" 2>/dev/null && rm -f \"\$d/SteamLibrary/.machine-dev-write-test\" && echo WRITE_OK || echo WRITE_FAIL
" >>"${LOG_DIR}/hybrid-post-start.log" 2>&1 || true

  if [ "$START_CONTAINER_STEAM" = "1" ]; then
    docker exec "$CONTAINER_NAME" bash -lc 'chown -R default:default /home/default/.steam /home/default/.local /home/default/.cache 2>/dev/null || true'
    docker exec "$CONTAINER_NAME" bash -lc 'pkill -9 -u default -f "steam|steamwebhelper" 2>/dev/null || true'
    container_exec_default_detached '
mkdir -p /home/default/.cache/log
pactl set-default-sink sink-sunshine-stereo 2>/dev/null || true
pactl set-default-source sink-sunshine-stereo.monitor 2>/dev/null || true
export PULSE_SINK=sink-sunshine-stereo
export GTK_A11Y=none
if [ "'"$STEAM_SKIP_PACKAGE_CHECK"'" = "1" ]; then
  export STEAM_SKIP_PACKAGE_CHECK=1
else
  unset STEAM_SKIP_PACKAGE_CHECK
fi
echo "PULSE_SERVER=${PULSE_SERVER}" >/home/default/.cache/log/steam-hostx-env.log
echo "PULSE_SINK=${PULSE_SINK}" >>/home/default/.cache/log/steam-hostx-env.log
echo "STEAM_COMPAT_MOUNTS=${STEAM_COMPAT_MOUNTS}" >>/home/default/.cache/log/steam-hostx-env.log
echo "STEAM_SKIP_PACKAGE_CHECK=${STEAM_SKIP_PACKAGE_CHECK:-<unset>}" >>/home/default/.cache/log/steam-hostx-env.log
echo "GTK_A11Y=${GTK_A11Y}" >>/home/default/.cache/log/steam-hostx-env.log
if [ "'"$AUTO_ACCEPT_STEAM_INSTALLER"'" = "1" ]; then
  mkdir -p /tmp/machine-dev-steam-bin
  printf "%s\n" "#!/usr/bin/env sh" "exit 0" >/tmp/machine-dev-steam-bin/zenity
  printf "%s\n" "#!/usr/bin/env sh" "exit 0" >/tmp/machine-dev-steam-bin/yad
  chmod +x /tmp/machine-dev-steam-bin/zenity /tmp/machine-dev-steam-bin/yad
  export PATH="/tmp/machine-dev-steam-bin:${PATH}"
  echo "AUTO_ACCEPT_STEAM_INSTALLER=1" >>/home/default/.cache/log/steam-hostx-env.log
fi
if [ "'"$AUTO_CLICK_STEAM_INSTALL"'" = "1" ] && command -v xdotool >/dev/null 2>&1; then
  (
    for _ in $(seq 1 45); do
      if pgrep -u default -f steamwebhelper >/dev/null 2>&1 &&
        xdotool search --onlyvisible --class steam >/dev/null 2>&1; then
        echo "$(date -Is) Steam UI is visible; stopping installer autoclick"
        exit 0
      fi

      for win in $(xdotool search --onlyvisible --name "Install Steam" 2>/dev/null; xdotool search --onlyvisible --name "Steam Setup" 2>/dev/null; xdotool search --onlyvisible --name "Steam - Self Updater" 2>/dev/null; xdotool search --onlyvisible --name "Question" 2>/dev/null; xdotool search --onlyvisible --name "Warning" 2>/dev/null; xdotool search --onlyvisible --class "zenity" 2>/dev/null); do
        name="$(xdotool getwindowname "$win" 2>/dev/null || true)"
        [ -n "$name" ] && printf "%s %s\n" "$(date -Is)" "$name"
        case "$name" in
          *"Install Steam"*|*"Steam Setup"*|*"Steam - Self Updater"*|*"Question"*|*"Warning"*)
            xdotool windowactivate --sync "$win" key --clearmodifiers Return 2>/dev/null || true
            ;;
        esac
      done
      sleep 1
    done
  ) >/home/default/.cache/log/steam-install-autoclick.log 2>&1 &
fi
steam -silent >/home/default/.cache/log/steam-hostx.log 2>&1
'
    printf '%s\n' "steam launched $(date -Is)" >>"${LOG_DIR}/hybrid-post-start.log"
  fi

  docker exec "$CONTAINER_NAME" bash -lc '
echo "==== supervisor selected ===="
supervisorctl status steam sunshine xorg desktop x11vnc audiostream frontend accounts-daemon polkit 2>/dev/null || true
echo "==== manual procs ===="
pgrep -a "sunshine|steam|xfce|xfwm|xfdesktop" || true
' >>"${LOG_DIR}/hybrid-post-start.log" 2>&1 || true

  printf '%s\n' "hybrid post-start done $(date -Is)" >>"${LOG_DIR}/hybrid-post-start.log"
}

start_debug_vnc() {
  is_hybrid || return 0
  [ "$ENABLE_DEBUG_VNC" = "1" ] || return 0
  command -v x11vnc >/dev/null 2>&1 || return 0

  pkill x11vnc 2>/dev/null || true
  x11vnc -display "$HOST_DISPLAY" -forever -shared -nopw -listen 0.0.0.0 -rfbport "$HOST_VNC_PORT" >"${LOG_DIR}/x11vnc-99.log" 2>&1 &
}

print_status() {
  local tsip
  tsip="$(tailscale_ip | tr -d '[:space:]')"

  echo
  echo "Steam Headless stack started."
  echo
  echo "Mode:"
  echo "  ${STEAM_HEADLESS_MODE}"
  if is_hybrid; then
    echo "  host Xorg display: ${HOST_DISPLAY}"
    echo "  host Xorg config:  ${HOST_XORG_CONFIG}"
    echo "  Pulse server:      unix:${PULSE_SERVER_PATH}"
  fi
  echo
  echo "Files:"
  echo "  ${SERVICE_DIR}/docker-compose.yml"
  echo "  ${SERVICE_DIR}/.env"
  echo "  ${DATA_DIR}/home/Downloads/NVIDIA_$(cat /sys/module/nvidia/version 2>/dev/null || echo '<version>').run"
  echo "  udev/Xorg restart-loop patch: ${PATCH_UDEV_XORG_RESTART_LOOP}"
  echo "  Steam games library: /mnt/games/SteamLibrary"
  echo
  echo "Logs:"
  echo "  cd ${SERVICE_DIR}"
  echo "  docker compose logs -f --tail=200"
  echo "  docker logs -f ${CONTAINER_NAME}"
  if is_hybrid; then
    echo "  tail -f ${HOST_XORG_LOG}"
    echo "  docker exec ${CONTAINER_NAME} tail -f /home/default/.cache/log/sunshine-hostx.log"
    echo "  docker exec ${CONTAINER_NAME} tail -f /home/default/.cache/log/steam-hostx.log"
    echo "  docker exec ${CONTAINER_NAME} tail -f /home/default/.cache/log/xfce-hostx.log"
    if [ "$START_STEAM_QR_SERVER" = "1" ]; then
      echo "  docker exec ${CONTAINER_NAME} tail -f /home/default/.cache/log/steam-qr-server.log"
    fi
  fi
  echo
  echo "Shell:"
  echo "  docker exec -it ${CONTAINER_NAME} bash"
  echo
  if [ -n "$tsip" ]; then
    echo "Sunshine:"
    echo "  https://${tsip}:47990"
    echo "  user: ${SUNSHINE_USER}"
    echo "  pass: ${SUNSHINE_PASS}"
    if is_hybrid && [ "$ENABLE_DEBUG_VNC" = "1" ]; then
      echo
      echo "Debug VNC:"
      echo "  ${tsip}:${HOST_VNC_PORT}"
    elif ! is_hybrid; then
      echo
      echo "noVNC:"
      echo "  http://${tsip}:${PORT_NOVNC_WEB}"
    fi
    if is_hybrid && [ "$START_STEAM_QR_SERVER" = "1" ]; then
      echo
      echo "Steam QR Login:"
      echo "  http://${tsip}:${STEAM_QR_PORT}/"
      echo "  debug screenshot: http://${tsip}:${STEAM_QR_PORT}/debug.png"
      if [ "$ENABLE_FRP_SUNSHINE_RELAY" = "1" ] && [ "$ENABLE_FRP_STEAM_QR_RELAY" = "1" ] && [ -n "$FRP_RELAY_HOST" ]; then
        echo "  EC2 relay: http://${FRP_RELAY_HOST}:${FRP_REMOTE_PORT_STEAM_QR}/"
      fi
    fi
  else
    echo "Sunshine: https://<host-ip>:47990"
    if ! is_hybrid; then
      echo "noVNC: http://<host-ip>:${PORT_NOVNC_WEB}"
    fi
    if is_hybrid && [ "$START_STEAM_QR_SERVER" = "1" ]; then
      echo "Steam QR Login: http://<host-ip>:${STEAM_QR_PORT}/"
      if [ "$ENABLE_FRP_SUNSHINE_RELAY" = "1" ] && [ "$ENABLE_FRP_STEAM_QR_RELAY" = "1" ] && [ -n "$FRP_RELAY_HOST" ]; then
        echo "Steam QR EC2 relay: http://${FRP_RELAY_HOST}:${FRP_REMOTE_PORT_STEAM_QR}/"
      fi
    fi
  fi
  if [ "$ENABLE_FRP_SUNSHINE_RELAY" = "1" ] && [ -n "$FRP_RELAY_HOST" ]; then
    echo
    echo "FRP Sunshine relay:"
    echo "  Moonlight host: ${FRP_RELAY_HOST}"
    echo "  control port:   ${FRP_RELAY_PORT}"
    echo "  service:        ${FRP_SERVICE_NAME}"
    echo "  logs:           journalctl -u ${FRP_SERVICE_NAME} -f"
    if [ "$START_STEAM_QR_SERVER" = "1" ] && [ "$ENABLE_FRP_STEAM_QR_RELAY" = "1" ]; then
      echo "  QR relay:       http://${FRP_RELAY_HOST}:${FRP_REMOTE_PORT_STEAM_QR}/"
    fi
  fi
  if [ -n "$TAILSCALE_EXIT_NODE" ]; then
    echo
    echo "Tailscale exit node:"
    echo "  node:           ${TAILSCALE_EXIT_NODE}"
    echo "  allow LAN:      ${TAILSCALE_EXIT_NODE_ALLOW_LAN}"
    echo "  FRP bypass:     ${TAILSCALE_EXIT_NODE_EXCLUDE_FRP_RELAY}"
    if [ -n "$FRP_RELAY_HOST" ]; then
      echo "  check relay:    ip route get ${FRP_RELAY_HOST}"
    fi
    echo "  check public:   curl -4 ifconfig.me"
  fi
  echo
  echo "Quick checks:"
  if is_hybrid; then
    echo "  DISPLAY=${HOST_DISPLAY} xrandr --query"
    echo "  DISPLAY=${HOST_DISPLAY} vkcube"
    echo "  docker exec -u default ${CONTAINER_NAME} bash -lc 'PULSE_SERVER=unix:${PULSE_SERVER_PATH} pactl list short sink-inputs'"
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

  case "$STEAM_HEADLESS_MODE" in
    hybrid|primary) ;;
    *)
      echo "ERROR: STEAM_HEADLESS_MODE must be hybrid or primary"
      exit 1
      ;;
  esac

  install_basics
  stop_existing_stacks
  prepare_devices
  prepare_dirs
  write_host_input_config

  local nvidia_version
  nvidia_version="${NVIDIA_DRIVER_VERSION:-$(detect_nvidia_version)}"

  download_nvidia_driver "$nvidia_version"
  restore_steam_session
  restore_sunshine_state
  seed_local_steam_library_config
  write_env_file "$nvidia_version"
  write_compose_file

  if is_hybrid; then
    write_host_xorg_config
    start_host_xorg
  fi

  start_stack
  wait_for_container
  wait_for_supervisor
  patch_udev_xorg_restart_loop

  if is_hybrid; then
    stop_supervisor_desktop_services
    install_container_runtime_packages
    configure_container_default_browser
    install_container_steam_qr_server
    start_hybrid_container_services
    start_steam_qr_server
    configure_tailscale_exit_node
    exclude_frp_relay_from_tailscale_exit_node
    start_frp_sunshine_relay
    start_debug_vnc
  fi

  print_status
  show_logs
}

main "$@"
