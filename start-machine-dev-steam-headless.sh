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
VERIFY_HOST_VULKAN="${VERIFY_HOST_VULKAN:-1}"
ENABLE_DEBUG_VNC="${ENABLE_DEBUG_VNC:-0}"
HOST_VNC_PORT="${HOST_VNC_PORT:-5901}"
HOST_XORG_CONFIG="${HOST_XORG_CONFIG:-/etc/X11/xorg-host-vulkan.conf}"
HOST_XORG_LOG="${HOST_XORG_LOG:-${LOG_DIR}/host-xorg-99.log}"
HOST_XORG_BUS_ID="${HOST_XORG_BUS_ID:-}"
HOST_XORG_CONNECTED_MONITOR="${HOST_XORG_CONNECTED_MONITOR:-DFP-0}"
HOST_XORG_OUTPUT="${HOST_XORG_OUTPUT:-}"
PULSE_SERVER_PATH="${PULSE_SERVER_PATH:-/tmp/.X11-unix/run/pulse/native}"
SUNSHINE_STATE_SOURCE_DIR="${SUNSHINE_STATE_SOURCE_DIR:-${SCRIPT_DIR}/sunshine}"
LUCIDLINK_HOST_MOUNT="${LUCIDLINK_HOST_MOUNT:-/mnt/lucidlink}"
LUCIDLINK_CONTAINER_MOUNT="${LUCIDLINK_CONTAINER_MOUNT:-/mnt/lucidlink}"
MOUNT_LUCIDLINK="${MOUNT_LUCIDLINK:-auto}" # auto, 1, or 0
ENABLE_LUCIDLINK="${ENABLE_LUCIDLINK:-auto}" # auto, 1, or 0
LUCIDLINK_FILESPACE="${LUCIDLINK_FILESPACE:-games.hjghjk}"
LUCIDLINK_ROOT_PATH="${LUCIDLINK_ROOT_PATH:-/var/lib/lucidlink}"
LUCIDLINK_RUN_USER="${LUCIDLINK_RUN_USER:-runner}"
LUCIDLINK_TOKEN_FILE="${LUCIDLINK_TOKEN_FILE:-/home/${LUCIDLINK_RUN_USER}/.lucid-secrets/service-token}"
LUCIDLINK_INSTALL_URL="${LUCIDLINK_INSTALL_URL:-https://www.lucidlink.com/download/new-ll-latest/linux-deb/stable/}"
LUCIDLINK_WAIT_SECONDS="${LUCIDLINK_WAIT_SECONDS:-90}"
LUCIDLINK_CACHE_SIZE="${LUCIDLINK_CACHE_SIZE:-25G}"
STEAM_COMPAT_MOUNTS="${STEAM_COMPAT_MOUNTS:-/mnt/games}"
FIX_LUCIDLINK_PERMISSIONS="${FIX_LUCIDLINK_PERMISSIONS:-0}"
LOCALIZE_LUCIDLINK_STEAM_STATE="${LOCALIZE_LUCIDLINK_STEAM_STATE:-1}"
LOCALIZE_LUCIDLINK_STEAM_TOOLS="${LOCALIZE_LUCIDLINK_STEAM_TOOLS:-1}"
STEAM_LOCAL_TOOL_APPIDS="${STEAM_LOCAL_TOOL_APPIDS:-1070560 1391110 1493710 1628350 2180100 228980 4183110}"
ENABLE_PROTON_LOGS="${ENABLE_PROTON_LOGS:-0}"
WAIT_FOR_SUPERVISOR_SECONDS="${WAIT_FOR_SUPERVISOR_SECONDS:-45}"
WAIT_FOR_PULSE_SECONDS="${WAIT_FOR_PULSE_SECONDS:-25}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
  fi
}

is_hybrid() {
  [ "$STEAM_HEADLESS_MODE" = "hybrid" ]
}

should_enable_lucidlink() {
  case "$ENABLE_LUCIDLINK" in
    1|true|yes) return 0 ;;
    0|false|no) return 1 ;;
  esac

  [ -n "${LUCIDLINK_TOKEN:-}" ] || [ -s "$LUCIDLINK_TOKEN_FILE" ]
}

