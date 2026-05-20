FROM josh5/steam-headless:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    pick_pkg() { \
      for pkg in "$@"; do \
        if apt-cache show "$pkg" >/dev/null 2>&1; then \
          printf "%s\n" "$pkg"; \
          return 0; \
        fi; \
      done; \
      return 1; \
    }; \
    asound_pkg="$(pick_pkg libasound2t64:i386 libasound2:i386 || printf "libasound2:i386")"; \
    curl_pkg="$(pick_pkg libcurl4t64:i386 libcurl4:i386 || printf "libcurl4:i386")"; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      chromium \
      curl \
      file \
      firefox-esr \
      xdotool \
      xdg-user-dirs \
      xdg-utils \
      "$asound_pkg" \
      libc6:i386 \
      "$curl_pkg" \
      libdbus-1-3:i386 \
      libdrm2:i386 \
      libegl1:i386 \
      libgbm1:i386 \
      libgcc-s1:i386 \
      libgl1:i386 \
      libglvnd0:i386 \
      libglx0:i386 \
      libnm0:i386 \
      libnss3:i386 \
      libpulse0:i386 \
      libstdc++6:i386 \
      libudev1:i386 \
      libvulkan1:i386 \
      libx11-6:i386 \
      libxcb-dri3-0:i386 \
      libxcb1:i386 \
      libxcomposite1:i386 \
      libxdamage1:i386 \
      libxext6:i386 \
      libxfixes3:i386 \
      libxrandr2:i386 \
      libxrender1:i386 \
      libxtst6:i386; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*
