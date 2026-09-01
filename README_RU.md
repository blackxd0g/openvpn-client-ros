# OpenVPN-клиент для MikroTik RouterOS ARM/ARM64

[English](README.md) | [Русский](README_RU.md)

Контейнер OpenVPN-клиента для MikroTik RouterOS 7.23/7.24. Поддерживает
RB5009 и другие устройства ARM64, а также RB4011 и другие ARMv7-устройства.
Образы x86/CHR и ARMv5 намеренно не публикуются.

Готовый multi-arch образ:

```text
blackxdog/openvpn-client-ros:latest
```

При подключении контейнер получает IPv4-маршруты, переданные OpenVPN-сервером,
и синхронизирует их с `/ip/route` и/или `/ip/firewall/address-list` через
RouterOS REST API. При падении туннеля управляемые записи удаляются, OpenVPN
автоматически переподключается, а события выводятся в журнал RouterOS.

## Схема сети

```text
Клиент LAN -> маршрут RouterOS -> veth контейнера -> tun0 -> VPN
```

В качестве gateway маршрута RouterOS используется IP контейнера на veth, а не
удалённый адрес внутри VPN-туннеля.

## Поддерживаемые платформы

- RouterOS `arm64` / Docker `linux/arm64`: RB5009 и другие ARM64.
- RouterOS `arm` / Docker `linux/arm/v7`: RB4011 и другие ARMv7.
- ARMv5, x86 и CHR не поддерживаются этим образом.

RouterOS показывает архитектуру RB4011 как `arm`, поэтому для него Docker
автоматически выбирает манифест `linux/arm/v7`.

## Что требуется

- RouterOS 7.23 или 7.24 с пакетом `container`.
- Разрешённый container device mode.
- Внешний накопитель рекомендуется для root-dir контейнера.
- OpenVPN-профиль `client.ovpn`.
- Доступ роутера в Docker Hub.

Включение контейнеров требует физического подтверждения на устройстве:

```routeros
/system/device-mode/update container=yes
```

## Автоматическая установка

Для полной установки используется idempotent-скрипт
[`deploy-routeros.rsc`](deploy-routeros.rsc). Повторный импорт обновляет
существующую конфигурацию и при необходимости пересоздаёт контейнер.

1. Скачайте `deploy-routeros.rsc`.
2. В начале файла задайте три значения:

```routeros
:local vpnUsername "VPN_LOGIN"
:local vpnPassword "VPN_PASSWORD"
:local apiPassword "LONG_RANDOM_API_PASSWORD"
```

3. При необходимости измените адреса veth, путь накопителя, имя контейнера,
   routing table, address-list и тег маршрутов.
4. Загрузите OpenVPN-профиль на роутер:

```text
usb1/openvpn-client-ros/config/client.ovpn
```

5. Загрузите скрипт и выполните:

```routeros
/import file-name=deploy-routeros.rsc verbose=yes
```

Скрипт автоматически:

- создаёт `/30`-сеть и veth контейнера;
- настраивает NAT и forwarding;
- создаёт ограниченного пользователя RouterOS REST;
- создаёт локальный CA и HTTPS-сертификат для `www-ssl`;
- ограничивает REST API IP-адресом контейнера;
- создаёт mount и env-list;
- сохраняет VPN/API пароли в файлах профиля вместо plaintext ENV;
- скачивает `blackxdog/openvpn-client-ros:latest`;
- создаёт и запускает контейнер.

После первой установки проверьте:

```routeros
/container/print
/log/print where topics~"container"
/ip/route/print where comment="ovpn-client-ros"
/ip/firewall/address-list/print where comment="ovpn-client-ros"
```

## OpenVPN-профиль

Основной файл должен называться `client.ovpn`. Все внешние файлы, на которые
он ссылается, должны находиться в той же смонтированной папке `/config`:

```conf
client
dev tun
proto udp
remote vpn.example.net 1194
ca /config/ca.crt
cert /config/client.crt
key /config/client.key
auth-user-pass
```

Не добавляйте в профиль `script-security`, `route-up` или `route-pre-down` —
контейнер задаёт их самостоятельно.

## Основные ENV