prepare_lucidlink_steam_library() {
  [ "$MOUNT_LUCIDLINK" != "0" ] || return 0
  [ -d "$LUCIDLINK_HOST_MOUNT" ] || return 0

  local library_dir="${LUCIDLINK_HOST_MOUNT}/SteamLibrary"
  local owner_uid owner_gid owner_user

  owner_uid="$(stat -c '%u' "$LUCIDLINK_HOST_MOUNT" 2>/dev/null || echo 0)"
  owner_gid="$(stat -c '%g' "$LUCIDLINK_HOST_MOUNT" 2>/dev/null || echo 0)"
  owner_user="$(getent passwd "$owner_uid" | cut -d: -f1 || true)"

  if [ -n "$owner_user" ] && [ "$owner_uid" != "0" ]; then
    runuser -u "$owner_user" -- mkdir -p "$library_dir" 2>/dev/null || true
    runuser -u "$owner_user" -- mkdir -p "${library_dir}/steamapps" 2>/dev/null || true
    chmod 777 "$library_dir" 2>/dev/null || true
    chmod 777 "${library_dir}/steamapps" 2>/dev/null || true
  else
    mkdir -p "$library_dir" 2>/dev/null || true
    mkdir -p "${library_dir}/steamapps" 2>/dev/null || true
    chmod 777 "$library_dir" 2>/dev/null || true
    chmod 777 "${library_dir}/steamapps" 2>/dev/null || true
  fi

  if [ -d "$library_dir" ]; then
    echo "LucidLink Steam library prepared: ${library_dir} ($(stat -c '%U:%G %a' "$library_dir" 2>/dev/null || true))"
    if [ "$FIX_LUCIDLINK_PERMISSIONS" = "1" ]; then
      echo "Making LucidLink Steam library writable for Steam container user"
      chmod -R ugo+rwX "$library_dir" 2>/dev/null || true
    fi
  else
    echo "WARNING: could not create LucidLink Steam library at ${library_dir}"
  fi
}

configure_lucidlink_cache() {
  should_enable_lucidlink || return 0
  [ -n "$LUCIDLINK_CACHE_SIZE" ] || return 0

  echo "Setting LucidLink local cache limit to ${LUCIDLINK_CACHE_SIZE}"
  runuser -u "$LUCIDLINK_RUN_USER" -- bash -lc "
    DISPLAY='${HOST_DISPLAY}' lucid config --set --DataCache.Size '${LUCIDLINK_CACHE_SIZE}' >/dev/null
    DISPLAY='${HOST_DISPLAY}' lucid cache --info 2>/dev/null || DISPLAY='${HOST_DISPLAY}' lucid cache 2>/dev/null || true
  " || echo "WARNING: failed to set LucidLink cache limit to ${LUCIDLINK_CACHE_SIZE}"
}

install_lucidlink_client() {
  should_enable_lucidlink || return 0

  if command -v lucid >/dev/null 2>&1; then
    return 0
  fi

  echo "Installing LucidLink Linux client"
  local deb="/tmp/lucidinstaller.deb"
  curl -fL "$LUCIDLINK_INSTALL_URL" -o "$deb"
  apt-get install -y "$deb"
}

