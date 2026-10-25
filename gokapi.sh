#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly GOKAPI_VERSION="2.2.4"
readonly SERVICE_NAME="gokapi"
readonly SERVICE_USER="gokapi"
readonly BINARY_PATH="/usr/local/bin/gokapi"
readonly UNIT_PATH="/etc/systemd/system/gokapi.service"
readonly ENV_PATH="/etc/default/gokapi"
readonly CONFIG_DIR="/etc/gokapi"
readonly DATA_DIR="/var/lib/gokapi"
readonly DEFAULT_PORT="${GOKAPI_PORT:-53842}"

tmp_dir=""

log() { printf '[gokapi] %s\n' "$*"; }
die() { printf '[gokapi] 错误：%s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
    rm -rf -- "$tmp_dir"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Gokapi Debian 12+ 一键管理脚本

用法：
  gokapi.sh install           安装或覆盖更新 Gokapi
  gokapi.sh update            更新到脚本固定的稳定版本
  gokapi.sh status            查看 systemd 服务状态
  gokapi.sh uninstall         卸载程序，保留配置和文件
  gokapi.sh purge --yes       完全卸载，并删除配置和全部文件
EOF
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "请使用 root 运行，或在命令前加 sudo。"
}

check_debian_version() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == "debian" ]] ||
    die "本脚本仅支持 Debian；当前系统为 ${PRETTY_NAME:-未知}。"
  [[ ${VERSION_ID:-} =~ ^[0-9]+([.][0-9]+)?$ ]] ||
    die "无法识别 Debian 版本：${VERSION_ID:-未知}。"
  local major_version="${VERSION_ID%%.*}"
  ((10#${major_version} >= 12)) ||
    die "本脚本仅支持 Debian 12 及以上版本；当前系统为 ${PRETTY_NAME:-未知}。"
  command -v systemctl >/dev/null 2>&1 || die "未检测到 systemd。"
}

validate_port() {
  [[ "$DEFAULT_PORT" =~ ^[0-9]+$ ]] ||
    die "GOKAPI_PORT 必须是 1 到 65535 之间的整数。"
  ((DEFAULT_PORT >= 1 && DEFAULT_PORT <= 65535)) ||
    die "GOKAPI_PORT 必须是 1 到 65535 之间的整数。"
}

install_dependencies() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v unzip >/dev/null 2>&1 || missing+=(unzip)
  dpkg-query -W -f='${Status}' ca-certificates 2>/dev/null | grep -q 'ok installed' || missing+=(ca-certificates)
  if ((${#missing[@]} > 0)); then
    log "安装依赖：${missing[*]}"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  fi
}

release_for_arch() {
  local deb_arch
  deb_arch="$(dpkg --print-architecture)"
  case "$deb_arch" in
    amd64)
      RELEASE_ARCH="amd64"
      RELEASE_SHA256="51dbf724c94f8afa0b40fb1ef63a1fe418e7996e7b9536e1f0a5da695b8e18ef"
      ;;
    arm64)
      RELEASE_ARCH="arm64"
      RELEASE_SHA256="9f82cfb96fc48ac9bdfb94584dc6ba4648de1ac4fcd1276d2dd5a7e0f80398f7"
      ;;
    armhf)
      RELEASE_ARCH="arm"
      RELEASE_SHA256="274428207bc4c7946b03f1857d25f5ff40365f82325cf07e41bd5058dce05b72"
      ;;
    riscv64)
      RELEASE_ARCH="riscv64"
      RELEASE_SHA256="8b47cfce6f66f19bea03f4c6256d5a5760819b4308f5a507969b2173cec67136"
      ;;
    *) die "Gokapi v${GOKAPI_VERSION} 没有受支持的 Debian ${deb_arch} 发布包。" ;;
  esac
}

download_binary() {
  local archive url
  tmp_dir="$(mktemp -d -t gokapi-install.XXXXXXXX)"
  archive="${tmp_dir}/gokapi.zip"
  url="https://github.com/Forceu/Gokapi/releases/download/v${GOKAPI_VERSION}/gokapi-${GOKAPI_VERSION}_linux-${RELEASE_ARCH}.zip"
  log "下载 Gokapi v${GOKAPI_VERSION} (${RELEASE_ARCH})"
  curl --fail --location --silent --show-error --retry 3 --retry-delay 2 \
    --output "$archive" "$url"
  printf '%s  %s\n' "$RELEASE_SHA256" "$archive" | sha256sum --check --status ||
    die "发布包 SHA-256 校验失败，已停止安装。"
  unzip -q "$archive" -d "$tmp_dir"
  [[ -f "${tmp_dir}/gokapi" ]] || die "发布包内未找到 gokapi 可执行文件。"
}

