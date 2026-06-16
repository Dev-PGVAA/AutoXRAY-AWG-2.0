# VPN Setup Script

Автоматическая установка и настройка VPN-сервера на Debian с использованием:
- **Xray** (VLESS + REALITY, Shadowsocks)
- **AmneziaWG 2.0** (userspace, с обфускацией)
- **UFW** (firewall)

## Требования

- Debian 10+
- root доступ (sudo)
- Минимум 512 MB RAM
- Открытые порты: 22 (SSH), 443, 8443, 2040, 51820

## Установка

**Вариант 1: One-liner (быстро)**
```bash
sudo bash -c "$(curl -L https://raw.githubusercontent.com/Dev-PGVAA/AutoXRAY-AWG-2.0/refs/heads/main/AutoXRAY.sh)"
```

**Вариант 2: Скачать и запустить вручную**
```bash
wget https://raw.githubusercontent.com/Dev-PGVAA/AutoXRAY-AWG-2.0/refs/heads/main/AutoXRAY.sh
sudo bash AutoXRAY.sh
```

Скрипт автоматически:
1. **Опционально создаст нового пользователя** (с правами sudo)
2. Обновит систему и установит необходимые пакеты
3. Установит и настроит Xray с VLESS+REALITY на портах 443/8443
4. Установит Shadowsocks на порту 2040 (резервной протокол)
5. Собери и настроит AmneziaWG 2.0 на порту 51820
6. Настроит UFW firewall
7. Выведет готовые конфиги для клиентов

**Логирование**: весь процесс пишется в `/var/log/vpn-setup.log`
```bash
tail -f /var/log/vpn-setup.log
```

## Конфиги клиентов

После установки скрипт выведет:
- **VLESS+REALITY (443)** — основной протокол, маскируется под обычный HTTPS
- **VLESS+REALITY (8443)** — резервной (второй SNI)
- **Shadowsocks** — запасной вариант
- **AmneziaWG** — конфиг сохранён в `/etc/amnezia/amneziawg/client_awg.conf`

### Копирование конфигов

```bash
# VLESS ссылки копируй в приложение (Happ, v2rayNG, Nekoray и т.д.)
# AmneziaWG конфиг:
cat /etc/amnezia/amneziawg/client_awg.conf
```

## Приложения клиентов

- **iOS**: Happ, v2rayTun, FoXray
- **Android**: Happ, v2rayTun, v2rayNG
- **Windows**: Happ, Nekoray, Hiddify, winLoadXRAY
- **macOS**: Happ, Nekoray

## Файлы конфигов

```
/usr/local/etc/xray/config.json        # Xray конфиг
/etc/amnezia/amneziawg/awg0.conf       # AmneziaWG server
/etc/amnezia/amneziawg/client_awg.conf # AmneziaWG client
```

## Управление сервисами

```bash
# Xray
systemctl status xray
systemctl restart xray

# AmneziaWG
systemctl status awg-quick@awg0
systemctl restart awg-quick@awg0

# Firewall
ufw status
```

## Проверка статуса после установки

```bash
# Смотри последние строки логов
tail /var/log/vpn-setup.log

# Проверь что Xray работает
systemctl is-active xray

# Проверь что AmneziaWG работает
ip link show awg0

# Проверь firewall
ufw status numbered
```

## Примечания

- Каждый запуск скрипта генерирует новые ключи и параметры обфускации
- AmneziaWG требует клиент версии ≥ 4.8.12.7 (поддержка AWG 2.0)
- Для добавления новых клиентов в AmneziaWG отредактируй `/etc/amnezia/amneziawg/awg0.conf` и добавь новые `[Peer]` секции
- SSH открыт на порту 22 (не закрывается firewall'ом)

## Troubleshooting

**Ошибка при установке?**
- Смотри полный лог: `cat /var/log/vpn-setup.log`
- Скрипт остановится с номером строки где произошла ошибка
- Убедись что запустил от root: `sudo bash setup_vpn.sh`

**Xray не запускается**
```bash
systemctl restart xray
journalctl -u xray -n 50  # последние 50 строк логов
```

**AmneziaWG не поднялся**
```bash
WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go awg-quick up awg0
journalctl -u awg-quick@awg0 -n 50
```

## Лицензия

MIT
