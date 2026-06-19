#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="ddns"
REPO="NewFuture/DDNS"
INSTALL_DIR="${DDNS_INSTALL_DIR:-/opt/ddns}"
CONFIG_DIR="${DDNS_CONFIG_DIR:-/etc/ddns}"
CONFIG_FILE="${DDNS_CONFIG_FILE:-${CONFIG_DIR}/config.json}"
SERVICE_FILE="${DDNS_SERVICE_FILE:-/etc/systemd/system/ddns.service}"
BIN_PATH="${INSTALL_DIR}/ddns"
TMP_DIR="${TMPDIR:-/tmp}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

pause() {
  printf "\nPress Enter to return to menu..."
  read -r _ || true
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "Please run as root: sudo bash $0"
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  local cmd="$1"
  if ! command_exists "$cmd"; then
    error "Missing required command: $cmd"
    return 1
  fi
}

confirm() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N]: " answer || return 1
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

split_domains_json() {
  local raw="$1"
  local first=1
  local item trimmed
  printf '['
  IFS=',' read -ra parts <<< "$raw"
  for item in "${parts[@]}"; do
    trimmed="$(printf '%s' "$item" | sed 's/^ *//;s/ *$//')"
    [[ -z "$trimmed" ]] && continue
    if [[ $first -eq 0 ]]; then printf ','; fi
    printf '"%s"' "$(json_escape "$trimmed")"
    first=0
  done
  printf ']'
}

has_domain() {
  local raw="$1"
  local item trimmed
  IFS=',' read -ra parts <<< "$raw"
  for item in "${parts[@]}"; do
    trimmed="$(printf '%s' "$item" | sed 's/^ *//;s/ *$//')"
    [[ -n "$trimmed" ]] && return 0
  done
  return 1
}

write_cloudflare_config() {
  local token="$1"
  local ipv4_raw="$2"
  local ipv6_raw="$3"
  local ttl="$4"
  local proxied="$5"
  local ipv4_json ipv6_json tmp_file

  ipv4_json="$(split_domains_json "$ipv4_raw")"
  ipv6_json="$(split_domains_json "$ipv6_raw")"

  mkdir -p "$CONFIG_DIR"
  tmp_file="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")"
  cat > "$tmp_file" <<JSON
{
  "\$schema": "https://ddns.newfuture.cc/schema/v4.0.json",
  "dns": "cloudflare",
  "id": "",
  "token": "$(json_escape "$token")",
  "index4": "default",
  "index6": "default",
  "ipv4": ${ipv4_json},
  "ipv6": ${ipv6_json},
  "ttl": ${ttl},
  "proxy": ${proxied}
}
JSON
  mv "$tmp_file" "$CONFIG_FILE"
  chown root:root "$CONFIG_FILE" 2>/dev/null || true
  chmod 600 "$CONFIG_FILE"
}

configure_cloudflare() {
  local token ipv4_raw enable_ipv6 ipv6_raw ttl proxied_answer proxied
  info "Cloudflare API Token setup wizard"
  read -r -s -p "Enter Cloudflare API Token: " token
  printf "\n"
  if [[ -z "$token" ]]; then
    error "API Token cannot be empty"
    return 1
  fi

  read -r -p "Enter IPv4 domains, comma separated, or leave empty: " ipv4_raw
  read -r -p "Enable IPv6? [y/N]: " enable_ipv6
  ipv6_raw=""
  if [[ "$enable_ipv6" == "y" || "$enable_ipv6" == "Y" ]]; then
    read -r -p "Enter IPv6 domains, comma separated: " ipv6_raw
  fi

  if ! has_domain "$ipv4_raw" && ! has_domain "$ipv6_raw"; then
    error "IPv4 and IPv6 domain lists cannot both be empty"
    return 1
  fi

  read -r -p "TTL, default 600: " ttl
  ttl="${ttl:-600}"
  if ! [[ "$ttl" =~ ^[0-9]+$ ]]; then
    error "TTL must be a number"
    return 1
  fi

  read -r -p "Enable Cloudflare proxied mode? [y/N]: " proxied_answer
  proxied="false"
  if [[ "$proxied_answer" == "y" || "$proxied_answer" == "Y" ]]; then
    proxied="true"
  fi

  write_cloudflare_config "$token" "$ipv4_raw" "$ipv6_raw" "$ttl" "$proxied"
  success "Config written to: $CONFIG_FILE"
}

