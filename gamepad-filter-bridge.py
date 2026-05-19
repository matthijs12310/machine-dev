#!/usr/bin/env python3
import os
import select
import signal
import sys
import time

from evdev import AbsInfo, InputDevice, UInput, ecodes, list_devices


SOURCE_MATCHES = tuple(
    part.lower()
    for part in os.environ.get(
        "GAMEPAD_SOURCE_MATCH",
        "sunshine x-box,xbox,x-box,microsoft,controller,gamepad,pad",
    ).split(",")
    if part.strip()
)
FILTERED_NAME = os.environ.get("GAMEPAD_FILTER_NAME", "MachineDev Filtered Xbox Controller")
DEADZONE = int(os.environ.get("GAMEPAD_DEADZONE", "9000"))
WAIT_TIMEOUT = int(os.environ.get("GAMEPAD_WAIT_TIMEOUT", "120"))
GRAB_SOURCE = os.environ.get("GAMEPAD_GRAB", "1").lower() not in {"0", "false", "no"}
OUTPUT_HZ = float(os.environ.get("GAMEPAD_OUTPUT_HZ", "250"))
SMOOTHING = float(os.environ.get("GAMEPAD_SMOOTHING", "0.65"))

STICK_AXES = {
    ecodes.ABS_X,
    ecodes.ABS_Y,
    ecodes.ABS_RX,
    ecodes.ABS_RY,
}


def find_source() -> InputDevice:
    deadline = time.monotonic() + WAIT_TIMEOUT
    last_seen: list[tuple[str, str]] = []

    while time.monotonic() < deadline:
        devices = []
        for path in list_devices():
            try:
                dev = InputDevice(path)
            except OSError:
                continue

            name = dev.name or ""
            devices.append((path, name))
            lowered = name.lower()

            if name == FILTERED_NAME:
                continue
            if "mouse passthrough" in lowered or "keyboard passthrough" in lowered:
                continue
            if any(part in lowered for part in SOURCE_MATCHES):
                return dev

        last_seen = devices
        time.sleep(1)

    print("Timed out waiting for a gamepad source.", flush=True)
    print("Available input devices:", flush=True)
    for path, name in last_seen:
        print(f"  {path}: {name}", flush=True)
    raise SystemExit(1)


def filtered_absinfo(info: AbsInfo) -> AbsInfo:
    return AbsInfo(
        value=info.value,
        min=info.min,
        max=info.max,
        fuzz=info.fuzz,
        flat=max(info.flat, DEADZONE),
        resolution=info.resolution,
    )


def build_capabilities(source: InputDevice) -> dict:
    caps = source.capabilities(absinfo=True)
    caps.pop(ecodes.EV_SYN, None)
    caps.pop(ecodes.EV_FF, None)

    if ecodes.EV_ABS in caps:
        fixed_abs = []
        for code, info in caps[ecodes.EV_ABS]:
            if code in STICK_AXES and isinstance(info, AbsInfo):
                fixed_abs.append((code, filtered_absinfo(info)))
            else:
                fixed_abs.append((code, info))
        caps[ecodes.EV_ABS] = fixed_abs

    return caps


def apply_deadzone(code: int, value: int) -> int:
    if code in STICK_AXES and abs(value) < DEADZONE:
        return 0
    return value


def main() -> None:
    source = find_source()
    caps = build_capabilities(source)
    ui = UInput(caps, name=FILTERED_NAME, version=source.version)

    grabbed = False
    if GRAB_SOURCE:
        try:
            source.grab()
            grabbed = True
        except OSError as exc:
            print(f"WARNING: could not grab source device: {exc}", flush=True)

    def cleanup(*_: object) -> None:
        if grabbed:
            try:
                source.ungrab()
            except OSError:
                pass
        ui.close()
        source.close()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    print(f"source={source.path} {source.name}", flush=True)
    print(f"filtered={FILTERED_NAME}", flush=True)
    print(f"deadzone={DEADZONE}", flush=True)
    print(f"output_hz={OUTPUT_HZ}", flush=True)
    print(f"smoothing={SMOOTHING}", flush=True)
    print(f"grab_source={grabbed}", flush=True)

    axis_targets = {}
    axis_values = {}
    axis_last_sent = {}

    for code in STICK_AXES:
        try:
            value = apply_deadzone(code, source.absinfo(code).value)
        except OSError:
            continue
        axis_targets[code] = float(value)
        axis_values[code] = float(value)
        axis_last_sent[code] = value
        ui.write(ecodes.EV_ABS, code, value)
    ui.syn()

    tick = 1.0 / max(1.0, OUTPUT_HZ)
    next_tick = time.monotonic() + tick

    while True:
        timeout = max(0.0, next_tick - time.monotonic())
        ready, _, _ = select.select([source.fd], [], [], timeout)

        if ready:
            for ev in source.read():
                if ev.type == ecodes.EV_ABS and ev.code in STICK_AXES:
                    axis_targets[ev.code] = float(apply_deadzone(ev.code, ev.value))
                elif ev.type == ecodes.EV_SYN:
                    pass
                else:
                    ui.write(ev.type, ev.code, ev.value)
                    ui.syn()

        now = time.monotonic()
        if now < next_tick:
            continue

        changed = False
        alpha = min(1.0, max(0.0, SMOOTHING))
        for code, target in axis_targets.items():
            current = axis_values.get(code, target)
            if alpha >= 1.0:
                current = target
            else:
                current = current + (target - current) * alpha
                if abs(target - current) < 1.0:
                    current = target
            axis_values[code] = current

            sent = int(round(current))
            if sent != axis_last_sent.get(code):
                ui.write(ecodes.EV_ABS, code, sent)
                axis_last_sent[code] = sent
                changed = True

        if changed:
            ui.syn()

        next_tick = now + tick


if __name__ == "__main__":
    main()
