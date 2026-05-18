# Machine.dev Gaming Kit

Minimal scripts for a fresh Machine.dev GPU gaming box with NVIDIA Xorg, Sunshine, Moonlight input passthrough, and Steam.

## Files

- `start-machine-dev-gaming.sh` - all-in-one launcher for Xorg, Sunshine, input bridge, and Steam.
- `setup-machine-dev-sunshine.sh` - installs/starts NVIDIA Xorg and Sunshine.
- `start-input-bridge.sh` + `moonlight-input-bridge.py` - bridges Moonlight passthrough keyboard/mouse into X11.
- `start-steam.sh` - starts Steam as `runner`/configured user.
- `install-steam-deps.sh` - installs Steam 32-bit runtime deps.

## Fresh Machine.dev Run

```bash
cd /workspace
git clone <your-github-repo-url> machine-dev
cd machine-dev
chmod +x *.sh moonlight-input-bridge.py
./start-machine-dev-gaming.sh
```

The all-in-one script starts Xorg/Sunshine first, checks NVIDIA GLX/Vulkan, then starts the input bridge and Steam. If GLX/Vulkan is not clean, Steam is skipped and logs are written to `/tmp/machine-dev-gaming`.

## Safer First Boot

Use this if you want to bring up Sunshine/Xorg first and start Steam manually after you verify Moonlight connects:

```bash
START_STEAM=0 ./start-machine-dev-gaming.sh
DISPLAY=:99 STEAM_USER=runner ./start-steam.sh
```

## Useful Overrides

```bash
START_STEAM=0 ./start-machine-dev-gaming.sh
START_INPUT=0 ./start-machine-dev-gaming.sh
WAIT_FOR_MOONLIGHT=1 ./start-machine-dev-gaming.sh
GAME_WIDTH=2560 GAME_HEIGHT=1440 ./start-machine-dev-gaming.sh
```

## Steam Login Session Restore

After logging into Steam once, you can back up the `runner` Steam session and place it next to these scripts as `steam-session.tar.gz`.

On the working machine:

```bash
pkill -u runner -f 'steam|steamwebhelper|srt-logger|zenity' 2>/dev/null || true
runuser -u runner -- bash -lc '
  set -e
  cd "$HOME"
  rm -rf /tmp/steam-session-backup
  mkdir -p /tmp/steam-session-backup
  shopt -s nullglob
  for p in \
    .steam/debian-installation/config \
    .steam/debian-installation/registry.vdf \
    .steam/debian-installation/ssfn* \
    .steam/steam/config \
    .steam/root/config \
    .steam/registry.vdf \
    .local/share/Steam/config \
    .local/share/Steam/registry.vdf \
    .local/share/Steam/ssfn*
  do
    [ -e "$p" ] && cp -a --parents "$p" /tmp/steam-session-backup/
  done
  tar -czf /tmp/steam-session.tar.gz -C /tmp/steam-session-backup .
'
ls -lh /tmp/steam-session.tar.gz
```

From your own computer:

```powershell
scp root@<machine-ip>:/tmp/steam-session.tar.gz .\machine-dev\steam-session.tar.gz
```

Then put `steam-session.tar.gz` in your private repo next to `start-steam.sh`. On a fresh machine, `./start-steam.sh` restores it automatically before launching Steam. This archive contains Steam login/session data, so do not commit it to a public repo. It intentionally does not include `steamapps` games.

You can also keep the archive elsewhere and pass:

```bash
STEAM_SESSION_URL="https://example.com/steam-session.tar.gz" ./start-machine-dev-gaming.sh
```

## Important

Do not install random `libnvidia-gl-*` packages on Machine.dev unless you are deliberately repairing a broken image. The host NVIDIA kernel driver and userspace libraries must match; mismatching them is what breaks GLX/Vulkan.