start_lucidlink() {
  should_enable_lucidlink || return 0

  if ! command -v lucid >/dev/null 2>&1; then
    echo "WARNING: LucidLink requested but lucid command is not installed"
    return 0
  fi

  if ! id "$LUCIDLINK_RUN_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$LUCIDLINK_RUN_USER"
  fi

  mkdir -p "$(dirname "$LUCIDLINK_TOKEN_FILE")" "$LUCIDLINK_HOST_MOUNT" "$LUCIDLINK_ROOT_PATH" "$LOG_DIR"
  chown -R "${LUCIDLINK_RUN_USER}:${LUCIDLINK_RUN_USER}" "$(dirname "$LUCIDLINK_TOKEN_FILE")" "$LUCIDLINK_HOST_MOUNT" "$LUCIDLINK_ROOT_PATH" 2>/dev/null || true
  chown "${LUCIDLINK_RUN_USER}:${LUCIDLINK_RUN_USER}" "$LOG_DIR" 2>/dev/null || chmod 1777 "$LOG_DIR" 2>/dev/null || true
  chmod 700 "$(dirname "$LUCIDLINK_TOKEN_FILE")" 2>/dev/null || true

  if [ -n "${LUCIDLINK_TOKEN:-}" ]; then
    printf '%s' "$LUCIDLINK_TOKEN" >"$LUCIDLINK_TOKEN_FILE"
    chown "${LUCIDLINK_RUN_USER}:${LUCIDLINK_RUN_USER}" "$LUCIDLINK_TOKEN_FILE" 2>/dev/null || true
    chmod 600 "$LUCIDLINK_TOKEN_FILE" 2>/dev/null || true
  fi

  if [ ! -s "$LUCIDLINK_TOKEN_FILE" ]; then
    echo "WARNING: LucidLink enabled, but no token found at ${LUCIDLINK_TOKEN_FILE}"
    return 0
  fi

  if [ -f /etc/fuse.conf ]; then
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
  fi

  if mountpoint -q "$LUCIDLINK_HOST_MOUNT"; then
    echo "LucidLink already mounted at ${LUCIDLINK_HOST_MOUNT}"
    return 0
  fi

  pkill -u "$LUCIDLINK_RUN_USER" -f 'lucid daemon' 2>/dev/null || true

  echo "Starting LucidLink filespace ${LUCIDLINK_FILESPACE} at ${LUCIDLINK_HOST_MOUNT}"
  runuser -u "$LUCIDLINK_RUN_USER" -- bash -lc "
    mkdir -p '${LUCIDLINK_ROOT_PATH}' '${LUCIDLINK_HOST_MOUNT}' '${LOG_DIR}'
    DISPLAY='${HOST_DISPLAY}' lucid daemon \
      --fs '${LUCIDLINK_FILESPACE}' \
      --login-token \"\$(cat '${LUCIDLINK_TOKEN_FILE}')\" \
      --mount-point '${LUCIDLINK_HOST_MOUNT}' \
      --root-path '${LUCIDLINK_ROOT_PATH}' \
      --fuse-allow-other \
      >'${LOG_DIR}/lucidlink.log' 2>&1 &
  "

  for _ in $(seq 1 "$LUCIDLINK_WAIT_SECONDS"); do
    if [ -d "${LUCIDLINK_HOST_MOUNT}/SteamLibrary/steamapps" ] || mountpoint -q "$LUCIDLINK_HOST_MOUNT"; then
      echo "LucidLink mount is available"
      configure_lucidlink_cache
      prepare_lucidlink_steam_library
      return 0
    fi
    sleep 1
  done

  echo "WARNING: LucidLink did not become ready within ${LUCIDLINK_WAIT_SECONDS}s"
  tail -80 "${LOG_DIR}/lucidlink.log" 2>/dev/null || true
}

seed_lucidlink_steam_library_config() {
  [ "$MOUNT_LUCIDLINK" != "0" ] || return 0
  [ -d "$LUCIDLINK_HOST_MOUNT/SteamLibrary" ] || return 0

  local steam_root="${DATA_DIR}/home/.steam/steam"
  local library_path="${LUCIDLINK_CONTAINER_MOUNT}/SteamLibrary"
  local apps_block=""
  local file

  if [ -d "$LUCIDLINK_HOST_MOUNT/SteamLibrary/steamapps" ]; then
    while IFS= read -r manifest; do
      local appid size
      appid="$(basename "$manifest" | sed -n 's/^appmanifest_\([0-9][0-9]*\)\.acf$/\1/p')"
      [ -n "$appid" ] || continue
      size="$(awk -F'"' '/"SizeOnDisk"/ { print $4; exit }' "$manifest" 2>/dev/null)"
      [ -n "$size" ] || size=0
      apps_block="${apps_block}			\"${appid}\"		\"${size}\"
"
    done < <(find "$LUCIDLINK_HOST_MOUNT/SteamLibrary/steamapps" -maxdepth 1 -type f -name 'appmanifest_*.acf' | sort)
  fi

  for file in \
    "${steam_root}/steamapps/libraryfolders.vdf" \
    "${steam_root}/config/libraryfolders.vdf"; do
    mkdir -p "$(dirname "$file")"

    if [ ! -s "$file" ]; then
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
		}
	}
}
EOF
    fi

    if grep -Fq "$library_path" "$file"; then
      continue
    fi

    cp "$file" "${file}.bak.$(date +%s)" 2>/dev/null || true
    sed '$d' "$file" >"${file}.tmp"
    cat >>"${file}.tmp" <<EOF
	"1"
	{
		"path"		"$library_path"
		"label"		"LucidLink"
		"contentid"		"1111111111111111111"
		"totalsize"		"0"
		"apps"
		{
${apps_block}
		}
	}
}
EOF
    mv "${file}.tmp" "$file"
  done

  chown -R "${PUID}:${PGID}" "${steam_root}/steamapps" "${steam_root}/config" 2>/dev/null || true
}

