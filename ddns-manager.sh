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
  printf "\n按 Enter 返回菜单..."
  read -r _ || true
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "请使用 root 权限运行: sudo bash $0"
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  local cmd="$1"
  if ! command_exists "$cmd"; then
    error "缺少必要命令: $cmd"
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
  "index4": "public",
  "index6": "public",
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
  info "Cloudflare API Token 配置向导"
  read -r -s -p "请输入 Cloudflare API Token: " token
  printf "\n"
  if [[ -z "$token" ]]; then
    error "API Token 不能为空"
    return 1
  fi

  read -r -p "请输入 IPv4 域名, 多个用英文逗号分隔, 可留空: " ipv4_raw
  read -r -p "是否启用 IPv6? [y/N]: " enable_ipv6
  ipv6_raw=""
  if [[ "$enable_ipv6" == "y" || "$enable_ipv6" == "Y" ]]; then
    read -r -p "请输入 IPv6 域名, 多个用英文逗号分隔: " ipv6_raw
  fi

  if ! has_domain "$ipv4_raw" && ! has_domain "$ipv6_raw"; then
    error "IPv4 和 IPv6 域名不能同时为空"
    return 1
  fi

  read -r -p "TTL, 默认 600: " ttl
  ttl="${ttl:-600}"
  if ! [[ "$ttl" =~ ^[0-9]+$ ]]; then
    error "TTL 必须是数字"
    return 1
  fi

  read -r -p "是否开启 Cloudflare 代理 proxied? [y/N]: " proxied_answer
  proxied="false"
  if [[ "$proxied_answer" == "y" || "$proxied_answer" == "Y" ]]; then
    proxied="true"
  fi

  write_cloudflare_config "$token" "$ipv4_raw" "$ipv6_raw" "$ttl" "$proxied"
  success "配置已写入: $CONFIG_FILE"
}

redact_token_stream() {
  sed -E 's/("token"[[:space:]]*:[[:space:]]*")[^"]*(")/\1***REDACTED***\2/g'
}

show_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    warn "配置文件不存在: $CONFIG_FILE"
    return 0
  fi
  info "当前配置文件: $CONFIG_FILE"
  redact_token_stream < "$CONFIG_FILE"
  if confirm "是否显示包含 token 的完整配置?"; then
    cat "$CONFIG_FILE"
  fi
}

modify_config() {
  cat <<'MODIFY'
1. 重新运行 Cloudflare 配置向导
2. 使用编辑器手动编辑完整配置
0. 退出
MODIFY
  local choice editor
  read -r -p "请选择: " choice
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
          error "未找到编辑器, 请安装 nano/vi 或设置 EDITOR"
          return 1
        fi
      fi
      mkdir -p "$CONFIG_DIR"
      [[ -f "$CONFIG_FILE" ]] || printf '{}\n' > "$CONFIG_FILE"
      $editor "$CONFIG_FILE"
      chmod 600 "$CONFIG_FILE"
      ;;
    0) return 0 ;;
    *) warn "无效选择" ;;
  esac
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv7*) printf 'armv7' ;;
    *) error "不支持的系统架构: $machine"; return 1 ;;
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
    error "需要 curl 或 wget 用于下载"
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

# NewFuture/DDNS Linux releases are usually direct binaries, for example:
# ddns-glibc-linux_amd64. Prefer glibc for regular Linux servers.
patterns = [
    f'ddns-glibc-linux_{arch}',
    f'ddns-musl-linux_{arch}',
    f'linux_{arch}',
    f'linux-{arch}',
]
archive_suffixes = ('.tar.gz', '.tgz', '.zip', '.gz')

candidates = []
for asset in assets:
    lower = asset.get('name', '').lower()
    url = asset.get('browser_download_url', '')
    if url and any(pattern in lower for pattern in patterns):
        candidates.append((lower, url))

for pattern in patterns:
    for lower, url in candidates:
        if pattern in lower:
            print(url)
            sys.exit(0)