ensure_service_user() {
  if ! getent group "$SERVICE_USER" >/dev/null; then groupadd --system "$SERVICE_USER"; fi
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --gid "$SERVICE_USER" --home-dir "$DATA_DIR" \
      --shell /usr/sbin/nologin "$SERVICE_USER"
  fi
  install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 "$CONFIG_DIR" "$DATA_DIR"
  install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 "${DATA_DIR}/data"
}

write_environment() {
  if [[ ! -e "$ENV_PATH" ]]; then
    cat >"$ENV_PATH" <<EOF
GOKAPI_CONFIG_DIR=${CONFIG_DIR}
GOKAPI_DATA_DIR=${DATA_DIR}/data
GOKAPI_PORT=${DEFAULT_PORT}
EOF
    chmod 0640 "$ENV_PATH"
    chown root:"$SERVICE_USER" "$ENV_PATH"
  fi
}

write_unit() {
  cat >"$UNIT_PATH" <<EOF
[Unit]
Description=Gokapi lightweight file sharing server
Documentation=https://gokapi.readthedocs.io/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${DATA_DIR}
EnvironmentFile=-${ENV_PATH}
ExecStart=${BINARY_PATH}
Restart=on-failure
RestartSec=5s
TimeoutStopSec=30s
UMask=0077

NoNewPrivileges=true
PrivateDevices=true
PrivateTmp=true
ProtectControlGroups=true
ProtectHome=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectSystem=strict
ReadWritePaths=${CONFIG_DIR} ${DATA_DIR}
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
RestrictSUIDSGID=true
LockPersonality=true
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
EOF
}

install_gokapi() {
  local first_install=false server_ip
  [[ -x "$BINARY_PATH" ]] || first_install=true
  check_debian_version
  validate_port
  install_dependencies
  release_for_arch
  download_binary
  ensure_service_user
  log "安装程序文件和 systemd 服务"
  install -o root -g root -m 0755 "${tmp_dir}/gokapi" "${BINARY_PATH}.new"
  mv -f "${BINARY_PATH}.new" "$BINARY_PATH"
  write_environment
  write_unit
  printf '%s\n' "$GOKAPI_VERSION" >"${CONFIG_DIR}/installed-version"
  chown root:"$SERVICE_USER" "${CONFIG_DIR}/installed-version"
  chmod 0640 "${CONFIG_DIR}/installed-version"
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  if [[ "$first_install" == false ]]; then systemctl restart "$SERVICE_NAME"; fi
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager >&2 || true
    die "服务未能启动，请查看上面的日志。"
  fi
  server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$server_ip" ]] || server_ip="服务器IP"
  log "安装完成：Gokapi v${GOKAPI_VERSION}"
  log "首次配置地址：http://${server_ip}:${DEFAULT_PORT}/setup"
  log "请立即完成管理员配置；公网使用时建议配置 HTTPS 反向代理。"
}

show_status() {
  require_root
  systemctl --no-pager --full status "$SERVICE_NAME"
}

uninstall_gokapi() {
  require_root
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
  fi
  rm -f -- "$UNIT_PATH" "$BINARY_PATH" "$ENV_PATH"
  systemctl daemon-reload 2>/dev/null || true
  log "程序和服务已卸载。配置 ${CONFIG_DIR} 与文件 ${DATA_DIR} 已保留。"
}

purge_gokapi() {
  require_root
  [[ ${1:-} == "--yes" ]] || die "完全卸载会删除所有配置和上传文件；确认请运行：$0 purge --yes"
  uninstall_gokapi
  rm -rf -- "$CONFIG_DIR" "$DATA_DIR"
  if id "$SERVICE_USER" >/dev/null 2>&1; then userdel "$SERVICE_USER" 2>/dev/null || true; fi
  if getent group "$SERVICE_USER" >/dev/null; then groupdel "$SERVICE_USER" 2>/dev/null || true; fi
  log "配置、上传文件和服务账户已全部删除。"
}

main() {
  case ${1:-} in
    install|update) require_root; install_gokapi ;;
    status) show_status ;;
    uninstall) uninstall_gokapi ;;
    purge) purge_gokapi "${2:-}" ;;
    -h|--help|help|"") usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
