#!/bin/bash
set -e

LOG_FILE="/var/log/vpn-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== Запуск установки: $(date) ====="

trap 'echo "❌ Ошибка на строке $LINENO. Смотри лог: $LOG_FILE"; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root (sudo bash setup_vpn.sh)"
  exit 1
fi

# ============================================================
# 0. Создание нового пользователя (опционально)
# ============================================================
read -p "Создать нового пользователя? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  read -p "Имя пользователя: " username
  if id "$username" &>/dev/null 2>&1; then
    echo "Пользователь $username уже существует"
  else
    useradd -m -s /bin/bash "$username"
    usermod -aG sudo "$username"
    echo "Пользователь $username создан с правами sudo"
    echo "Установи пароль вручную: passwd $username"
  fi
fi

echo "=== 1. Обновление и установка необходимых пакетов ==="
apt update && apt install -y jq curl wget build-essential make git ufw gettext-base

# ============================================================
# 2. Установка Xray
# ============================================================
echo "=== 2. Установка Xray-core ==="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

SCRIPT_DIR=/usr/local/etc/xray
mkdir -p "$SCRIPT_DIR"

# --- генерация переменных ---
xray_uuid_vrv=$(xray uuid)

domains=(www.theregister.com www.20minutes.fr www.dealabs.com www.manomano.fr www.caradisiac.com www.techadvisor.com www.computerworld.com teamdocs.su wikiportal.su docscenter.su www.bing.com github.com tradingview.com)
xray_dest_vrv=${domains[$RANDOM % ${#domains[@]}]}
xray_dest_vrv222=${domains[$RANDOM % ${#domains[@]}]}

key_output=$(xray x25519)
xray_privateKey_vrv=$(echo "$key_output" | awk -F': ' '/PrivateKey/ {print $2}')
xray_publicKey_vrv=$(echo "$key_output" | awk -F': ' '/Password/ {print $2}')

key_mldsa65=$(xray mldsa65)
seed_mldsa65=$(echo "$key_mldsa65" | awk -F': ' '/Seed/ {print $2}')
verify_mldsa65=$(echo "$key_mldsa65" | awk -F': ' '/Verify/ {print $2}')

xray_shortIds_vrv=$(openssl rand -hex 8)
xray_sspasw_vrv=$(openssl rand -base64 15 | tr -dc 'A-Za-z0-9' | head -c 20)

ipserv=$(hostname -I | awk '{print $1}')

export xray_uuid_vrv xray_dest_vrv xray_dest_vrv222 xray_privateKey_vrv xray_publicKey_vrv xray_shortIds_vrv xray_sspasw_vrv

cat << 'EOF' | envsubst > "$SCRIPT_DIR/config.json"
{
  "log": {
    "dnsLog": false,
    "loglevel": "none"
  },
  "dns": {
    "servers": [
      "https+local://8.8.4.4/dns-query",
      "https+local://8.8.8.8/dns-query",
      "https+local://1.1.1.1/dns-query",
      "localhost"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "VLESStcpREALITY",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "flow": "xtls-rprx-vision",
            "id": "${xray_uuid_vrv}"
          }
        ],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 0,
          "target": "${xray_dest_vrv}:443",
          "spiderX": "/",
          "shortIds": ["${xray_shortIds_vrv}"],
          "privateKey": "${xray_privateKey_vrv}",
          "serverNames": ["${xray_dest_vrv}"],
          "limitFallbackUpload": {
            "afterBytes": 0,
            "bytesPerSec": 65536,
            "burstBytesPerSec": 0
          },
          "limitFallbackDownload": {
            "afterBytes": 5242880,
            "bytesPerSec": 262144,
            "burstBytesPerSec": 2097152
          }
        }
      }
    },
    {
      "tag": "Vless8443",
      "port": 8443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "flow": "xtls-rprx-vision",
            "id": "${xray_uuid_vrv}"
          }
        ],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 0,
          "target": "${xray_dest_vrv222}:443",
          "spiderX": "/",
          "shortIds": ["${xray_shortIds_vrv}"],
          "privateKey": "${xray_privateKey_vrv}",
          "serverNames": ["${xray_dest_vrv222}"],
          "limitFallbackUpload": {
            "afterBytes": 0,
            "bytesPerSec": 65536,
            "burstBytesPerSec": 0
          },
          "limitFallbackDownload": {
            "afterBytes": 5242880,
            "bytesPerSec": 262144,
            "burstBytesPerSec": 2097152
          }
        }
      }
    },
    {
      "tag": "ShadowsocksTCP",
      "port": 2040,
      "listen": "0.0.0.0",
      "protocol": "shadowsocks",
      "settings": {
        "clients": [
          {
            "password": "${xray_sspasw_vrv}",
            "method": "chacha20-ietf-poly1305"
          }
        ]
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": { "domainStrategy": "ForceIPv4" }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "rules": [
      {
        "domain": ["geosite:category-ads", "geosite:win-spy", "geosite:private"],
        "outboundTag": "block"
      },
      {
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

systemctl enable xray
systemctl restart xray
echo "Xray готов."

# ============================================================
# 3. AmneziaWG 2.0 (userspace, без kernel module — собирается из исходников)
# ============================================================
echo "=== 3. Установка AmneziaWG 2.0 ==="

# включаем форвардинг трафика
cat > /etc/sysctl.d/99-awg.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-awg.conf

# ставим Go, если нет или версия слишком старая
export PATH=$PATH:/usr/local/go/bin:/usr/local/bin
GO_VER=1.22.5
need_go_install=true
if command -v go &>/dev/null; then
  current_go_ver=$(go version | awk '{print $3}' | sed 's/go//')
  if [[ "$(printf '%s\n' "$GO_VER" "$current_go_ver" | sort -V | head -n1)" == "$GO_VER" ]]; then
    need_go_install=false
    echo "Go $current_go_ver уже установлен, подходит."
  fi
fi

if $need_go_install; then
  cd /tmp
  wget -q "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "go${GO_VER}.linux-amd64.tar.gz"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
fi

if ! command -v go &>/dev/null; then
  echo "❌ Go не установился, прерываю."
  exit 1
fi

# собираем amneziawg-go (userspace-реализация)
if ! command -v amneziawg-go &>/dev/null; then
  rm -rf /opt/amneziawg-go
  git clone https://github.com/amnezia-vpn/amneziawg-go.git /opt/amneziawg-go
  cd /opt/amneziawg-go && make
  if [ ! -f amneziawg-go ]; then
    echo "❌ Сборка amneziawg-go не удалась."
    exit 1
  fi
  cp amneziawg-go /usr/bin/amneziawg-go
fi

# собираем amneziawg-tools (awg, awg-quick)
if ! command -v awg &>/dev/null; then
  rm -rf /opt/amneziawg-tools
  git clone https://github.com/amnezia-vpn/amneziawg-tools.git /opt/amneziawg-tools
  cd /opt/amneziawg-tools/src
  make
  make install
  if ! command -v awg &>/dev/null; then
    echo "❌ Установка amneziawg-tools не удалась."
    exit 1
  fi
fi

mkdir -p /etc/amnezia/amneziawg
cd /etc/amnezia/amneziawg

# ключи
server_priv=$(awg genkey)
server_pub=$(echo "$server_priv" | awg pubkey)
client_priv=$(awg genkey)
client_pub=$(echo "$client_priv" | awg pubkey)
psk=$(awg genpsk)

# обфускация AWG2.0: Jc/Jmin/Jmax — мусорные пакеты, S1-S4 — паддинг хендшейка, H1-H4 — magic headers
jc=4
jmin=40
jmax=70
s1=$(( 15 + ($(printf '%d' 0x$(openssl rand -hex 2)) % 50) ))
s2=$(( 65 + ($(printf '%d' 0x$(openssl rand -hex 2)) % 50) ))
s3=$(( 15 + ($(printf '%d' 0x$(openssl rand -hex 2)) % 50) ))
s4=$(( 65 + ($(printf '%d' 0x$(openssl rand -hex 2)) % 50) ))
h1=$(( 5 + ($(printf '%d' 0x$(openssl rand -hex 4)) % 2147483643) ))
h2=$(( 5 + ($(printf '%d' 0x$(openssl rand -hex 4)) % 2147483643) ))
h3=$(( 5 + ($(printf '%d' 0x$(openssl rand -hex 4)) % 2147483643) ))
h4=$(( 5 + ($(printf '%d' 0x$(openssl rand -hex 4)) % 2147483643) ))

# внешний интерфейс для NAT
ext_if=$(ip route | awk '/^default/ {print $5; exit}')

cat > awg0.conf <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = ${server_priv}
Jc = ${jc}
Jmin = ${jmin}
Jmax = ${jmax}
S1 = ${s1}
S2 = ${s2}
S3 = ${s3}
S4 = ${s4}
H1 = ${h1}
H2 = ${h2}
H3 = ${h3}
H4 = ${h4}
PostUp = iptables -A FORWARD -i awg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${ext_if} -j MASQUERADE
PostDown = iptables -D FORWARD -i awg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${ext_if} -j MASQUERADE

[Peer]
PublicKey = ${client_pub}
PresharedKey = ${psk}
AllowedIPs = 10.66.66.2/32
EOF
chmod 600 awg0.conf

# поднимаем интерфейс через userspace-реализацию
mkdir -p /etc/systemd/system/awg-quick@awg0.service.d
cat > /etc/systemd/system/awg-quick@awg0.service.d/override.conf <<EOF
[Service]
Environment=WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go
EOF

systemctl daemon-reload
WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go awg-quick up awg0 || true
systemctl enable --now awg-quick@awg0

# клиентский конфиг
cat > client_awg.conf <<EOF
[Interface]
PrivateKey = ${client_priv}
Address = 10.66.66.2/32
DNS = 1.1.1.1
Jc = ${jc}
Jmin = ${jmin}
Jmax = ${jmax}
S1 = ${s1}
S2 = ${s2}
S3 = ${s3}
S4 = ${s4}
H1 = ${h1}
H2 = ${h2}
H3 = ${h3}
H4 = ${h4}

[Peer]
PublicKey = ${server_pub}
PresharedKey = ${psk}
Endpoint = ${ipserv}:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 client_awg.conf

echo "AmneziaWG готов."

# ============================================================
# 4. Firewall (ufw)
# ============================================================
echo "=== 4. Настройка firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 443/tcp    comment 'xray vless reality'
ufw allow 8443/tcp   comment 'xray vless reality 2'
ufw allow 2040/tcp   comment 'xray shadowsocks'
ufw allow 51820/udp  comment 'amneziawg'
ufw --force enable

# ============================================================
# 5. Вывод итоговых конфигов
# ============================================================
link1="vless://${xray_uuid_vrv}@${ipserv}:443?security=reality&sni=${xray_dest_vrv}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-vless-443"
link2="vless://${xray_uuid_vrv}@${ipserv}:8443?security=reality&sni=${xray_dest_vrv222}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-vless-8443"
ss_encoded=$(echo -n "chacha20-ietf-poly1305:${xray_sspasw_vrv}" | base64)
link3="ss://${ss_encoded}@${ipserv}:2040#VPN-ShadowS-2040"

echo -e "
================== ГОТОВО ==================

VLESS+REALITY (443):
${link1}

VLESS+REALITY (8443, резерв):
${link2}

Shadowsocks (резерв):
${link3}

AmneziaWG конфиг клиента сохранён в:
/etc/amnezia/amneziawg/client_awg.conf

Скопируй его содержимое в приложение AmneziaVPN / amneziawg-windows-client
(нужна версия клиента, поддерживающая AWG 2.0: AmneziaVPN >= 4.8.12.7).

============================================
"
