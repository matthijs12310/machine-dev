# Machine.dev Gaming Kit

Minimal scripts for a fresh Machine.dev GPU gaming box with NVIDIA Xorg, Sunshine, Moonlight input passthrough, and Steam.

## Files

- `start-machine-dev-gaming.sh` - all-in-one launcher for Xorg, Sunshine, input bridge, and Steam.
- `start-machine-dev-wolf.sh` - alternative Games on Whales/Wolf stack for Moonlight.
- `start-machine-dev-steam-headless.sh` - experimental Steam Headless Docker stack.
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

## Alternative Wolf Stack

Wolf is a separate Moonlight/GameStream server. Do not run it at the same time as Sunshine, because they use overlapping ports and input/audio/GPU devices.

```bash
cd /root/machine-dev
./start-machine-dev-wolf.sh
```

The Wolf launcher:

- stops the Sunshine/Xorg/Steam stack by default
- enables `nvidia_drm modeset=1` when possible
- prepares `/dev/uinput` and `/dev/uhid`
- builds a matching NVIDIA driver volume from the Tesla/Data Center `.run` installer
- writes the NVIDIA Vulkan ICD into that volume so Proton/DXVK sees NVIDIA instead of `llvmpipe`
- starts Wolf with that driver volume mounted at `/usr/nvidia`
- patches the Wolf Steam app with `NVIDIA_DRIVER_VOLUME_NAME`, `VK_ICD_FILENAMES`, and `LD_LIBRARY_PATH`
- builds a small local `wolf-ui-opengl:local` image so Wolf UI avoids the Godot Vulkan black-screen issue

The manual NVIDIA driver volume is intentional. On this Machine.dev/AWS NVIDIA setup the toolkit-only route can expose the GPU to containers but still break Vulkan presentation, which shows up as black Firefox hardware rendering, crashing `vkcube`, or Proton/DXVK games with audio/input but no video.

Wolf stores Moonlight pairing state in `/etc/wolf/cfg/config.toml` under `paired_clients`, together with a host `uuid`. It also generates `/etc/wolf/cfg/cert.pem` and `/etc/wolf/cfg/key.pem`. If `wolf/cfg/` exists in this repo, `start-machine-dev-wolf.sh` restores it to `/etc/wolf/cfg/` before Wolf starts.

Useful Wolf logs:

```bash
docker logs -f wolf
docker logs -f "$(docker ps -a --format '{{.Names}}' | grep '^Wolf-UI_' | tail -1)"
tail -f /tmp/machine-dev-wolf/nvidia-driver-volume-build.log
```

If the host NVIDIA driver changes, rebuild the driver volume:

```bash
REBUILD_NVIDIA_DRIVER_VOLUME=1 ./start-machine-dev-wolf.sh
```

To save Wolf pairing state after pairing Moonlight once:

```bash
cd /root/machine-dev
mkdir -p wolf/cfg
cp -a /etc/wolf/cfg/config.toml /etc/wolf/cfg/cert.pem /etc/wolf/cfg/key.pem wolf/cfg/
chmod 600 wolf/cfg/key.pem
```

Then copy or commit `wolf/cfg/` back to your private repo. This contains pairing/auth material, so keep the repo private.

The GitHub Actions workflow defaults to `gaming_stack=none`, so it only brings up SSH/Tailscale unless you choose `wolf`, `sunshine`, or `steam-headless`.

## Steam Headless Hybrid Stack

Use this when you want to try the Steam Headless Docker image instead of the local Sunshine stack or Wolf:

```bash
cd /root/machine-dev
./start-machine-dev-steam-headless.sh
```

The default launcher mode is `STEAM_HEADLESS_MODE=hybrid`. This is the Machine.dev/AWS L4 path that avoids Steam Headless' broken NVIDIA dummy-Xorg Vulkan presentation:

- installs Docker Compose if needed
- installs host Xorg/Vulkan/X11 utilities
- starts host Xorg on `:99`
- writes host Xorg input catchall rules for Sunshine keyboard/mouse/touch passthrough
- writes `/opt/container-services/steam-headless/docker-compose.yml` and `.env`
- creates persistent data under `/opt/container-data/steam-headless`
- detects the host NVIDIA driver version
- downloads the matching Tesla/Data Center NVIDIA `.run` installer into `/home/default/Downloads` inside the container's persistent home
- starts Steam Headless in `MODE=secondary`
- patches the Steam Headless Sunshine/udev Xorg restart-loop workaround
- starts XFCE, Sunshine, and Steam manually inside the container against host display `:99`
- starts Steam with `PULSE_SERVER=unix:/tmp/.X11-unix/run/pulse/native`, so game audio reaches Sunshine
- uses `/mnt/games/SteamLibrary` as the local Steam game library

This cache step matters on Machine.dev/AWS L4 because Steam Headless tries the generic XFree86 NVIDIA URL first, while the matching L4 driver can live under NVIDIA's Tesla/Data Center download path.

Useful commands:

```bash
cd /opt/container-services/steam-headless
docker compose logs -f --tail=200
docker exec -it SteamHeadless bash
```

Default hybrid access:

- Sunshine: `https://<tailscale-ip>:47990`
- Sunshine login: `admin` / `admin`

Useful hybrid checks:

```bash
DISPLAY=:99 xrandr --query
DISPLAY=:99 vkcube
docker exec -u default SteamHeadless bash -lc 'PULSE_SERVER=unix:/tmp/.X11-unix/run/pulse/native pactl list short sink-inputs'
docker exec SteamHeadless tail -f /home/default/.cache/log/sunshine-hostx.log
docker exec SteamHeadless tail -f /home/default/.cache/log/steam-hostx.log
```

Use `DISPLAY_REFRESH=144 ./start-machine-dev-steam-headless.sh` to try 144 Hz. The default is 120 Hz because it is more reliable with NVIDIA dummy/VGX modes. Use `STEAM_HEADLESS_MODE=primary` if you want the old all-in-container Steam Headless behavior with noVNC, but Proton/DXVK Vulkan presentation may fail there on Machine.dev L4.

The GitHub Actions workflow can also start it directly with `gaming_stack=steam-headless`. Use `gaming_stack=none` if you only want SSH/Tailscale and prefer to start stacks manually. The workflow keepalive default is 350 minutes and the runner disk defaults to 300 GB for local game installs.

### Faster Steam Headless Image

The repo includes `steam-headless-machine-dev.Dockerfile`, which extends `josh5/steam-headless:latest` with Firefox/Chromium helpers and the Steam i386 bootstrap dependencies. This keeps Steam Headless behavior intact while avoiding most container `apt` work on each fresh Machine.dev instance.

This only speeds up packages that belong inside the Steam Headless container. The host still needs Xorg/Vulkan/input utilities for the hybrid `:99` display path, so the SSH workflow preinstalls those host packages before launching the stack.

Build and publish it from GitHub Actions by running the `Build Steam Headless image` workflow. The SSH workflow uses this image automatically for `gaming_stack=steam-headless`:

```text
ghcr.io/<owner>/<repo>/steam-headless-machine-dev:latest
```

For manual runs, pass the image explicitly:

```bash
STEAM_HEADLESS_IMAGE=ghcr.io/<owner>/<repo>/steam-headless-machine-dev:latest \
  ./start-machine-dev-steam-headless.sh
```

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