# Backward-compatible fallback for older archive-style assets.
for asset in assets:
    lower = asset.get('name', '').lower()
    url = asset.get('browser_download_url', '')
    if url and 'linux' in lower and arch in lower and lower.endswith(archive_suffixes):
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
    *)
      # Current NewFuture/DDNS Linux assets are direct executable binaries
      # such as ddns-glibc-linux_amd64. Treat unknown suffix as a binary.
      cp "$archive" "$workdir/ddns"
      chmod +x "$workdir/ddns"
      ;;
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
    error "未检测到 systemd/systemctl, 本脚本仅支持 systemd 系统"
    return 1
  fi

  arch="$(detect_arch)" || return 1
  info "检测到架构: $arch"

  api_file="$(mktemp "${TMP_DIR}/ddns-release.XXXXXX.json")"
  info "正在获取最新 Release 信息..."
  download_file "$(latest_release_api)" "$api_file" || return 1

  asset_url="$(find_asset_url "$arch" "$api_file")" || {
    error "未找到匹配 linux/$arch 的 Release 资产"
    return 1
  }
  info "正在下载: $asset_url"

  archive="${TMP_DIR}/$(basename "${asset_url%%\?*}")"
  download_file "$asset_url" "$archive" || return 1

  workdir="$(mktemp -d "${TMP_DIR}/ddns-extract.XXXXXX")"
  extract_binary "$archive" "$workdir" || return 1
  extracted="$(locate_extracted_ddns "$workdir")"
  if [[ -z "$extracted" ]]; then
    error "压缩包中未找到 ddns 二进制文件"
    return 1
  fi

  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
  install -m 0755 "$extracted" "$BIN_PATH"
  if [[ ! -x "$BIN_PATH" ]]; then
    error "安装失败, 二进制文件不可执行: $BIN_PATH"
    return 1
  fi

  write_service_file
  chmod 644 "$SERVICE_FILE"
  systemctl daemon-reload
  success "DDNS 已安装/更新到: $BIN_PATH"

  if confirm "是否现在配置 Cloudflare?"; then
    configure_cloudflare
  fi
}

require_systemctl() {
  if ! command_exists systemctl; then
    error "未找到 systemctl, 本功能需要 systemd"
    return 1
  fi
}

start_service() {
  require_systemctl || return 1
  systemctl enable --now "$APP_NAME"
  success "DDNS 已启动并设置开机自启"
}

stop_service() {
  require_systemctl || return 1
  systemctl stop "$APP_NAME"
  success "DDNS 已停止"
}

restart_service() {
  require_systemctl || return 1
  systemctl restart "$APP_NAME"
  success "DDNS 已重启"
}

status_service() {
  require_systemctl || return 1
  systemctl status "$APP_NAME" --no-pager || true
}

logs_service() {
  if ! command_exists journalctl; then
    error "未找到 journalctl"
    pause
    return 1
  fi
  info "按 Ctrl+C 退出日志查看"
  journalctl -u "$APP_NAME" -f
}

uninstall_ddns() {
  if ! confirm "确认卸载 DDNS? 这会删除程序和 systemd 服务"; then
    info "已取消卸载"
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
  success "已删除程序目录: $INSTALL_DIR"

  if [[ -e "$CONFIG_DIR" ]]; then
    if confirm "是否同时删除配置目录 $CONFIG_DIR?"; then
      rm -rf "$CONFIG_DIR"
      success "已删除配置目录: $CONFIG_DIR"
    else
      info "已保留配置目录: $CONFIG_DIR"
    fi
  fi
}

main_menu() {
  while true; do
    clear || true
    cat <<'MENU'
========================================
 NewFuture/DDNS Cloudflare 管理脚本
========================================
1. 安装/更新 DDNS
2. 配置 Cloudflare
3. 查看当前配置
4. 修改配置
5. 启动 DDNS
6. 停止 DDNS
7. 重启 DDNS
8. 查看运行状态
9. 查看日志
10. 卸载 DDNS
0. 退出
MENU
    printf "请选择: "
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
      *) warn "无效选择"; pause ;;
    esac
  done
}

main() {
  if [[ "$#" -gt 0 ]]; then
    error "本脚本仅支持交互式菜单, 请直接运行: sudo bash $0"
    exit 2
  fi
  require_root
  main_menu
}

main "$@"
