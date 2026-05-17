#!/usr/bin/env python3
import ctypes
import os
import re
import subprocess
import time

from evdev import InputDevice, ecodes, list_devices


DISPLAY = os.environ.get("DISPLAY", ":99")
WAIT_TIMEOUT = int(os.environ.get("INPUT_WAIT_TIMEOUT", "120"))


class XTestInput:
    def __init__(self, display_name: str):
        self.x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
        self.xtst = ctypes.cdll.LoadLibrary("libXtst.so.6")
        self.x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x11.XOpenDisplay.restype = ctypes.c_void_p
        self.x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
        self.x11.XStringToKeysym.restype = ctypes.c_ulong
        self.x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        self.x11.XKeysymToKeycode.restype = ctypes.c_uint
        self.x11.XFlush.argtypes = [ctypes.c_void_p]
        self.xtst.XTestFakeRelativeMotionEvent.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_ulong,
        ]
        self.xtst.XTestFakeButtonEvent.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint,
            ctypes.c_int,
            ctypes.c_ulong,
        ]
        self.xtst.XTestFakeKeyEvent.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint,
            ctypes.c_int,
            ctypes.c_ulong,
        ]
        self.display = self.x11.XOpenDisplay(display_name.encode())
        if not self.display:
            raise RuntimeError(f"Could not open X display {display_name}")

    def flush(self) -> None:
        self.x11.XFlush(self.display)

    def move(self, dx: int, dy: int) -> None:
        if dx or dy:
            self.xtst.XTestFakeRelativeMotionEvent(self.display, dx, dy, 0)

    def button(self, button: int, down: bool) -> None:
        self.xtst.XTestFakeButtonEvent(self.display, button, int(down), 0)

    def key(self, name: str, down: bool) -> None:
        keysym = self.x11.XStringToKeysym(name.encode())
        if not keysym:
            return
        keycode = self.x11.XKeysymToKeycode(self.display, keysym)
        if keycode:
            self.xtst.XTestFakeKeyEvent(self.display, keycode, int(down), 0)