redact_token_stream() {
  sed -E 's/("token"[[:space:]]*:[[:space:]]*")[^"]*(")/\1***REDACTED***\2/g'
}

show_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    warn "Config file not found: $CONFIG_FILE"
    return 0
  fi
  info "Current config file: $CONFIG_FILE"
  redact_token_stream < "$CONFIG_FILE"
  if confirm "Show full config including token?"; then
    cat "$CONFIG_FILE"
  fi
}

modify_config() {
  cat <<'MODIFY'
1. Re-run Cloudflare setup wizard
2. Edit full config with editor
0. Exit
MODIFY
  local choice editor
  read -r -p "Select: " choice
  case "$choice" in
    1) configure_cloudflare ;;
    2)
      editor="${EDITOR:-}"
      if [[ -z "$editor" ]]; then
        if command_exists nano; then
          editor="nano"
        elif command_exists vi; then
          editor="vi"
        else
          error "No editor found. Install nano/vi or set EDITOR"
          return 1
        fi
      fi
      mkdir -p "$CONFIG_DIR"
      [[ -f "$CONFIG_FILE" ]] || printf '{}\n' > "$CONFIG_FILE"
      $editor "$CONFIG_FILE"
      chmod 600 "$CONFIG_FILE"
      ;;
    0) return 0 ;;
    *) warn "Invalid choice" ;;
  esac
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv7*) printf 'armv7' ;;
    *) error "Unsupported architecture: $machine"; return 1 ;;
  esac
}

latest_release_api() {
  printf 'https://api.github.com/repos/%s/releases/latest' "$REPO"
}

download_file() {
  local url="$1"
  local output="$2"
  if command_exists curl; then
    curl -fsSL "$url" -o "$output"
  elif command_exists wget; then
    wget -q "$url" -O "$output"
  else
    error "curl or wget is required for download"
    return 1
  fi
}

find_asset_url() {
  local arch="$1"
  local api_json="$2"
  python3 - "$arch" "$api_json" <<'PY'
import json
import sys
arch = sys.argv[1]
path = sys.argv[2]
data = json.load(open(path, encoding='utf-8'))
assets = data.get('assets', [])
keywords = ['linux', arch]
for asset in assets:
    name = asset.get('name', '').lower()
    url = asset.get('browser_download_url', '')
    if all(k in name for k in keywords) and (name.endswith('.tar.gz') or name.endswith('.tgz') or name.endswith('.zip') or name.endswith('.gz')):
        print(url)
        sys.exit(0)
print('', end='')
sys.exit(1)
PY
}

extract_binary() {
  local archive="$1"
  local workdir="$2"
  mkdir -p "$workdir"
  case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$workdir" ;;
    *.zip) unzip -q "$archive" -d "$workdir" ;;
    *.gz)
      local out="$workdir/ddns"
      gzip -dc "$archive" > "$out"
      chmod +x "$out"
      ;;
    *) error "Unsupported archive format: $archive"; return 1 ;;
  esac
}

locate_extracted_ddns() {
  local workdir="$1"
  find "$workdir" -type f \( -name 'ddns' -o -name 'DDNS' \) -print -quit
}

write_service_file() {
  cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=NewFuture DDNS Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_PATH} -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE
}