localize_lucidlink_steam_state() {
  [ "$LOCALIZE_LUCIDLINK_STEAM_STATE" = "1" ] || return 0
  [ "$MOUNT_LUCIDLINK" != "0" ] || return 0
  [ -d "$LUCIDLINK_HOST_MOUNT/SteamLibrary/steamapps" ] || return 0

  local steamapps="${LUCIDLINK_HOST_MOUNT}/SteamLibrary/steamapps"
  local local_root="${DATA_DIR}/home/.steam/steam/steamapps"
  local name target backup

  mkdir -p "${local_root}/compatdata-lucid" "${local_root}/shadercache-lucid"
  chown -R "${PUID}:${PGID}" "${local_root}/compatdata-lucid" "${local_root}/shadercache-lucid" 2>/dev/null || true

  for name in compatdata shadercache; do
    target="/home/default/.steam/steam/steamapps/${name}-lucid"
    backup="${steamapps}/${name}.lucid.bak.$(date +%s)"

    if [ -L "${steamapps}/${name}" ]; then
      continue
    fi

    if [ -e "${steamapps}/${name}" ]; then
      mv "${steamapps}/${name}" "$backup" 2>/dev/null || true
    fi

    ln -s "$target" "${steamapps}/${name}" 2>/dev/null || true
  done
}

localize_lucidlink_steam_tools() {
  [ "$LOCALIZE_LUCIDLINK_STEAM_TOOLS" = "1" ] || return 0
  [ "$MOUNT_LUCIDLINK" != "0" ] || return 0
  [ -d "$LUCIDLINK_HOST_MOUNT/SteamLibrary/steamapps" ] || return 0

  local lucid_steamapps="${LUCIDLINK_HOST_MOUNT}/SteamLibrary/steamapps"
  local local_steamapps="${DATA_DIR}/home/.steam/steam/steamapps"
  local appid manifest installdir src_dir dst_dir

  mkdir -p "${local_steamapps}/common"
  chown -R "${PUID}:${PGID}" "$local_steamapps" 2>/dev/null || true

  for appid in $STEAM_LOCAL_TOOL_APPIDS; do
    manifest="${lucid_steamapps}/appmanifest_${appid}.acf"
    [ -f "$manifest" ] || continue

    installdir="$(awk -F'"' '/"installdir"/ { print $4; exit }' "$manifest" 2>/dev/null || true)"
    if [ -n "$installdir" ]; then
      src_dir="${lucid_steamapps}/common/${installdir}"
      dst_dir="${local_steamapps}/common/${installdir}"
      if [ -d "$src_dir" ] && [ ! -e "$dst_dir" ]; then
        echo "Moving Steam tool/runtime ${appid} (${installdir}) from LucidLink to local Steam library"
        mv "$src_dir" "$dst_dir" 2>/dev/null || true
      elif [ -d "$src_dir" ] && [ -e "$dst_dir" ]; then
        echo "Steam tool/runtime ${appid} already exists locally; leaving LucidLink copy in place"
      fi
    fi

    if [ ! -f "${local_steamapps}/appmanifest_${appid}.acf" ]; then
      mv "$manifest" "${local_steamapps}/appmanifest_${appid}.acf" 2>/dev/null || cp "$manifest" "${local_steamapps}/appmanifest_${appid}.acf" 2>/dev/null || true
    fi
  done

  chown -R "${PUID}:${PGID}" "$local_steamapps" 2>/dev/null || true
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
    ca-certificates curl git docker.io docker-compose containerd fuse3

  if is_hybrid; then
    apt-get install -y --no-install-recommends \
      dbus-x11 pulseaudio-utils vulkan-tools x11-utils x11-xserver-utils \
      xinit xserver-xorg-core xserver-xorg-input-evdev xserver-xorg-input-libinput

    if [ "$ENABLE_DEBUG_VNC" = "1" ]; then
      apt-get install -y --no-install-recommends x11vnc
    fi
  fi

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
  local lucid_mount_line=""

  if is_hybrid; then
    x11_source='/tmp/.X11-unix/'
  fi

  if [ "$MOUNT_LUCIDLINK" = "1" ] || { [ "$MOUNT_LUCIDLINK" = "auto" ] && [ -d "$LUCIDLINK_HOST_MOUNT" ]; }; then
    lucid_mount_line="      - ${LUCIDLINK_HOST_MOUNT}/:${LUCIDLINK_CONTAINER_MOUNT}/:rw"
    case ":${STEAM_COMPAT_MOUNTS}:" in
      *":${LUCIDLINK_CONTAINER_MOUNT}:"*) ;;
      *) STEAM_COMPAT_MOUNTS="${STEAM_COMPAT_MOUNTS}:${LUCIDLINK_CONTAINER_MOUNT}" ;;
    esac
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
${lucid_mount_line}
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

  prepare_lucidlink_steam_library
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
    if timeout 2 docker exec "$CONTAINER_NAME" supervisorctl status >/dev/null 2>&1; then
      echo "supervisord is ready"
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

