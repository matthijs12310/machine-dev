#!/usr/bin/with-contenv bash
# Runs at every container start (linuxserver custom-init). Idempotent:
# fixes labwc autostart env, registers /config/roms gamedir,
# installs keys + firmware from /nas (NAS bind, read-only is fine).
# Safe to re-run; never overwrites existing good state blindly.

AUTOSTART=/config/.config/labwc/autostart
mkdir -p /config/.config/labwc
if ! grep -q "QT_QPA_PLATFORM=wayland" "$AUTOSTART" 2>/dev/null; then
  cat > "$AUTOSTART" <<'AUTOSTART_EOF'
#!/bin/bash

if [ ! -f "${HOME}/.config/eden/qt-config.ini" ]; then
  mkdir -p "${HOME}/.config/eden/"
  cp /defaults/qt-config.ini "${HOME}/.config/eden/"
fi

export HOME=/config
export XDG_RUNTIME_DIR=/config/.XDG
export WAYLAND_DISPLAY=wayland-1
export QT_QPA_PLATFORM=wayland
exec eden
AUTOSTART_EOF
  chown abc:abc "$AUTOSTART" 2>/dev/null || true
fi

QTINI=/config/.config/eden/qt-config.ini
if [ -f "$QTINI" ] && ! grep -q "gamedirs.4.path" "$QTINI" 2>/dev/null; then
  sed -i 's|^Paths\\gamedirs\\size=3$|Paths\\gamedirs\\size=4|; s|^Paths\\gamedirs\\3\\expanded=true$|Paths\\gamedirs\\3\\expanded=true\nPaths\\gamedirs\\4\\path=/config/roms\nPaths\\gamedirs\\4\\deep_scan\\default=true\nPaths\\gamedirs\\4\\deep_scan=false\nPaths\\gamedirs\\4\\expanded\\default=true\nPaths\\gamedirs\\4\\expanded=true|' "$QTINI" || true
fi

if [ -d /nas ]; then
  mkdir -p /config/.local/share/eden/keys /config/.local/share/eden/nand/system/Contents/registered
  for k in prod.keys title.keys; do
    [ -f "/nas/$k" ] && [ ! -f "/config/.local/share/eden/keys/$k" ] && cp "/nas/$k" /config/.local/share/eden/keys/
  done
  FWZIP="$(ls /nas/Firmware*.zip 2>/dev/null | head -1)"
  if [ -n "$FWZIP" ] && [ -z "$(ls /config/.local/share/eden/nand/system/Contents/registered/ 2>/dev/null)" ]; then
    unzip -o -q "$FWZIP" -d /config/.local/share/eden/nand/system/Contents/registered/
  fi
  chown -R abc:abc /config/.local/share/eden/keys /config/.local/share/eden/nand /config/roms 2>/dev/null || true
fi
