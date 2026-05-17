#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$0" "$@"
  fi
  echo "This installer needs root for apt. Run it as root."
  exit 1
fi

dpkg --add-architecture i386
apt-get update

glib_i386="libglib2.0-0t64:i386"
if ! apt-cache show "$glib_i386" >/dev/null 2>&1; then
  glib_i386="libglib2.0-0:i386"
fi

glib_amd64="libglib2.0-0t64"
if ! apt-cache show "$glib_amd64" >/dev/null 2>&1; then
  glib_amd64="libglib2.0-0"
fi

asound_i386="libasound2t64:i386"
if ! apt-cache show "$asound_i386" >/dev/null 2>&1; then
  asound_i386="libasound2:i386"
fi

apt-get install -y --no-install-recommends \
  ca-certificates curl wget xdg-utils xfonts-base fonts-dejavu-core dbus-x11 locales "$glib_amd64" \
  libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
  libx11-6:i386 libxext6:i386 libxrender1:i386 libxrandr2:i386 \
  libxcb1:i386 libxcb-res0:i386 libxfixes3:i386 libxi6:i386 libxinerama1:i386 \
  libxcursor1:i386 libxtst6:i386 \
  libdbus-1-3:i386 "$glib_i386" libgtk2.0-0:i386 \
  "$asound_i386" libpulse0:i386 libpipewire-0.3-0:i386 libudev1:i386 \
  libdrm2:i386 libgbm1:i386 libgl1:i386 libglx0:i386 libegl1:i386 \
  libgl1-mesa-dri:i386 libvulkan1:i386 libva2:i386 libvdpau1:i386 \
  libnss3:i386 libnspr4:i386 \
  libibus-1.0-5 libibus-1.0-5:i386 ibus-gtk ibus-gtk:i386 ibus-gtk3 ibus-gtk3:i386

optional_packages=()
for package in \
  libcurl4t64:i386 libcurl4:i386 libcurl3t64-gnutls:i386 libcurl3-gnutls:i386 \
  zlib1g:i386 libbz2-1.0:i386 liblzma5:i386 libzstd1:i386 \
  libvpx9:i386 libvpx8:i386 libvpx7:i386 libvpx6:i386 \
  libssl3t64:i386 libssl3:i386 libkrb5-3:i386 libgssapi-krb5-2:i386 \
  libidn2-0:i386 libnghttp2-14:i386 librtmp1:i386 libssh-4:i386 \
  libpsl5:i386 libldap2:i386 libbrotli1:i386 libsqlite3-0:i386 libxml2:i386 \
  libatspi2.0-0:i386 libatk1.0-0:i386 libcairo2:i386 libpango-1.0-0:i386 \
  libpangocairo-1.0-0:i386 libfontconfig1:i386 libfreetype6:i386 \
  libsdl2-2.0-0:i386; do
  if apt-cache show "$package" >/dev/null 2>&1; then
    optional_packages+=("$package")
  fi
done
if [ "${#optional_packages[@]}" -gt 0 ]; then
  apt-get install -y --no-install-recommends "${optional_packages[@]}" || true
fi

for package in libcurl4-openssl-dev libcurl4-gnutls-dev; do
  if apt-cache show "$package" >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends "$package" || true
    break
  fi
done

locale-gen en_US.UTF-8 >/dev/null 2>&1 || true

steam_libs=()
for package in steam-libs-amd64:amd64 steam-libs-i386:i386; do
  if apt-cache show "$package" >/dev/null 2>&1; then
    steam_libs+=("$package")
  fi
done
if [ "${#steam_libs[@]}" -gt 0 ]; then
  apt-get install -y --no-install-recommends "${steam_libs[@]}" || true
fi

ldconfig || true

echo "Steam 32-bit runtime deps installed."
echo "Try Steam again from the same DISPLAY, e.g.:"
echo "  DISPLAY=:99 steam"
