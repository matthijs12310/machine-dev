#!/usr/bin/env python3
import io
import os
import time
from typing import Optional, Tuple

import mss
import numpy as np
from flask import Flask, Response, jsonify
from PIL import Image

try:
    import cv2
except ImportError:
    cv2 = None

app = Flask(__name__)

HOST = os.environ.get("QR_HOST", "0.0.0.0")
PORT = int(os.environ.get("QR_PORT", "8765"))

# Optional manual crop fallback:
# QR_CROP="x,y,w,h"
# Example:
# QR_CROP="1180,280,360,360"
QR_CROP = os.environ.get("QR_CROP", "")

NO_CACHE_HEADERS = {
    "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
    "Pragma": "no-cache",
    "Expires": "0",
}


def screenshot() -> Image.Image:
    with mss.mss() as sct:
        monitor = sct.monitors[1]
        img = sct.grab(monitor)
        return Image.frombytes("RGB", img.size, img.rgb)


def parse_crop(value: str) -> Optional[Tuple[int, int, int, int]]:
    if not value:
        return None

    try:
        x, y, w, h = [int(part.strip()) for part in value.split(",")]
        if w <= 0 or h <= 0:
            return None
        return x, y, w, h
    except Exception:
        return None


def crop_manual(img: Image.Image) -> Optional[Image.Image]:
    crop = parse_crop(QR_CROP)
    if not crop:
        return None

    x, y, w, h = crop
    return img.crop((x, y, x + w, y + h))


def detect_qr_crop(img: Image.Image) -> Optional[Image.Image]:
    if cv2 is None:
        return None

    rgb = np.array(img)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)

    detector = cv2.QRCodeDetector()
    ok, points = detector.detect(bgr)

    if not ok or points is None:
        return None

    points = points.reshape(-1, 2)

    x_min = int(points[:, 0].min())
    y_min = int(points[:, 1].min())
    x_max = int(points[:, 0].max())
    y_max = int(points[:, 1].max())

    width = x_max - x_min
    height = y_max - y_min

    if width < 50 or height < 50:
        return None

    pad = int(max(width, height) * 0.18)

    x1 = max(0, x_min - pad)
    y1 = max(0, y_min - pad)
    x2 = min(img.width, x_max + pad)
    y2 = min(img.height, y_max + pad)

    return img.crop((x1, y1, x2, y2))


def png_response(img: Image.Image) -> Response:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)

    return Response(
        buf.getvalue(),
        mimetype="image/png",
        headers=NO_CACHE_HEADERS,
    )


@app.get("/")
def index():
    return """
<!doctype html>
<html>
  <head>
    <title>Steam QR</title>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      body {
        font-family: system-ui, sans-serif;
        background: #111;
        color: white;
        display: grid;
        place-items: center;
        min-height: 100vh;
        margin: 0;
      }
      main {
        text-align: center;
      }
      img {
        max-width: min(85vw, 420px);
        background: white;
        padding: 12px;
        border-radius: 16px;
      }
      button {
        margin-top: 16px;
        padding: 10px 16px;
        border-radius: 10px;
        border: 0;
        cursor: pointer;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Steam QR Login</h1>
      <img id="qr" src="/qr.png?ts=0" />
      <br />
      <button onclick="reload()">Refresh</button>
    </main>
    <script>
      function reload() {
        document.getElementById("qr").src = "/qr.png?ts=" + Date.now();
      }
      setInterval(reload, 8000);
    </script>
  </body>
</html>
"""


@app.get("/health")
def health():
    return jsonify({"ok": True, "time": time.time()})


@app.get("/status")
def status():
    img = screenshot()
    qr = detect_qr_crop(img) or crop_manual(img)

    return jsonify({
        "ok": True,
        "qr_available": qr is not None,
        "auto_detection_available": cv2 is not None,
        "manual_crop_enabled": bool(QR_CROP),
        "crop": QR_CROP or None,
    })


@app.get("/qr.png")
def qr_png():
    img = screenshot()

    qr = detect_qr_crop(img)

    if qr is None:
        qr = crop_manual(img)

    if qr is None:
        return jsonify({
            "ok": False,
            "error": "No QR code detected. Use /debug.png to calibrate QR_CROP."
        }), 404, NO_CACHE_HEADERS

    return png_response(qr)


@app.get("/debug.png")
def debug_png():
    # Only use this while testing. It exposes the full remote desktop screenshot.
    return png_response(screenshot())


if __name__ == "__main__":
    app.run(host=HOST, port=PORT)
