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
git clone <your-github-repo-url> machine-dev-gaming-kit
cd machine-dev-gaming-kit
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

## Important

Do not install random `libnvidia-gl-*` packages on Machine.dev unless you are deliberately repairing a broken image. The host NVIDIA kernel driver and userspace libraries must match; mismatching them is what breaks GLX/Vulkan.
