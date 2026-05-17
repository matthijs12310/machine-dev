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
steam_root="${STEAM_ROOT:-${steam_home}/.local/share/Steam}"
steam_args="${STEAM_ARGS:--cef-disable-gpu -cef-disable-gpu-compositing -cef-disable-dev-shm-usage -no-cef-sandbox}"
steam_runtime="${STEAM_RUNTIME:-1}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp/runtime-${steam_user}}"
steam_ld_library_path="${STEAM_LD_LIBRARY_PATH:-/usr/lib32:/usr/lib/x86_64-linux-gnu}"

if ! dpkg --print-foreign-architectures | grep -qx i386 \
  || ! dpkg -s libc6:i386 libgl1:i386 libgl1-mesa-dri:i386 libdrm2:i386 >/dev/null 2>&1; then
  echo "Steam 32-bit deps missing. Installing now..."
  "${script_dir}/install-steam-deps.sh"
fi

if [ "$(id -u)" -eq 0 ]; then
  if ! id "$steam_user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$steam_user"
  fi

  mkdir -p "$runtime_dir" /dev/shm
  chown "$steam_user:$steam_user" "$runtime_dir"
  chmod 700 "$runtime_dir"
  chmod 1777 /dev/shm /tmp || true
  rm -f /dev/shm/Steam* /dev/shm/steam* /dev/shm/.org.chromium.* /tmp/.org.chromium.* 2>/dev/null || true
  DISPLAY="$DISPLAY" xhost "+SI:localuser:${steam_user}" >/dev/null 2>&1 || true

  echo "Starting Steam as user ${steam_user} on DISPLAY=${DISPLAY}"
  echo "Steam root: ${steam_root}"
  echo "LD_LIBRARY_PATH=${steam_ld_library_path}"
  exec runuser -u "$steam_user" -- env \
    DISPLAY="$DISPLAY" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS= \
    HOME="$steam_home" \
    USER="$steam_user" \
    LOGNAME="$steam_user" \
    PATH="$PATH" \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    GTK_A11Y=none \
    GTK_IM_MODULE=xim \
    QT_IM_MODULE=xim \
    XMODIFIERS=@im=none \
    SDL_VIDEODRIVER=x11 \
    STEAM_RUNTIME="$steam_runtime" \
    STEAM_ARGS="$steam_args" \
    LD_LIBRARY_PATH="$steam_ld_library_path" \
    bash -lc 'set +u; cd "$HOME/.local/share/Steam" || exit 1; set -- ${STEAM_ARGS:-}; exec ./steam.sh "$@"'
fi

export XDG_RUNTIME_DIR="$runtime_dir"
mkdir -p "$XDG_RUNTIME_DIR" /dev/shm
chmod 700 "$XDG_RUNTIME_DIR"
chmod 1777 /dev/shm /tmp || true
rm -f /dev/shm/Steam* /dev/shm/steam* /dev/shm/.org.chromium.* /tmp/.org.chromium.* 2>/dev/null || true

export HOME="${HOME:-$steam_home}"
export USER="${USER:-$steam_user}"
export LOGNAME="${LOGNAME:-$steam_user}"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export GTK_A11Y=none
export GTK_IM_MODULE=xim
export QT_IM_MODULE=xim
export XMODIFIERS=@im=none
export SDL_VIDEODRIVER=x11
export STEAM_RUNTIME="$steam_runtime"
export LD_LIBRARY_PATH="$steam_ld_library_path"

cd "$steam_root"
set -- ${steam_args:-}
exec ./steam.sh "$@"