install_container_browser() {
  [ "$INSTALL_CONTAINER_BROWSER" = "1" ] || return 0

  echo "Ensuring browser is installed inside ${CONTAINER_NAME}"
  timeout 240 docker exec "$CONTAINER_NAME" bash -lc '
set -e
if command -v firefox >/dev/null 2>&1 || command -v firefox-esr >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1; then
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends firefox-esr || apt-get install -y --no-install-recommends chromium
' || echo "WARNING: browser install inside ${CONTAINER_NAME} failed or timed out"
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

  if [ "$START_CONTAINER_SUNSHINE" = "1" ]; then
    docker exec "$CONTAINER_NAME" bash -lc 'pkill -u default -f sunshine 2>/dev/null || true'
    docker exec -u default "$CONTAINER_NAME" bash -lc "sunshine --creds '${SUNSHINE_USER}' '${SUNSHINE_PASS}' >/dev/null 2>&1 || true"
    docker exec -u default "$CONTAINER_NAME" bash -lc '
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
for d in /mnt/games '${LUCIDLINK_CONTAINER_MOUNT}'; do
  [ -d \"\$d\" ] || continue
  echo \"-- \$d\"
  stat -c '%U:%G %a %F %n' \"\$d\" 2>/dev/null || true
  df -h \"\$d\" 2>/dev/null || true
  mkdir -p \"\$d/SteamLibrary\" 2>/dev/null || true
  touch \"\$d/SteamLibrary/.machine-dev-write-test\" 2>/dev/null && rm -f \"\$d/SteamLibrary/.machine-dev-write-test\" && echo WRITE_OK || echo WRITE_FAIL
done
" >>"${LOG_DIR}/hybrid-post-start.log" 2>&1 || true

  if [ "$START_CONTAINER_STEAM" = "1" ]; then
    docker exec "$CONTAINER_NAME" bash -lc 'pkill -9 -u default -f "steam|steamwebhelper" 2>/dev/null || true'
    container_exec_default_detached '
mkdir -p /home/default/.cache/log
pactl set-default-sink sink-sunshine-stereo 2>/dev/null || true
pactl set-default-source sink-sunshine-stereo.monitor 2>/dev/null || true
export PULSE_SINK=sink-sunshine-stereo
echo "PULSE_SERVER=${PULSE_SERVER}" >/home/default/.cache/log/steam-hostx-env.log
echo "PULSE_SINK=${PULSE_SINK}" >>/home/default/.cache/log/steam-hostx-env.log
echo "STEAM_COMPAT_MOUNTS=${STEAM_COMPAT_MOUNTS}" >>/home/default/.cache/log/steam-hostx-env.log
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
  if [ "$MOUNT_LUCIDLINK" != "0" ] && [ -d "$LUCIDLINK_HOST_MOUNT" ]; then
    echo "  LucidLink mount: ${LUCIDLINK_HOST_MOUNT} -> ${LUCIDLINK_CONTAINER_MOUNT}"
  fi
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
  else
    echo "Sunshine: https://<host-ip>:47990"
    if ! is_hybrid; then
      echo "noVNC: http://<host-ip>:${PORT_NOVNC_WEB}"
    fi
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
  install_lucidlink_client
  start_lucidlink
  prepare_dirs
  write_host_input_config

  local nvidia_version
  nvidia_version="${NVIDIA_DRIVER_VERSION:-$(detect_nvidia_version)}"

  download_nvidia_driver "$nvidia_version"
  restore_steam_session
  restore_sunshine_state
  localize_lucidlink_steam_state
  localize_lucidlink_steam_tools
  seed_lucidlink_steam_library_config
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
    install_container_browser
    start_hybrid_container_services
    start_debug_vnc
  fi

  print_status
  show_logs
}

main "$@"
