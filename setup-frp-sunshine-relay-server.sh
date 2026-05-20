#!/usr/bin/env bash
set -euo pipefail

FRP_VERSION="${FRP_VERSION:-0.68.1}"
FRP_BIND_PORT="${FRP_BIND_PORT:-443}"
FRP_TOKEN="${FRP_TOKEN:-}"
FRP_CONFIG_DIR="${FRP_CONFIG_DIR:-/etc/frp}"
FRP_SERVICE_NAME="${FRP_SERVICE_NAME:-frps}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
  fi
}

frp_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l) echo arm ;;
    *)
      echo "ERROR: unsupported FRP architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

install_basics() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl tar
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl tar
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl tar
  fi
}

install_frp_server() {
  if command -v frps >/dev/null 2>&1; then
    return 0
  fi

  local arch
  local archive
  local url
  local tmpdir
  arch="$(frp_arch)"
  archive="frp_${FRP_VERSION}_linux_${arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${archive}"
  tmpdir="$(mktemp -d)"

  echo "Installing FRP server ${FRP_VERSION} (${arch})"
  curl -fL --retry 3 --retry-delay 2 -o "${tmpdir}/${archive}" "$url"
  tar -xzf "${tmpdir}/${archive}" -C "$tmpdir"
  install -m 0755 "${tmpdir}/frp_${FRP_VERSION}_linux_${arch}/frps" /usr/local/bin/frps
  rm -rf "$tmpdir"
}

write_config() {
  local frp_token
  frp_token="$(printf '%s' "$FRP_TOKEN" | tr -d '\r\n')"

  if [ -z "$frp_token" ]; then
    echo "ERROR: set FRP_TOKEN first, for example:"
    echo "  sudo FRP_TOKEN='your-long-random-token' $0"
    exit 1
  fi

  mkdir -p "$FRP_CONFIG_DIR"
  chmod 700 "$FRP_CONFIG_DIR" 2>/dev/null || true

  cat >"${FRP_CONFIG_DIR}/frps.toml" <<EOF
bindPort = ${FRP_BIND_PORT}

auth.method = "token"
auth.token = "${frp_token}"

transport.tcpMux = true
EOF

  chmod 600 "${FRP_CONFIG_DIR}/frps.toml"

  cat >"/etc/systemd/system/${FRP_SERVICE_NAME}.service" <<EOF
[Unit]
Description=FRP server for Sunshine relay
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/frps -c ${FRP_CONFIG_DIR}/frps.toml
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
  systemctl daemon-reload
  systemctl enable --now "$FRP_SERVICE_NAME"
  systemctl restart "$FRP_SERVICE_NAME"

  echo
  echo "FRP relay server started."
  echo "Open these inbound ports in the EC2 security group:"
  echo "  TCP ${FRP_BIND_PORT}"
  echo "  TCP 47984, 47989, 47990, 48010"
  echo "  UDP 47998, 47999, 48000, 48002"
  echo
  systemctl status "$FRP_SERVICE_NAME" --no-pager || true
  ss -lntup | grep -E ":(${FRP_BIND_PORT}|47984|47989|47990|48010|47998|47999|48000|48002)\\b" || true
}

main() {
  need_root
  install_basics
  install_frp_server
  write_config
  start_service
}

main "$@"
