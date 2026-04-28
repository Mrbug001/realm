#!/usr/bin/env bash
set -e

#BASE_URL="https://raw.githubusercontent.com/Mrbug001/realm/main"
#因为github网址国内服务器有时候访问不到
BASE_URL="https://cdn.jsdelivr.net/gh/Mrbug001/realm@main"

BASE_DIR="/etc/xshyun/realm"
BIN_DIR="$BASE_DIR/bin"
CONF_DIR="$BASE_DIR/conf"
LOG_DIR="/var/log/realm"
CERT_DIR="$BASE_DIR/cert"
BIN="$BIN_DIR/realm"
MANAGER="/usr/local/bin/realm"
SCRIPT_PATH="$BASE_DIR/realm.sh"

ACTION="$1"
shift || true

localPort=""
remoteHost=""
remotePort=""
protocol="none"
isSecure="false"
sendProxy="false"
acceptProxy="false"
customHost=""
customSni=""
customPath=""
isServer="false"
autoRestart="true"
isBalance="false"

info(){ echo "$*"; }
err(){ echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && err "请使用 root 用户运行"

need_cmd(){
  command -v "$1" >/dev/null 2>&1 && return

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null
    apt-get install -y "$1" >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$1" >/dev/null
  else
    err "不支持的系统，缺少 apt-get/yum"
  fi
}

arch(){
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64|armv8*) echo "arm64" ;;
    *) err "不支持的架构：$(uname -m)" ;;
  esac
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--localPort)
        localPort="$2"
        shift 2
        ;;
      -r|--remoteHost)
        remoteHost="$2"
        shift 2
        ;;
      -p|--remotePort)
        remotePort="$2"
        shift 2
        ;;
      --protocol)
        protocol="$2"
        shift 2
        ;;
      --isSecure)
        isSecure="$2"
        shift 2
        ;;
      --sendProxy)
        sendProxy="$2"
        shift 2
        ;;
      --acceptProxy)
        acceptProxy="$2"
        shift 2
        ;;
      --customHost)
        customHost="$2"
        shift 2
        ;;
      --customSni)
        customSni="$2"
        shift 2
        ;;
      --customPath)
        customPath="$2"
        shift 2
        ;;
      --isServer)
        isServer="$2"
        shift 2
        ;;
      --autoRestart)
        autoRestart="$2"
        shift 2
        ;;
      --isBalance)
        isBalance="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
}

check_port(){
  [[ -z "$1" ]] && err "端口不能为空"
  [[ "$1" =~ ^[0-9]+$ ]] || err "端口不正确：$1"
  [[ "$1" -ge 1 && "$1" -le 65535 ]] || err "端口范围应为 1-65535"
}

install_realm(){
  need_cmd curl
  need_cmd lsof

  mkdir -p "$BIN_DIR" "$CONF_DIR" "$LOG_DIR" "$CERT_DIR"

  local a
  a="$(arch)"

  curl -L -o "$BIN" "$BASE_URL/$a/realm"
  chmod +x "$BIN"

  curl -L -o "$CONF_DIR/full.json" "$BASE_URL/full.json"

  cp -f "$0" "$SCRIPT_PATH" 2>/dev/null || true
  chmod +x "$SCRIPT_PATH" 2>/dev/null || true

  cat > "$MANAGER" <<EOF
#!/usr/bin/env bash
bash "$SCRIPT_PATH" "\$@"
EOF

  chmod +x "$MANAGER"

  echo "OK: realm installed"
}

add_service(){
  parse_args "$@"

  [[ -z "$localPort" ]] && err "缺少 --localPort"
  [[ -z "$remoteHost" ]] && err "缺少 --remoteHost"
  [[ -z "$remotePort" ]] && err "缺少 --remotePort"

  check_port "$localPort"
  check_port "$remotePort"

  [[ ! -f "$BIN" ]] && install_realm

  if [[ ! -f "$CONF_DIR/full.json" ]]; then
    mkdir -p "$CONF_DIR"
    curl -L -o "$CONF_DIR/full.json" "$BASE_URL/full.json"
  fi

  mkdir -p "$CONF_DIR" "$LOG_DIR" "$CERT_DIR"

  local conf="$CONF_DIR/${localPort}.json"
  local service="realm-${localPort}.service"

  cp "$CONF_DIR/full.json" "$conf"

  sed -i "s#\"listen\":.*#\"listen\":\"[::]:$localPort\",#g" "$conf"
  sed -i "s#\"remote\":.*#\"remote\":\"$remoteHost:$remotePort\",#g" "$conf"

  [[ "$sendProxy" == "true" ]] && sed -i "s#\"send_proxy\":.*#\"send_proxy\":true,#g" "$conf"
  [[ "$acceptProxy" == "true" ]] && sed -i "s#\"accept_proxy\":.*#\"accept_proxy\":true,#g" "$conf"

  customPath="${customPath#/}"

  if [[ "$isServer" == "false" ]]; then
    if [[ "$protocol" == "tls" ]]; then
      if [[ "$isSecure" == "true" ]]; then
        sed -i "s#\"remote_transport\":.*#\"remote_transport\":\"tls;sni=${customSni}\"#g" "$conf"
      else
        sed -i "s#\"remote_transport\":.*#\"remote_transport\":\"tls;sni=${customSni};insecure\"#g" "$conf"
      fi
    elif [[ "$protocol" == "ws" ]]; then
      sed -i "s#\"remote_transport\":.*#\"remote_transport\":\"ws;host=${customHost};path=/${customPath}\"#g" "$conf"
    elif [[ "$protocol" == "wss" ]]; then
      if [[ "$isSecure" == "true" ]]; then
        sed -i "s#\"remote_transport\":.*#\"remote_transport\":\"ws;host=${customHost};path=/${customPath};tls;sni=${customSni}\"#g" "$conf"
      else
        sed -i "s#\"remote_transport\":.*#\"remote_transport\":\"ws;host=${customHost};path=/${customPath};tls;sni=${customSni};insecure\"#g" "$conf"
      fi
    fi
  else
    local cert_dir="$CERT_DIR/${localPort}"
    local cert_file="$cert_dir/${customSni}.crt"
    local key_file="$cert_dir/${customSni}.key"

    mkdir -p "$cert_dir"

    if [[ "$protocol" == "tls" ]]; then
      if [[ "$isSecure" == "true" ]]; then
        sed -i "s#\"listen_transport\":.*#\"listen_transport\":\"tls;cert=${cert_file};key=${key_file}\",#g" "$conf"
      else
        sed -i "s#\"listen_transport\":.*#\"listen_transport\":\"tls;servername=${customSni}\",#g" "$conf"
      fi
    elif [[ "$protocol" == "ws" ]]; then
      sed -i "s#\"listen_transport\":.*#\"listen_transport\":\"ws;host=${customHost};path=/${customPath}\",#g" "$conf"
    elif [[ "$protocol" == "wss" ]]; then
      if [[ "$isSecure" == "true" ]]; then
        sed -i "s#\"listen_transport\":.*#\"listen_transport\":\"ws;host=${customHost};path=/${customPath};tls;cert=${cert_file};key=${key_file}\",#g" "$conf"
      else
        sed -i "s#\"listen_transport\":.*#\"listen_transport\":\"ws;host=${customHost};path=/${customPath};tls;servername=${customSni}\",#g" "$conf"
      fi
    fi
  fi

  cat > "/etc/systemd/system/$service" <<EOF
[Unit]
Description=realm forwarding service $localPort
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
LimitNOFILE=102400
ExecStart=$BIN -c $conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload

  if [[ "$isBalance" == "true" ]]; then
    echo "OK: config generated only, balance mode enabled, service not started"
  else
    systemctl restart "$service"

    if [[ "$autoRestart" == "true" ]]; then
      systemctl enable "$service" >/dev/null 2>&1
    fi

    echo "OK: realm-${localPort}.service started"
  fi
}

