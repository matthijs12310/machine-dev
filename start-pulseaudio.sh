#!/usr/bin/env bash
set -euo pipefail

default_audio_user="runner"
if ! id runner >/dev/null 2>&1; then
  default_audio_user="${USER:-runner}"
fi

audio_user="${AUDIO_USER:-${STEAM_USER:-$default_audio_user}}"
audio_home="${AUDIO_HOME:-/home/${audio_user}}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp/runtime-${audio_user}}"

if [ "$(id -u)" -eq 0 ]; then
  if ! id "$audio_user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$audio_user"
  fi

  if ! command -v pulseaudio >/dev/null 2>&1 || ! command -v pactl >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends pulseaudio pulseaudio-utils
  fi

  mkdir -p "$runtime_dir" "${audio_home}/.config/pulse" "${audio_home}/.cache"
  chown -R "$audio_user:$audio_user" "$runtime_dir" "${audio_home}/.config" "${audio_home}/.cache"
  chmod 700 "$runtime_dir" "${audio_home}/.config/pulse"

  exec runuser -u "$audio_user" -- env \
    HOME="$audio_home" \
    USER="$audio_user" \
    LOGNAME="$audio_user" \
    XDG_CONFIG_HOME="${audio_home}/.config" \
    XDG_CACHE_HOME="${audio_home}/.cache" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS= \
    bash "$0"
fi

export HOME="$audio_home"
export XDG_CONFIG_HOME="${audio_home}/.config"
export XDG_CACHE_HOME="${audio_home}/.cache"
export XDG_RUNTIME_DIR="$runtime_dir"
unset PULSE_RUNTIME_PATH PULSE_CONFIG_PATH PULSE_STATE_PATH PULSE_CLIENTCONFIG

mkdir -p "$XDG_CONFIG_HOME/pulse" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_CONFIG_HOME/pulse" "$XDG_RUNTIME_DIR"

cat >"$XDG_CONFIG_HOME/pulse/default.pa" <<'EOF'
.nofail
load-module module-native-protocol-unix auth-anonymous=1
load-module module-always-sink
EOF

cat >"$XDG_CONFIG_HOME/pulse/daemon.conf" <<'EOF'
exit-idle-time = -1
default-sample-rate = 48000
alternate-sample-rate = 44100
EOF

pulseaudio --kill >/dev/null 2>&1 || true
pulseaudio --start --exit-idle-time=-1

for _ in $(seq 1 20); do
  if pactl info >/dev/null 2>&1; then
    echo "PulseAudio ready"
    pactl list short sinks || true
    exit 0
  fi
  sleep 0.5
done

echo "PulseAudio did not become ready"
exit 1