| Переменная | Назначение |
|---|---|
| `OVPN_CONFIG` | Профиль, обычно `/config/client.ovpn` |
| `OVPN_USERNAME` | Логин VPN |
| `OVPN_PASSWORD_FILE` | Файл пароля VPN |
| `OVPN_API_URL` | REST URL, например `https://192.168.255.9` |
| `OVPN_API_USER` | Пользователь RouterOS REST |
| `OVPN_API_PASSWORD_FILE` | Файл пароля REST |
| `OVPN_API_VERIFY_TLS` | Проверять сертификат RouterOS |
| `OVPN_GATEWAY` | IP контейнера на veth |
| `OVPN_SYNC_ROUTES` | Создавать записи `/ip/route` |
| `OVPN_SYNC_ADDRESS_LIST` | Создавать address-list записи |
| `OVPN_ADDRESS_LIST_NAME` | Имя address-list; пустое = имя контейнера |
| `OVPN_ROUTE_TAG` | Comment/тег управляемых записей |
| `OVPN_LEGACY_TAGS` | Старые теги через пробел или запятую |
| `OVPN_ROUTE_TABLE` | Таблица маршрутизации, обычно `main` |
| `OVPN_ROUTE_DISTANCE` | Distance создаваемых маршрутов |
| `OVPN_ALLOW_DEFAULT_ROUTE` | Разрешить pushed `0.0.0.0/0` |
| `OVPN_EXTRA_ROUTES` | Дополнительные сети через пробел/запятую |
| `OVPN_RESTART_DELAY` | Задержка перезапуска OpenVPN в секундах |
| `OVPN_LOG_LEVEL` | `error`, `warn`, `info` или `debug` |

Актуальные записи с правильным тегом, gateway, table и distance сохраняются
без перезаписи. Старые или изменённые управляемые записи заменяются, лишние
удаляются, недостающие создаются. Чужие записи контейнер не изменяет.

## Пароли без утечки в журнал

При `logging=yes` RouterOS выводит значения ENV в строке запуска контейнера.
Поэтому рекомендуется использовать файлы:

```text
OVPN_PASSWORD_FILE=/config/openvpn-password
OVPN_API_PASSWORD_FILE=/config/router-api-password
```

Автоматический скрипт настраивает этот режим самостоятельно. Не добавляйте
пароли, `.ovpn`, ключи и сертификаты в Git; соответствующие шаблоны уже есть в
`.gitignore`.

## HTTPS RouterOS REST

Скрипт создаёт отдельный локальный CA и серверный сертификат с SAN для IP
RouterOS, включает `www-ssl` и разрешает доступ только с IP контейнера. После
проверки HTTPS обычный `www` можно отключить:

```routeros
/ip/service/set www disabled=yes
```

Для self-signed сертификата используется `OVPN_API_VERIFY_TLS=false`. Для
строгой проверки экспортируйте CA в `/config`, включите TLS verification и
укажите CA-файл.

## Переподключение и журнал

OpenVPN выполняет штатное переподключение при сетевых сбоях. Если процесс
полностью завершился, supervisor удаляет управляемые маршруты, пишет код выхода
в журнал, ждёт `OVPN_RESTART_DELAY` и запускает OpenVPN снова.

Успешная синхронизация выглядит так:

```text
[route-sync] [info] sync complete: destinations=17 routes=on address-list=on
```

## Самостоятельная сборка

```sh
docker buildx build --pull --no-cache \
  --platform linux/arm/v7,linux/arm64 \
  -t YOUR_DOCKERHUB/openvpn-client-ros:latest \
  --push .
```

Dockerfile использует `alpine:latest` и актуальный пакет OpenVPN из репозитория
Alpine. Точная версия OpenVPN выводится в журнал при старте.

## Безопасность

- Используйте отдельного RouterOS API-пользователя.
- Ограничивайте `www-ssl` и firewall адресом контейнера.
- Не публикуйте VPN-профили, приватные ключи и файлы паролей.
- Перед использованием замените все `CHANGE_ME` значения.
- Контейнер запускается от root, поскольку TUN, forwarding и iptables требуют
  сетевых привилегий.
