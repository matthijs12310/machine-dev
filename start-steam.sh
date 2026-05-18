#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

default_steam_user="mc"
if id runner >/dev/null 2>&1; then
  default_steam_user="runner"
fi

steam_user="${STEAM_USER:-$default_steam_user}"
steam_home="/home/${steam_user}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp/runtime-${steam_user}}"
xdg_config_home="${steam_home}/.config"
xdg_cache_home="${steam_home}/.cache"
pulse_server="${PULSE_SERVER:-unix:${runtime_dir}/pulse/native}"
steam_session_archive="${STEAM_SESSION_ARCHIVE:-}"
steam_session_url="${STEAM_SESSION_URL:-}"
steam_restore_force="${STEAM_RESTORE_FORCE:-0}"

need_root_for_install() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Steam is not installed and this script is not running as root."
    echo "Run with sudo so it can install steam-installer."
    exit 1
  fi
}

install_steam_installer() {
  if command -v steam >/dev/null 2>&1; then
    echo "Steam command already exists: $(command -v steam)"
    return 0
  fi

  need_root_for_install

  echo "Installing Steam via apt..."

  export DEBIAN_FRONTEND=noninteractive

  dpkg --add-architecture i386 || true
  apt-get update

  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    steam-installer

  if ! command -v steam >/dev/null 2>&1; then
    echo "ERROR: steam command still not found after installing steam-installer."
    exit 1
  fi

  echo "Steam installed: $(command -v steam)"
}

prepare_user_and_runtime() {
  modprobe uinput 2>/dev/null || true
  if [ ! -e /dev/uinput ]; then
    mknod /dev/uinput c 10 223 2>/dev/null || true
  fi

  if [ "$(id -u)" -eq 0 ]; then
    if ! id "$steam_user" >/dev/null 2>&1; then
      echo "Creating user: ${steam_user}"
      useradd -m -s /bin/bash "$steam_user"
    fi
    usermod -aG input "$steam_user" 2>/dev/null || true

    mkdir -p "$runtime_dir" /dev/shm "$steam_home" "$xdg_config_home" "$xdg_cache_home"
    chown -R "$steam_user:$steam_user" "$runtime_dir" "$steam_home" "$xdg_config_home" "$xdg_cache_home" || true
    chmod 700 "$runtime_dir" || true
  else
    mkdir -p "$runtime_dir" "$xdg_config_home" "$xdg_cache_home" /dev/shm
    chmod 700 "$runtime_dir" || true
  fi

  chmod 1777 /dev/shm /tmp || true
  chmod -R a+rw /dev/input /dev/uinput 2>/dev/null || true
  rm -f /dev/shm/Steam* /dev/shm/steam* /dev/shm/.org.chromium.* /tmp/.org.chromium.* 2>/dev/null || true

  if command -v xhost >/dev/null 2>&1; then
    DISPLAY="$DISPLAY" xhost "+SI:localuser:${steam_user}" >/dev/null 2>&1 || true
  fi
}

steam_session_exists() {
  [ -f "${steam_home}/.steam/debian-installation/config/loginusers.vdf" ] \
    || [ -f "${steam_home}/.steam/steam/config/loginusers.vdf" ] \
    || [ -f "${steam_home}/.steam/root/config/loginusers.vdf" ] \
    || [ -f "${steam_home}/.local/share/Steam/config/loginusers.vdf" ]
}

find_steam_session_archive() {
  local candidate

  if [ -n "$steam_session_archive" ] && [ -f "$steam_session_archive" ]; then
    echo "$steam_session_archive"
    return 0
  fi

  for candidate in \
    "${script_dir}/steam-session.tar.gz" \
    "${script_dir}/steam-session.tgz" \
    "${script_dir}/steam-session.tar.zst" \
    "${script_dir}/steam-profile.tar.gz" \
    "${script_dir}/steam-profile.tgz" \
    "${script_dir}/steam-profile.tar.zst"
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

download_steam_session_archive() {
  local target="/tmp/steam-session-restore.tar.gz"

  [ -n "$steam_session_url" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1

  case "$steam_session_url" in
    *.tar.zst|*.zst) target="/tmp/steam-session-restore.tar.zst" ;;
    *.tgz) target="/tmp/steam-session-restore.tgz" ;;
  esac

  echo "Downloading Steam session archive from STEAM_SESSION_URL" >&2
  curl -fL "$steam_session_url" -o "$target"
  echo "$target"
}

restore_steam_session_if_available() {
  local archive=""

  if [ "$steam_restore_force" != "1" ] && steam_session_exists; then
    echo "Steam session already exists for ${steam_user}; restore skipped."
    return 0
  fi

  if archive="$(find_steam_session_archive 2>/dev/null)"; then
    :
  elif archive="$(download_steam_session_archive 2>/dev/null)"; then
    :
  else
    echo "No Steam session archive found; first Steam login may still be required."
    return 0
  fi

  echo "Restoring Steam session from: ${archive}"
  mkdir -p "$steam_home"

  case "$archive" in
    *.tar.zst|*.zst)
      if command -v zstd >/dev/null 2>&1; then
        tar --zstd -xf "$archive" -C "$steam_home"
      else
        echo "WARNING: ${archive} needs zstd, but zstd is not installed. Restore skipped."
        return 0
      fi
      ;;
    *)
      tar -xzf "$archive" -C "$steam_home"
      ;;
  esac

  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$steam_user:$steam_user" "${steam_home}/.steam" "${steam_home}/.local" 2>/dev/null || true
  fi
}

start_steam_as_user() {
  echo "Starting Steam as user ${steam_user} on DISPLAY=${DISPLAY}"
  echo "Command: runuser -u ${steam_user} -- env DISPLAY=${DISPLAY} HOME=${steam_home} USER=${steam_user} LOGNAME=${steam_user} steam"

  exec runuser -u "$steam_user" -- env \
    DISPLAY="$DISPLAY" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    XDG_CACHE_HOME="$xdg_cache_home" \
    DBUS_SESSION_BUS_ADDRESS= \
    PULSE_SERVER="$pulse_server" \
    HOME="$steam_home" \
    USER="$steam_user" \
    LOGNAME="$steam_user" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    GTK_A11Y=none \
    SDL_VIDEODRIVER=x11 \
    dbus-run-session -- steam
}

start_steam_current_user() {
  export XDG_RUNTIME_DIR="$runtime_dir"
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$xdg_config_home}"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$xdg_cache_home}"
  export PULSE_SERVER="${PULSE_SERVER:-$pulse_server}"
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:${PATH:-}"
  export HOME="${HOME:-$steam_home}"
  export USER="${USER:-$steam_user}"
  export LOGNAME="${LOGNAME:-$steam_user}"
  export LANG=C.UTF-8
  export LC_ALL=C.UTF-8
  export GTK_A11Y=none
  export SDL_VIDEODRIVER=x11

  echo "Starting Steam as current user on DISPLAY=${DISPLAY}"
  echo "Command: steam"

  exec dbus-run-session -- steam
}

main() {
  install_steam_installer
  prepare_user_and_runtime
  restore_steam_session_if_available

  if [ "$(id -u)" -eq 0 ]; then
    start_steam_as_user
  else
    start_steam_current_user
  fi
}

main "$@"