install_or_update() {
  local arch api_file asset_url archive workdir extracted
  require_command uname || return 1
  require_command python3 || return 1
  require_command find || return 1

  if ! command_exists systemctl; then
    error "systemd/systemctl not found. This script supports systemd systems only"
    return 1
  fi

  arch="$(detect_arch)" || return 1
  info "Detected architecture: $arch"

  api_file="$(mktemp "${TMP_DIR}/ddns-release.XXXXXX.json")"
  info "Fetching latest Release metadata..."
  download_file "$(latest_release_api)" "$api_file" || return 1

  asset_url="$(find_asset_url "$arch" "$api_file")" || {
    error "No matching linux/$arch Release asset found"
    return 1
  }
  info "Downloading: $asset_url"

  archive="$(mktemp "${TMP_DIR}/ddns-archive.XXXXXX")"
  download_file "$asset_url" "$archive" || return 1

  workdir="$(mktemp -d "${TMP_DIR}/ddns-extract.XXXXXX")"
  extract_binary "$archive" "$workdir" || return 1
  extracted="$(locate_extracted_ddns "$workdir")"
  if [[ -z "$extracted" ]]; then
    error "No ddns binary found in the archive"
    return 1
  fi

  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
  install -m 0755 "$extracted" "$BIN_PATH"
  if [[ ! -x "$BIN_PATH" ]]; then
    error "Install failed, binary is not executable: $BIN_PATH"
    return 1
  fi

  write_service_file
  chmod 644 "$SERVICE_FILE"
  systemctl daemon-reload
  success "DDNS installed/updated at: $BIN_PATH"

  if confirm "Configure Cloudflare now?"; then
    configure_cloudflare
  fi
}

require_systemctl() {
  if ! command_exists systemctl; then
    error "systemctl not found. This feature requires systemd"
    return 1
  fi
}

start_service() {
  require_systemctl || return 1
  systemctl enable --now "$APP_NAME"
  success "DDNS started and enabled at boot"
}

stop_service() {
  require_systemctl || return 1
  systemctl stop "$APP_NAME"
  success "DDNS stopped"
}

restart_service() {
  require_systemctl || return 1
  systemctl restart "$APP_NAME"
  success "DDNS restarted"
}

status_service() {
  require_systemctl || return 1
  systemctl status "$APP_NAME" --no-pager || true
}

logs_service() {
  if ! command_exists journalctl; then
    error "journalctl not found"
    pause
    return 1
  fi
  info "Press Ctrl+C to stop following logs"
  journalctl -u "$APP_NAME" -f
}

uninstall_ddns() {
  if ! confirm "Uninstall DDNS? This removes the program and systemd service"; then
    info "Uninstall canceled"
    return 0
  fi

  if command_exists systemctl; then
    systemctl stop "$APP_NAME" 2>/dev/null || true
    systemctl disable "$APP_NAME" 2>/dev/null || true
  fi

  rm -f "$SERVICE_FILE"
  if command_exists systemctl; then
    systemctl daemon-reload 2>/dev/null || true
  fi

  rm -rf "$INSTALL_DIR"
  success "Removed install directory: $INSTALL_DIR"

  if [[ -e "$CONFIG_DIR" ]]; then
    if confirm "Also remove config directory $CONFIG_DIR?"; then
      rm -rf "$CONFIG_DIR"
      success "Removed config directory: $CONFIG_DIR"
    else
      info "Kept config directory: $CONFIG_DIR"
    fi
  fi
}

main_menu() {
  while true; do
    clear || true
    cat <<'MENU'
========================================
 NewFuture/DDNS Cloudflare Manager
========================================
1. Install/Update DDNS
2. Configure Cloudflare
3. Show current config
4. Modify config
5. Start DDNS
6. Stop DDNS
7. Restart DDNS
8. Show service status
9. Show logs
10. Uninstall DDNS
0. Exit
MENU
    printf "Select: "
    read -r choice || exit 0
    case "$choice" in
      1) install_or_update; pause ;;
      2) configure_cloudflare; pause ;;
      3) show_config; pause ;;
      4) modify_config; pause ;;
      5) start_service; pause ;;
      6) stop_service; pause ;;
      7) restart_service; pause ;;
      8) status_service; pause ;;
      9) logs_service ;;
      10) uninstall_ddns; pause ;;
      0) exit 0 ;;
      *) warn "Invalid choice"; pause ;;
    esac
  done
}

main() {
  if [[ "$#" -gt 0 ]]; then
    error "This version is menu-only. Run: sudo bash $0"
    exit 2
  fi
  require_root
  main_menu
}

main "$@"