start_port(){
  parse_args "$@"

  [[ -z "$localPort" ]] && err "缺少 --localPort"

  check_port "$localPort"

  local service="realm-${localPort}.service"

  systemctl start "$service" >/dev/null 2>&1 || err "服务不存在或启动失败: $service"

  echo "OK: realm-${localPort}.service started"
}

stop_port(){
  parse_args "$@"

  [[ -z "$localPort" ]] && err "缺少 --localPort"

  check_port "$localPort"

  local service="realm-${localPort}.service"

  systemctl stop "$service" >/dev/null 2>&1 || err "服务不存在或停止失败: $service"

  echo "OK: realm-${localPort}.service stopped"
}

restart_port(){
  parse_args "$@"

  [[ -z "$localPort" ]] && err "缺少 --localPort"

  check_port "$localPort"

  local service="realm-${localPort}.service"

  systemctl restart "$service" >/dev/null 2>&1 || err "服务不存在或重启失败: $service"

  echo "OK: realm-${localPort}.service restarted"
}

remove_port(){
  parse_args "$@"

  [[ -z "$localPort" ]] && err "缺少 --localPort"

  check_port "$localPort"

  local service="realm-${localPort}.service"

  systemctl stop "$service" >/dev/null 2>&1 || true
  systemctl disable "$service" >/dev/null 2>&1 || true

  rm -f "/etc/systemd/system/$service"
  rm -f "$CONF_DIR/${localPort}.json"

  systemctl daemon-reload

  echo "OK: realm-${localPort}.service removed"
}

uninstall_all(){
  systemctl list-units --type=service --all | awk '{print $1}' | grep '^realm-[0-9]\+\.service$' | while read -r service; do
    systemctl stop "$service" >/dev/null 2>&1 || true
    systemctl disable "$service" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$service"
  done

  rm -rf "$BASE_DIR"
  rm -rf "$LOG_DIR"
  rm -f "$MANAGER"

  systemctl daemon-reload

  echo "OK: realm fully uninstalled"
}

uninstall_realm(){
  parse_args "$@"

  if [[ -n "$localPort" ]]; then
    remove_port --localPort "$localPort"
  else
    uninstall_all
  fi
}

list_services(){
  systemctl list-units --type=service --all | grep 'realm-[0-9]\+\.service' || true
}

status_port(){
  parse_args "$@"

  [[ -z "$localPort" ]] && err "缺少 --localPort"

  check_port "$localPort"

  local service="realm-${localPort}.service"

  systemctl status "$service" --no-pager
}

case "$ACTION" in
  install)
    install_realm
    ;;
  add)
    add_service "$@"
    ;;
  start)
    start_port "$@"
    ;;
  stop)
    stop_port "$@"
    ;;
  restart)
    restart_port "$@"
    ;;
  remove)
    remove_port "$@"
    ;;
  uninstall)
    uninstall_realm "$@"
    ;;
  list)
    list_services
    ;;
  status)
    status_port "$@"
    ;;
  *)
    echo "Usage:"
    echo "  realm install"
    echo "  realm add --localPort 12345 --remoteHost 1.2.3.4 --remotePort 443"
    echo "  realm start --localPort 12345"
    echo "  realm stop --localPort 12345"
    echo "  realm restart --localPort 12345"
    echo "  realm status --localPort 12345"
    echo "  realm remove --localPort 12345"
    echo "  realm uninstall"
    echo "  realm uninstall --localPort 12345"
    echo "  realm list"
    exit 1
    ;;
esac
