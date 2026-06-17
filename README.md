#!/bin/bash

set -euo pipefail

LOG_FILE="/var/log/vpn-setup.log"

# Исправление 5: read работает с /dev/tty
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== Запуск установки: $(date) ====="

# Исправление 10: лучшая обработка ошибок
trap 'echo "❌ Ошибка на строке $LINENO. Смотри лог: $LOG_FILE"; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Запусти от root (sudo bash setup_vpn.sh)"
  exit 1
fi

# Определяем цвета (только для терминала)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# Вспомогательная функция для заголовков секций
print_section() {
    echo -e "\n${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${YELLOW}  $1${RESET}"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ============================================================
# 0. Создание нового пользователя (опционально)
# ============================================================
# Исправление 5: read с /dev/tty
read -p "Создать нового пользователя? (y/n): " -n 1 -r < /dev/tty
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  read -p "Имя пользователя: " username < /dev/tty
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
# Исправление 1: добавлен gettext для envsubst
apt update && apt install -y jq curl wget build-essential make git ufw gettext-base gettext

# ============================================================
# 2. Установка Xray
# ============================================================
echo "=== 2. Установка Xray-core ==="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

SCRIPT_DIR=/usr/local/etc/xray
mkdir -p "$SCRIPT_DIR"

# --- генерация переменных ---
xray_uuid_vrv=$(xray uuid)

# Исправление 2: исправлен массив доменов (убрано Markdown-форматирование)
domains=(
    www.theregister.com
    www.20minutes.fr
    www.dealabs.com
    www.manomano.fr
    www.caradisiac.com
    www.techadvisor.com
    www.computerworld.com
    teamdocs.su
    wikiportal.su
    docscenter.su
    www.bing.com
    github.com
    tradingview.com
)
xray_dest_vrv=${domains[$RANDOM % ${#domains[@]}]}
xray_dest_vrv222=${domains[$RANDOM % ${#domains[@]}]}

key_output=$(xray x25519)
xray_privateKey_vrv=$(echo "$key_output" | awk -F': ' '/PrivateKey/ {print $2}')
# Исправление 3: PublicKey вместо Password
xray_publicKey_vrv=$(echo "$key_output" | awk -F': ' '/PublicKey/ {print $2}')
xray_shortIds_vrv=$(openssl rand -hex 8)
xray_sspasw_vrv=$(openssl rand -base64 15 | tr -dc 'A-Za-z0-9' | head -c 20)

# Исправление 9: надежное получение IP
ipserv=$(ip -4 addr show | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)

# Если IP не получен, используем hostname
if [[ -z "$ipserv" ]]; then
    ipserv=$(hostname -I | awk '{print $1}')
fi

export xray_uuid_vrv xray_dest_vrv xray_dest_vrv222 xray_privateKey_vrv xray_publicKey_vrv xray_shortIds_vrv xray_sspasw_vrv ipserv

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
# 3. Firewall (ufw)
# ============================================================
echo "=== 3. Настройка firewall ==="

# Исправление 4: проверка порта 443
if ss -tlnp | grep -q ':443'; then
    echo "${YELLOW}⚠️ Порт 443 занят. Проверьте: ss -tlnp | grep 443${RESET}"
    echo "${YELLOW}Если занят nginx/apache, остановите: systemctl stop nginx apache2${RESET}"
fi

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 443/tcp    comment 'xray vless reality'
ufw allow 8443/tcp   comment 'xray vless reality 2'
ufw allow 2040/tcp   comment 'xray shadowsocks'
ufw --force enable

# ============================================================
# 4. Настройка SSH
# ============================================================
echo "=== 4. Настройка SSH ==="

# Исправление 4: замените на действительные публичные ключи
SSH_PUBKEYS=(
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD действительный_ключ_1 сюда"
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD действительный_ключ_2 сюда"
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD действительный_ключ_3 сюда"
)

# Функция для настройки SSH для конкретного пользователя
setup_ssh_for_user() {
  local user_home=$1
  local user_name=$2
  
  mkdir -p "$user_home/.ssh"
  
  # Очищаем файл authorized_keys и добавляем ключи
  > "$user_home/.ssh/authorized_keys"
  for key in "${SSH_PUBKEYS[@]}"; do
    echo "$key" >> "$user_home/.ssh/authorized_keys"
  done
  
  # Правильные права доступа
  chmod 700 "$user_home/.ssh"
  chmod 600 "$user_home/.ssh/authorized_keys"
  chown -R "$user_name:$user_name" "$user_home/.ssh"
  
  echo "SSH ключи добавлены для пользователя $user_name"
}

# Настройка SSH для root и созданного пользователя
setup_ssh_for_user "/root" "root"
if [[ ! -z "$username" ]] && [[ "$username" != "root" ]]; then
  setup_ssh_for_user "/home/$username" "$username"
fi

# Настройка sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"

# Бэкап оригинального конфига
if [ ! -f "${SSHD_CONFIG}.backup" ]; then
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup"
fi

# Функция для безопасного изменения параметров SSH
update_ssh_config() {
  local key=$1
  local value=$2
  
  # Если параметр существует (в том числе закомментированный), обновляем его
  if grep -q "^#\?${key}\s" "$SSHD_CONFIG"; then
    sed -i "s/^#\?${key}\s.*/${key} ${value}/" "$SSHD_CONFIG"
  else
    # Иначе добавляем в конец файла
    echo "${key} ${value}" >> "$SSHD_CONFIG"
  fi
}

# Настройки безопасности SSH
update_ssh_config "PermitRootLogin" "prohibit-password"
update_ssh_config "PubkeyAuthentication" "yes"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "UsePAM" "yes"
update_ssh_config "X11Forwarding" "no"
update_ssh_config "MaxAuthTries" "3"
update_ssh_config "MaxSessions" "5"
update_ssh_config "ClientAliveInterval" "300"
update_ssh_config "ClientAliveCountMax" "2"

# Перезапуск SSH
systemctl restart sshd
echo "SSH настроен и перезапущен"

# ============================================================
# 5. Создание пользовательских конфигов
# ============================================================
echo "=== 5. Создание пользовательских конфигов ==="

# Исправление 7: вычисляем ss_encoded перед созданием README.txt
ss_encoded=$(echo -n "chacha20-ietf-poly1305:${xray_sspasw_vrv}" | base64 | tr -d '\n')

# Создаем конфигурационные файлы для клиентов
CONFIG_DIR="$SCRIPT_DIR/client_configs"
mkdir -p "$CONFIG_DIR"

# VLESS 443 клиентский конфиг (JSON для Xray клиента)
cat << EOF > "$CONFIG_DIR/vless_443_client.json"
{
  "inbounds": [{
    "port": 10808,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {
      "udp": true
    }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${ipserv}",
        "port": 443,
        "users": [{
          "id": "${xray_uuid_vrv}",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "${xray_dest_vrv}",
        "fingerprint": "chrome",
        "publicKey": "${xray_publicKey_vrv}",
        "shortId": "${xray_shortIds_vrv}",
        "spiderX": "/"
      }
    }
  }]
}
EOF

# VLESS 8443 клиентский конфиг
cat << EOF > "$CONFIG_DIR/vless_8443_client.json"
{
  "inbounds": [{
    "port": 10809,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {
      "udp": true
    }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${ipserv}",
        "port": 8443,
        "users": [{
          "id": "${xray_uuid_vrv}",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "${xray_dest_vrv222}",
        "fingerprint": "chrome",
        "publicKey": "${xray_publicKey_vrv}",
        "shortId": "${xray_shortIds_vrv}",
        "spiderX": "/"
      }
    }
  }]
}
EOF

# Shadowsocks клиентский конфиг
cat << EOF > "$CONFIG_DIR/shadowsocks_client.json"
{
  "inbounds": [{
    "port": 10810,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {
      "udp": true
    }
  }],
  "outbounds": [{
    "protocol": "shadowsocks",
    "settings": {
      "servers": [{
        "address": "${ipserv}",
        "port": 2040,
        "method": "chacha20-ietf-poly1305",
        "password": "${xray_sspasw_vrv}"
      }]
    }
  }]
}
EOF

# Создаем файл с информацией о всех конфигурациях
# Исправление 7: ss_encoded теперь определен
cat << EOF > "$CONFIG_DIR/README.txt"
===========================================
VPN Конфигурации
Сервер IP: ${ipserv}
Дата установки: $(date)
===========================================

1. VLESS + REALITY (Порт 443) - Основной
   Ссылка: vless://${xray_uuid_vrv}@${ipserv}:443?security=reality&sni=${xray_dest_vrv}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-443
   Конфиг файл: vless_443_client.json

2. VLESS + REALITY (Порт 8443) - Резервный
   Ссылка: vless://${xray_uuid_vrv}@${ipserv}:8443?security=reality&sni=${xray_dest_vrv222}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-8443
   Конфиг файл: vless_8443_client.json

3. Shadowsocks (Порт 2040) - Резервный
   Ссылка: ss://${ss_encoded}@${ipserv}:2040#VPN-2040
   Конфиг файл: shadowsocks_client.json

SSH Конфигурация:
- Парольная аутентификация отключена
- Доступ только по SSH-ключам
- Root доступ: только по ключам
- Конфиг файл SSH: ${SSHD_CONFIG}.backup (оригинал)
===========================================
EOF

# ============================================================
# 6. Красивый вывод итоговой информации
# ============================================================
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║   🚀 VPN & SSH SETUP COMPLETED SUCCESSFULLY   ║${RESET}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════╝${RESET}"

print_section "🔑 SSH AUTHORIZED KEYS"
for i in "${!SSH_PUBKEYS[@]}"; do
    printf "${CYAN}  Key %d:${RESET} ${GREEN}%s...${RESET}\n" $((i+1)) "${SSH_PUBKEYS[$i]:0:40}"
done

print_section "🌐 VPN CONFIGURATIONS"

echo -e "${BOLD}${GREEN}  VLESS + REALITY (Primary port 443)${RESET}"
echo -e "${CYAN}  vless://${xray_uuid_vrv}@${ipserv}:443?security=reality&sni=${xray_dest_vrv}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-443${RESET}"

echo -e "\n${BOLD}${GREEN}  VLESS + REALITY (Backup port 8443)${RESET}"
echo -e "${CYAN}  vless://${xray_uuid_vrv}@${ipserv}:8443?security=reality&sni=${xray_dest_vrv222}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-8443${RESET}"

echo -e "\n${BOLD}${GREEN}  Shadowsocks (Backup port 2040)${RESET}"
echo -e "${CYAN}  ss://${ss_encoded}@${ipserv}:2040#VPN-2040${RESET}"

print_section "📁 CLIENT CONFIG FILES"
echo -e "${GREEN}  Directory: ${CONFIG_DIR}${RESET}"
echo -e "${GREEN}  Readme:    ${CONFIG_DIR}/README.txt${RESET}"

print_section "⚠️ IMPORTANT CHECKLIST"
echo -e "${YELLOW}  1. Замените SSH_PUBKEYS на действительные ключи${RESET}"
echo -e "${YELLOW}  2. Проверьте что порт 443 свободен (ss -tlnp | grep 443)${RESET}"
echo -e "${YELLOW}  3. Если порт 443 занят - остановите nginx/apache${RESET}"
echo -e "${YELLOW}  4. Проверьте сервис Xray: systemctl status xray${RESET}"
echo -e "${YELLOW}  5. Лог установки: $LOG_FILE${RESET}"