class XDoToolInput:
    def key(self, name: str, down: bool) -> None:
        command = "keydown" if down else "keyup"
        subprocess.run(
            ["xdotool", command, name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def find_exact(name: str, required: bool = True) -> InputDevice | None:
    devices = []
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        devices.append((path, dev.name))
        if dev.name == name:
            return dev
    if not required:
        return None
    print("Available input devices:", flush=True)
    for path, dev_name in devices:
        print(f"  {path}: {dev_name}", flush=True)
    raise SystemExit(f"Missing exact input device: {name}")


def wait_for_passthrough() -> None:
    deadline = time.monotonic() + WAIT_TIMEOUT
    while time.monotonic() < deadline:
        ensure_event_nodes()
        names = []
        for path in list_devices():
            try:
                names.append(InputDevice(path).name)
            except OSError:
                continue
        if "Keyboard passthrough" in names and (
            "Mouse passthrough" in names or os.environ.get("BRIDGE_MOUSE", "xtest") in {"0", "false", "False", "no"}
        ):
            return
        time.sleep(1)
    print("Timed out waiting for Sunshine/Moonlight passthrough input devices.", flush=True)


KEYSYM = {
    ecodes.KEY_ESC: "Escape",
    ecodes.KEY_TAB: "Tab",
    ecodes.KEY_ENTER: "Return",
    ecodes.KEY_BACKSPACE: "BackSpace",
    ecodes.KEY_SPACE: "space",
    ecodes.KEY_LEFTSHIFT: "Shift_L",
    ecodes.KEY_RIGHTSHIFT: "Shift_R",
    ecodes.KEY_LEFTCTRL: "Control_L",
    ecodes.KEY_RIGHTCTRL: "Control_R",
    ecodes.KEY_LEFTALT: "Alt_L",
    ecodes.KEY_RIGHTALT: "Alt_R",
    ecodes.KEY_UP: "Up",
    ecodes.KEY_DOWN: "Down",
    ecodes.KEY_LEFT: "Left",
    ecodes.KEY_RIGHT: "Right",
    ecodes.KEY_DELETE: "Delete",
    ecodes.KEY_HOME: "Home",
    ecodes.KEY_END: "End",
    ecodes.KEY_PAGEUP: "Page_Up",
    ecodes.KEY_PAGEDOWN: "Page_Down",
    ecodes.KEY_MINUS: "minus",
    ecodes.KEY_EQUAL: "equal",
    ecodes.KEY_LEFTBRACE: "bracketleft",
    ecodes.KEY_RIGHTBRACE: "bracketright",
    ecodes.KEY_BACKSLASH: "backslash",
    ecodes.KEY_SEMICOLON: "semicolon",
    ecodes.KEY_APOSTROPHE: "apostrophe",
    ecodes.KEY_COMMA: "comma",
    ecodes.KEY_DOT: "period",
    ecodes.KEY_SLASH: "slash",
    ecodes.KEY_GRAVE: "grave",
}

for char in "abcdefghijklmnopqrstuvwxyz":
    KEYSYM[getattr(ecodes, f"KEY_{char.upper()}")] = char
for idx, char in enumerate("1234567890", start=2):
    code = getattr(ecodes, f"KEY_{char}")
    KEYSYM[code] = char
for number in range(1, 13):
    KEYSYM[getattr(ecodes, f"KEY_F{number}")] = f"F{number}"


def ensure_event_nodes() -> None:
    os.makedirs("/dev/input", exist_ok=True)
    try:
        proc_devices = open("/proc/bus/input/devices", encoding="utf-8", errors="ignore").read()
    except OSError:
        proc_devices = ""
    for event_id in sorted({int(match) for match in re.findall(r"\bevent(\d+)\b", proc_devices)}):
        path = f"/dev/input/event{event_id}"
        if not os.path.exists(path):
            try:
                os.mknod(path, 0o666 | 0o20000, os.makedev(13, 64 + event_id))
            except FileExistsError:
                pass
            except PermissionError:
                pass
    existing = set(list_devices())
    for n in range(4, 16):
        path = f"/dev/input/event{n}"
        if path not in existing and os.path.exists(path):
            # Stale manual node without a real kernel input device behind it.
            try:
                os.unlink(path)
            except OSError:
                pass
        if path in existing and not os.path.exists(path):
            try:
                os.mknod(path, 0o666 | 0o20000, os.makedev(13, 64 + n))
            except FileExistsError:
                pass
            except PermissionError:
                pass
    os.system("chmod -R a+rw /dev/input /dev/uinput 2>/dev/null || true")


def main() -> None:
    wait_for_passthrough()
    ensure_event_nodes()
    mouse_mode = os.environ.get("BRIDGE_MOUSE", "xtest")
    prime_mouse = mouse_mode in {"prime", "Prime", "PRIME", "once", "Once", "ONCE"}
    bridge_mouse = mouse_mode not in {"0", "false", "False", "no"} and not prime_mouse
    keyboard_mode = os.environ.get("BRIDGE_KEYBOARD", "xdotool")
    bridge_keyboard = keyboard_mode not in {"0", "false", "False", "no"}
    mouse = find_exact("Mouse passthrough") if bridge_mouse or prime_mouse else None
    keyboard = find_exact("Keyboard passthrough") if bridge_keyboard else None
    x = XTestInput(DISPLAY)
    key_input = XDoToolInput() if keyboard_mode in {"xdotool", "XDOTool", "XDOTOOL"} else x
    print(f"DISPLAY={DISPLAY}", flush=True)
    if mouse and bridge_mouse:
        print(f"mouse={mouse.path} {mouse.name}", flush=True)
    elif mouse and prime_mouse:
        print(f"mouse primed={mouse.path} {mouse.name}", flush=True)
    else:
        print("mouse bridge disabled", flush=True)
    if keyboard:
        print(f"keyboard={keyboard.path} {keyboard.name}", flush=True)
    else:
        print("keyboard bridge disabled", flush=True)

    buttons = {
        ecodes.BTN_LEFT: 1,
        ecodes.BTN_MIDDLE: 2,
        ecodes.BTN_RIGHT: 3,
        ecodes.BTN_SIDE: 8,
        ecodes.BTN_EXTRA: 9,
    }

    if prime_mouse and mouse:
        mouse.close()

    if mouse and keyboard and bridge_mouse:
        pid = os.fork()
    elif mouse and bridge_mouse:
        pid = 0
    else:
        pid = 1

    if pid == 0 and mouse and bridge_mouse:
        dx = dy = 0
        last_flush = time.monotonic()
        for ev in mouse.read_loop():
            if ev.type == ecodes.EV_REL:
                if ev.code == ecodes.REL_X:
                    dx += ev.value
                elif ev.code == ecodes.REL_Y:
                    dy += ev.value
                elif ev.code == ecodes.REL_WHEEL and ev.value:
                    for _ in range(abs(ev.value)):
                        x.button(4 if ev.value > 0 else 5, True)
                        x.button(4 if ev.value > 0 else 5, False)
                    x.flush()
            elif ev.type == ecodes.EV_KEY and ev.code in buttons:
                if dx or dy:
                    x.move(dx, dy)
                    dx = dy = 0
                x.button(buttons[ev.code], ev.value != 0)
                x.flush()
            elif ev.type == ecodes.EV_SYN:
                if dx or dy:
                    x.move(dx, dy)
                    x.flush()
                    dx = dy = 0
                    last_flush = time.monotonic()
            if dx or dy and time.monotonic() - last_flush > 0.008:
                x.move(dx, dy)
                x.flush()
                dx = dy = 0
                last_flush = time.monotonic()
    elif keyboard:
        for ev in keyboard.read_loop():
            if ev.type == ecodes.EV_KEY and ev.value in (0, 1):
                name = KEYSYM.get(ev.code)
                if name:
                    try:
                        key_input.key(name, ev.value == 1)
                        if key_input is x:
                            x.flush()
                    except Exception as exc:
                        print(f"keyboard bridge ignored {name} down={ev.value == 1}: {exc}", flush=True)


if __name__ == "__main__":
    main()
