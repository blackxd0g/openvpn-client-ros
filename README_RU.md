[English](README.md) | **Русский**

# openvpn-client-ros

> Мультиархитектурный OpenVPN-клиент для контейнеров MikroTik RouterOS.
> Получает маршруты от OpenVPN-сервера, синхронизирует `/ip/route` и firewall
> address-list через RouterOS REST API и переподключается при обрыве туннеля.

[![Docker Pulls](https://img.shields.io/docker/pulls/blackxdog/openvpn-client-ros?logo=docker&label=docker%20pulls)](https://hub.docker.com/r/blackxdog/openvpn-client-ros)
[![Docker Image Size](https://img.shields.io/docker/image-size/blackxdog/openvpn-client-ros/latest?logo=docker&label=image%20size)](https://hub.docker.com/r/blackxdog/openvpn-client-ros)
[![Последний commit](https://img.shields.io/github/last-commit/blackxd0g/openvpn-client-ros?logo=github&label=last%20commit)](https://github.com/blackxd0g/openvpn-client-ros/commits/main)
![Платформы](https://img.shields.io/badge/arch-armv5%20%7C%20armv7%20%7C%20arm64%20%7C%20amd64-success)
![RouterOS](https://img.shields.io/badge/RouterOS-7.23%20%7C%207.24-blue)
[![Boosty](https://img.shields.io/badge/Boosty-поддержать-f15f2c?logo=boosty&logoColor=white)](https://boosty.to/blackxdog/donate)

## ✨ Возможности

- 📦 Один тег `latest` для `linux/arm/v5`, `linux/arm/v7`, `linux/arm64` и `linux/amd64`.
- ✅ Поддержка ARM-моделей, RB4011, RB5009, x86 и CHR.
- 🔄 Автоматическое переподключение OpenVPN с выводом причины в журнал.
- 🛣 Синхронизация pushed IPv4-маршрутов с `/ip/route`.
- 🧾 Синхронизация тех же сетей с `/ip/firewall/address-list`.
- 🏷 Собственный тег/comment для всех управляемых записей.
- ♻️ Идемпотентная сверка: актуальные записи не перезаписываются.
- 🧹 Удаление устаревших маршрутов и поддержка прежних тегов.
- 🔐 RouterOS REST через HTTPS с отдельным self-signed CA.
- 🔒 Пароли в файлах вместо открытых ENV в журнале RouterOS.
- 🚀 Автоматическая установка одним RouterOS-скриптом.
- 🪵 Уровни логирования `error`, `warn`, `info`, `debug`.

> [!NOTE]
> Проверено на RouterOS 7.23/7.24. Требуются пакет `container` и
> `device-mode container=yes`.

## ⚡ Быстрый старт

1. Включите поддержку контейнеров:

```routeros
/system/device-mode/print
/system/device-mode/update container=yes
```

После команды подтвердите изменение физической кнопкой или перезапуском
питания в отведённое RouterOS время.

2. Скачайте установщик прямо из терминала MikroTik:

```routeros
:local url "https://raw.githubusercontent.com/blackxd0g/openvpn-client-ros/main/deploy-routeros.rsc"
:local dst "deploy-routeros.rsc"
/tool fetch url=$url mode=https dst-path=$dst
:put ("Downloaded " . $dst . ". Review its network settings before import.")
```

Откройте `deploy-routeros.rsc` в разделе **Files** и при необходимости проверьте
сетевые параметры. Логин и пароль VPN скрипт запросит при запуске. Отдельный
40-символьный пароль RouterOS REST API будет создан автоматически.

3. Загрузите профиль в один из каталогов, который затем выберете в установщике:

```text
usb1/openvpn-client-ros/config/client.ovpn
openvpn-client-ros/config/client.ovpn         # system
```

4. Загрузите `deploy-routeros.rsc` на роутер и импортируйте:

```routeros
/import file-name=deploy-routeros.rsc verbose=yes
```

5. Проверьте результат:

```routeros
/container/print
/log/print where topics~"container"
/ip/route/print where comment="ovpn-client-ros"
/ip/firewall/address-list/print where comment="ovpn-client-ros"
```

Успешный запуск заканчивается сообщением:

```text
[route-sync] [info] sync complete: destinations=17 routes=on address-list=on
```

## 🚀 Автоматическая установка

[![Установщик](https://img.shields.io/badge/RouterOS-скачать%20установщик-0A84FF?logo=mikrotik&logoColor=white)](deploy-routeros.rsc)
[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-открыть%20образ-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/blackxdog/openvpn-client-ros)
[![Совместимость](https://img.shields.io/badge/docs-совместимость%20профилей-7B61FF)](PROFILE-COMPATIBILITY.md)

[`deploy-routeros.rsc`](deploy-routeros.rsc) рассчитан на повторный запуск. Он:

- 📁 предлагает выбрать `usb1` или `system`, проверяет профиль и создаёт каталоги;
- 🔌 создаёт veth и изолированную `/30`-сеть;
- 🔀 настраивает адрес RouterOS, NAT и forwarding;
- 👤 создаёт ограниченного пользователя RouterOS REST;
- 🔏 создаёт локальный CA и сертификат `www-ssl` с IP в SAN;
- 🧱 ограничивает REST API IP-адресом контейнера;
- 💾 создаёт mount `/config` и env-list;
- 🔑 переносит VPN/API пароли в файлы профиля;
- 🐳 скачивает `blackxdog/openvpn-client-ros:latest`;
- ▶️ создаёт контейнер и включает автозапуск.

Основные параметры находятся в начале скрипта:

| Параметр | По умолчанию | Назначение |
|---|---:|---|
| `containerName` | `ovpn-client-ros` | Имя контейнера |
| `imageName` | `blackxdog/openvpn-client-ros:latest` | Docker-образ |
| `routerAddress` | `192.168.255.9/30` | Адрес RouterOS на veth |
| `containerAddress` | `192.168.255.10/30` | Адрес контейнера |
| `storageChoice` | запрос при запуске | `usb1` или встроенный `system` |
| `routeTable` | `main` | Routing table |
| `addressListName` | пусто | Пусто = имя контейнера |
| `routeTag` | пусто | Пусто = имя контейнера |
| `logLevel` | `info` | Уровень журнала |
| `recreateContainer` | `true` | Пересоздать контейнер |

> [!IMPORTANT]
> При выборе `system` убедитесь, что во внутренней памяти достаточно места.
> Выбранная `/30`-сеть не должна пересекаться с существующими сетями роутера.

### 📜 Полный скрипт развёртывания

Нажмите, чтобы раскрыть исходник, затем скопируйте его в файл `deploy-routeros.rsc`.
Запускайте скрипт из интерактивного терминала: он запросит VPN-логин и пароль.
`/terminal ask` не маскирует ввод как специализированное password-поле, поэтому
используйте доверенную SSH- или WinBox-сессию.

<details>
<summary><strong>Показать deploy-routeros.rsc</strong></summary>

```routeros
# Automated deployment for RouterOS 7.23/7.24.
# Upload client.ovpn to the selected system or usb1 storage before running.
# Run this file from an interactive RouterOS terminal.

:local vpnUsername ""
:local vpnPassword ""
:local apiPassword [:rndstr from="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" length=40]

:local containerName "ovpn-client-ros"
:local imageName "registry-1.docker.io/blackxdog/openvpn-client-ros:latest"
:local envList "OVPN-CLIENT-ROS"
:local mountList "ovpn-client-ros-config"
:local vethName "veth-ovpn-client"
:local routerAddress "192.168.255.9/30"
:local containerAddress "192.168.255.10/30"
:local routerIP "192.168.255.9"
:local containerIP "192.168.255.10"
:local linkNetwork "192.168.255.8/30"
:local storageChoice ""
:local storageRoot ""
:local profilePath ""
:local routeTable "main"
:local addressListName ""
:local routeTag ""
:local logLevel "info"
:local recreateContainer true

:while (($storageChoice != "usb1") and ($storageChoice != "system")) do={
    :put "[ovpn-deploy] Select container storage: usb1 or system"
    :set storageChoice [/terminal ask]
}
:if ($storageChoice = "usb1") do={
    :if ([:len [/disk find where slot="usb1"]] = 0) do={
        :error "usb1 disk was not found; attach it or run again and select system"
    }
    :set storageRoot "usb1/openvpn-client-ros"
} else={
    :set storageRoot "openvpn-client-ros"
}
:set profilePath ($storageRoot . "/config/client.ovpn")
:put ("[ovpn-deploy] storage selected: " . $storageChoice . "; profile: " . $profilePath)

:put "[ovpn-deploy] Enter VPN login:"
:set vpnUsername [/terminal ask]
:if ([:len $vpnUsername] = 0) do={ :error "VPN login cannot be empty" }
:put "[ovpn-deploy] Enter VPN password (input may be visible in the terminal):"
:set vpnPassword [/terminal ask]
:if ([:len $vpnPassword] = 0) do={ :error "VPN password cannot be empty" }
:put "[ovpn-deploy] RouterOS REST API password generated automatically"

:put "[ovpn-deploy] preparing directories"
:if ([:len [/file find where name=$storageRoot and type="directory"]] = 0) do={
    /file add name=$storageRoot type=directory
}
:if ([:len [/file find where name=($storageRoot . "/config") and type="directory"]] = 0) do={
    /file add name=($storageRoot . "/config") type=directory
}

:if ([:len [/file find where name=$profilePath]] = 0) do={
    :error ("OpenVPN profile is missing: " . $profilePath)
}

:put "[ovpn-deploy] configuring veth and gateway"
:local vethId [/interface/veth find where name=$vethName]
:if ([:len $vethId] = 0) do={
    /interface/veth add name=$vethName address=$containerAddress gateway=$routerIP comment=$containerName
} else={
    /interface/veth set $vethId address=$containerAddress gateway=$routerIP comment=$containerName
}

:local addressId [/ip/address find where comment=$containerName and interface=$vethName]
:if ([:len $addressId] = 0) do={
    /ip/address add address=$routerAddress interface=$vethName comment=$containerName
} else={
    /ip/address set $addressId address=$routerAddress interface=$vethName comment=$containerName
}

:put "[ovpn-deploy] configuring NAT and REST firewall access"
:local natId [/ip/firewall/nat find where comment=($containerName . " outbound")]
:if ([:len $natId] = 0) do={
    /ip/firewall/nat add chain=srcnat action=masquerade src-address=$linkNetwork out-interface-list=WAN comment=($containerName . " outbound")
} else={
    /ip/firewall/nat set $natId chain=srcnat action=masquerade src-address=$linkNetwork out-interface-list=WAN disabled=no
}

:local filterId [/ip/firewall/filter find where comment=($containerName . " REST API")]
:if ([:len $filterId] = 0) do={
    /ip/firewall/filter add chain=input action=accept protocol=tcp src-address=$containerIP dst-port=80,443 place-before=0 comment=($containerName . " REST API")
} else={
    /ip/firewall/filter set $filterId chain=input action=accept protocol=tcp src-address=$containerIP dst-port=80,443 disabled=no
}

:put "[ovpn-deploy] configuring restricted REST account"
:local apiGroup "api-ovpn-routes"
:local apiUser "api-ovpn-client"
:local groupId [/user/group find where name=$apiGroup]
:if ([:len $groupId] = 0) do={
    /user/group add name=$apiGroup policy=read,write,web,api,rest-api
} else={
    /user/group set $groupId policy=read,write,web,api,rest-api
}
:local userId [/user find where name=$apiUser]
:if ([:len $userId] = 0) do={
    /user add name=$apiUser group=$apiGroup password=$apiPassword address=($containerIP . "/32") comment=$containerName
} else={
    /user set $userId group=$apiGroup password=$apiPassword address=($containerIP . "/32") disabled=no comment=$containerName
}
:put "[ovpn-deploy] configuring self-signed REST HTTPS certificate"
:local restCertName ($containerName . "-rest")
:local restCaName ($containerName . "-rest-ca")
:local restCaId [/certificate find where name=$restCaName]
:if ([:len $restCaId] = 0) do={
    /certificate add name=$restCaName common-name=($containerName . " REST CA") key-usage=key-cert-sign,crl-sign days-valid=3650
    /certificate sign $restCaName
    /certificate set [find where name=$restCaName] trusted=yes
}
:local restCertId [/certificate find where name=$restCertName]
:if ([:len $restCertId] = 0) do={
    /certificate add name=$restCertName common-name=$routerIP subject-alt-name=("IP:" . $routerIP) key-usage=tls-server,digital-signature,key-encipherment days-valid=3650
    /certificate sign $restCertName ca=$restCaName
    /certificate set [find where name=$restCertName] trusted=yes
}
/ip/service set www-ssl disabled=no address=($containerIP . "/32") certificate=$restCertName tls-version=only-1.2
# Plain HTTP remains available only from the isolated container IP as a fallback.
/ip/service set www disabled=no address=($containerIP . "/32")

:put "[ovpn-deploy] configuring read-only profile mount"
:local oldMounts [/container/mounts find where list=$mountList]
:if ([:len $oldMounts] > 0) do={ /container/mounts remove $oldMounts }
/container/mounts add list=$mountList src=($storageRoot . "/config") dst="/config" mode=ro

:local ovpnSetEnv do={
    :local itemId [/container/envs find where list=$listName and key=$keyName]
    :if ([:len $itemId] = 0) do={
        /container/envs add list=$listName key=$keyName value=$keyValue
    } else={
        /container/envs set $itemId value=$keyValue
    }
}

:put "[ovpn-deploy] configuring OVPN environment"
:local vpnPasswordFile ($storageRoot . "/config/openvpn-password")
:local apiPasswordFile ($storageRoot . "/config/router-api-password")
:foreach secretSpec in={($vpnPasswordFile . "=" . $vpnPassword);($apiPasswordFile . "=" . $apiPassword)} do={
    :local separator [:find $secretSpec "="]
    :local secretPath [:pick $secretSpec 0 $separator]
    :local secretValue [:pick $secretSpec ($separator + 1) [:len $secretSpec]]
    :local secretId [/file find where name=$secretPath]
    :if ([:len $secretId] = 0) do={
        /file add name=$secretPath contents=$secretValue
    } else={
        /file set $secretId contents=$secretValue
    }
}
$ovpnSetEnv listName=$envList keyName="OVPN_CONFIG" keyValue="/config/client.ovpn"
$ovpnSetEnv listName=$envList keyName="OVPN_USERNAME" keyValue=$vpnUsername
:local oldVpnPasswordEnv [/container/envs find where list=$envList and key="OVPN_PASSWORD"]
:if ([:len $oldVpnPasswordEnv] > 0) do={ /container/envs remove $oldVpnPasswordEnv }
$ovpnSetEnv listName=$envList keyName="OVPN_PASSWORD_FILE" keyValue="/config/openvpn-password"
$ovpnSetEnv listName=$envList keyName="OVPN_DATA_CIPHERS" keyValue="AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC"
$ovpnSetEnv listName=$envList keyName="OVPN_RESTART_DELAY" keyValue="10"
$ovpnSetEnv listName=$envList keyName="OVPN_LOG_LEVEL" keyValue=$logLevel
$ovpnSetEnv listName=$envList keyName="OVPN_API_URL" keyValue=("https://" . $routerIP)
$ovpnSetEnv listName=$envList keyName="OVPN_API_USER" keyValue=$apiUser
:local oldApiPasswordEnv [/container/envs find where list=$envList and key="OVPN_API_PASSWORD"]
:if ([:len $oldApiPasswordEnv] > 0) do={ /container/envs remove $oldApiPasswordEnv }
$ovpnSetEnv listName=$envList keyName="OVPN_API_PASSWORD_FILE" keyValue="/config/router-api-password"
$ovpnSetEnv listName=$envList keyName="OVPN_API_VERIFY_TLS" keyValue="false"
$ovpnSetEnv listName=$envList keyName="OVPN_GATEWAY" keyValue=$containerIP
$ovpnSetEnv listName=$envList keyName="OVPN_CONTAINER_NAME" keyValue=$containerName
$ovpnSetEnv listName=$envList keyName="OVPN_ROUTE_TAG" keyValue=$routeTag
$ovpnSetEnv listName=$envList keyName="OVPN_SYNC_ROUTES" keyValue="true"
$ovpnSetEnv listName=$envList keyName="OVPN_SYNC_ADDRESS_LIST" keyValue="true"
$ovpnSetEnv listName=$envList keyName="OVPN_ADDRESS_LIST_NAME" keyValue=$addressListName
$ovpnSetEnv listName=$envList keyName="OVPN_ROUTE_TABLE" keyValue=$routeTable
$ovpnSetEnv listName=$envList keyName="OVPN_ROUTE_DISTANCE" keyValue="1"
$ovpnSetEnv listName=$envList keyName="OVPN_ALLOW_DEFAULT_ROUTE" keyValue="false"
$ovpnSetEnv listName=$envList keyName="OVPN_EXTRA_ROUTES" keyValue=""

/container/config set registry-url="https://registry-1.docker.io" tmpdir=($storageRoot . "/tmp")

:local containerId [/container find where name=$containerName]
:if (([:len $containerId] > 0) and $recreateContainer) do={
    :put "[ovpn-deploy] removing previous ovpn-client-ros container"
    /container stop $containerId
    :delay 3s
    /container remove $containerId
    :delay 2s
    :set containerId ""
}

:if ([:len $containerId] = 0) do={
    :put "[ovpn-deploy] downloading container image"
    /container add name=$containerName remote-image=$imageName interface=$vethName root-dir=($storageRoot . "/root") mountlists=$mountList envlists=$envList user="0:0" dns="1.1.1.1" logging=yes start-on-boot=yes comment=$containerName
}

:put "[ovpn-deploy] waiting for image extraction"
:local ready false
:for attempt from=1 to=120 do={
    :set containerId [/container find where name=$containerName]
    :if ([:len $containerId] > 0) do={
        :local currentStatus [/container get $containerId status]
        :if ($currentStatus = "stopped") do={
            :set ready true
            :break
        }
    }
    :if (!$ready) do={ :delay 5s }
}

:if (!$ready) do={
    :error "Container image was not ready after 10 minutes; check /container/print and /log/print"
}

:put "[ovpn-deploy] starting container"
/container start $containerId
:delay 5s
/container print detail where name=$containerName
:put "[ovpn-deploy] complete; inspect /log/print where topics~\"container\""
```

</details>


## 🌐 Схема трафика

```text
LAN-клиент
    │
    ▼
маршрут RouterOS
    │ gateway = IP контейнера на veth
    ▼
eth0 контейнера ── forwarding + masquerade ── tun0 ── VPN
```

В RouterOS gateway — это IP контейнера на veth. Адрес, выданный внутри
OpenVPN-туннеля, как RouterOS gateway не используется.

## 🧱 Поддерживаемые архитектуры

| RouterOS | Docker platform | Примеры | Статус |
|---|---|---|---|
| `arm64` | `linux/arm64` | RB5009 | ✅ |
| `arm` | `linux/arm/v5` | RB4011 и другие ARM32-модели | ✅ Рекомендуется для RouterOS |
| `arm` | `linux/arm/v7` | ARMv7 вне RouterOS / ручной импорт | ✅ |
| `x86` / CHR | `linux/amd64` | CHR, x86-64 | ✅ |

RouterOS для архитектуры `arm` ожидает ARM32/ARMv5-контейнер. Поэтому тег
`latest` содержит отдельный ARMv5-вариант на Debian `armel`; ARM64, ARMv7 и
AMD64 собираются на Alpine.

## 📁 Точка монтирования

Требуется только одна постоянная mount-папка:

| Путь RouterOS | Путь контейнера | Содержимое |
|---|---|---|
| `usb1/openvpn-client-ros/config` | `/config` | `.ovpn`, сертификаты, ключи, пароли |

```text
usb1/openvpn-client-ros/config/
├── client.ovpn
├── openvpn-password
└── router-api-password
```

Если сертификаты не встроены в `.ovpn`, положите их сюда и используйте пути
`/config/...`.

## 🧾 OpenVPN-профиль

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

> [!WARNING]
> Не добавляйте `script-security`, `route-up` и `route-pre-down`: контейнер
> задаёт собственные hooks для синхронизации RouterOS.

Поддерживается routed TUN. TAP/bridge и IPv6-маршруты не синхронизируются.

## ⚙️ Переменные окружения

### 🔗 OpenVPN и supervisor

| ENV | По умолчанию | Описание |
|---|---:|---|
| `OVPN_CONFIG` | `/config/client.ovpn` | Путь к профилю |
| `OVPN_USERNAME` | — | Логин OpenVPN |
| `OVPN_PASSWORD` | — | Plaintext ENV для совместимости |
| `OVPN_PASSWORD_FILE` | — | Рекомендуемый файл пароля VPN |
| `OVPN_DATA_CIPHERS` | образ | Список data ciphers |
| `OVPN_RESTART_DELAY` | `10` | Задержка перезапуска, секунд |
| `OVPN_LOG_LEVEL` | `info` | `error` / `warn` / `info` / `debug` |
| `OVPN_VERB` | от log level | Явный OpenVPN `verb` |

### 🔐 RouterOS REST

| ENV | По умолчанию | Описание |
|---|---:|---|
| `OVPN_API_URL` | — | Например `https://192.168.255.9` |
| `OVPN_API_USER` | — | Пользователь RouterOS REST |
| `OVPN_API_PASSWORD` | — | Plaintext ENV для совместимости |
| `OVPN_API_PASSWORD_FILE` | — | Рекомендуемый файл пароля REST |
| `OVPN_API_VERIFY_TLS` | `true` | Проверка TLS-сертификата |
| `OVPN_GATEWAY` | — | IP контейнера на veth |

### 🛣 Маршруты и address-list

| ENV | По умолчанию | Описание |
|---|---:|---|
| `OVPN_CONTAINER_NAME` | `ovpn-client-ros` | Имя и базовый tag |
| `OVPN_SYNC_ROUTES` | `true` | Создавать `/ip/route` |
| `OVPN_SYNC_ADDRESS_LIST` | `true` | Создавать address-list |
| `OVPN_ADDRESS_LIST_NAME` | имя контейнера | Имя address-list |
| `OVPN_ROUTE_TAG` | имя контейнера | Comment управляемых записей |
| `OVPN_LEGACY_TAGS` | — | Старые теги через пробел/запятую |
| `OVPN_ROUTE_TABLE` | `main` | Routing table |
| `OVPN_ROUTE_DISTANCE` | `1` | Distance маршрута |
| `OVPN_ALLOW_DEFAULT_ROUTE` | `false` | Разрешить `0.0.0.0/0` |
| `OVPN_EXTRA_ROUTES` | — | Дополнительные CIDR |

Старые `ROS_*` ENV остаются совместимыми алиасами.

## ♻️ Как работает сверка

- ✅ актуальный tag + сеть + gateway + table + distance → оставить;
- 🔁 изменённые параметры → заменить;
- 🏷 старый тег из `OVPN_LEGACY_TAGS` → заменить новым;
- 🗑 лишняя управляемая сеть → удалить;
- ➕ недостающая сеть → создать;
- 🛡 чужая запись → не изменять, вывести предупреждение.

При падении туннеля управляемые маршруты удаляются, чтобы трафик не уходил в
неработающий gateway. После восстановления они создаются снова.

## 🔑 Пароли без утечки в журнал

RouterOS при `logging=yes` печатает ENV в строке запуска. Хешировать API-пароль
нельзя: REST Basic Auth требует исходное значение. Используйте файлы:

```text
OVPN_PASSWORD_FILE=/config/openvpn-password
OVPN_API_PASSWORD_FILE=/config/router-api-password
```

Файлы имеют приоритет над plaintext ENV. Автоматический скрипт создаёт их и
удаляет `OVPN_PASSWORD`/`OVPN_API_PASSWORD` из env-list.

> [!CAUTION]
> Старые записи RouterOS log могут хранить прежние plaintext ENV до перезагрузки.
> После миграции рекомендуется сменить оба пароля.

## 🔒 HTTPS для RouterOS REST

Скрипт создаёт CA `ovpn-client-ros-rest-ca`, серверный сертификат
`ovpn-client-ros-rest`, SAN с IP RouterOS и firewall-доступ только контейнеру.

После проверки HTTPS обычный HTTP можно отключить:

```routeros
/ip/service/set www disabled=yes
```

Self-signed режим использует `OVPN_API_VERIFY_TLS=false`. Для строгой проверки
экспортируйте CA в `/config` и включите verification.

## 🔄 Переподключение

При кратком сбое OpenVPN переподключается внутри процесса. Если процесс
завершился, supervisor:

1. 🧹 удаляет управляемые RouterOS-записи;
2. 🪵 пишет код выхода в журнал;
3. ⏳ ждёт `OVPN_RESTART_DELAY`;
4. ▶️ запускает OpenVPN снова.

## 🛠 Диагностика

```routeros
/container/print detail where name="ovpn-client-ros"
/log/print where topics~"container"
/ip/route/print detail where comment="ovpn-client-ros"
/ip/firewall/address-list/print detail where comment="ovpn-client-ros"
```

Полезные сообщения:

```text
Initialization Sequence Completed
[route-sync] [info] sync complete: destinations=N routes=on address-list=on
[route-sync] [error] route sync failed: ...
[ovpn-supervisor] [info] starting OpenVPN attempt=N ...
```

## 🐳 Самостоятельная сборка

```sh
docker buildx build --pull --no-cache \
  --platform linux/arm/v7,linux/arm64,linux/amd64 \
  -t YOUR_DOCKERHUB/openvpn-client-ros:latest-modern --push .

docker buildx build --pull --no-cache \
  --platform linux/arm/v5 -f Dockerfile.armv5 \
  -t YOUR_DOCKERHUB/openvpn-client-ros:latest-armv5 --push .

docker buildx imagetools create \
  -t YOUR_DOCKERHUB/openvpn-client-ros:latest \
  YOUR_DOCKERHUB/openvpn-client-ros:latest-modern \
  YOUR_DOCKERHUB/openvpn-client-ros:latest-armv5
```

Основной Dockerfile использует `alpine:latest`, а ARMv5 — официальный
`arm32v5/debian:bookworm-slim`. В обоих случаях OpenVPN устанавливается из
актуального репозитория дистрибутива во время сборки.

## 🛡 Безопасность

- 👤 Используйте отдельного RouterOS API-пользователя.
- 🧱 Ограничивайте REST API адресом veth-контейнера.
- 🔒 После настройки отключите обычный `www`.
- 🚫 Не публикуйте `.ovpn`, ключи, сертификаты и файлы паролей.
- ✏️ Перед импортом замените все `CHANGE_ME` значения.
- 🔌 Не добавляйте veth контейнера в LAN bridge.
- ⚠️ Контейнер работает от root для TUN, forwarding и iptables.

## 💖 Поддержка проекта

Если `openvpn-client-ros` сэкономил вам время и оказался полезен, вы можете
[поддержать разработку через Boosty](https://boosty.to/blackxdog/donate).

[![Поддержать на Boosty](https://img.shields.io/badge/Boosty-поддержать-f15f2c?logo=boosty&logoColor=white)](https://boosty.to/blackxdog/donate)

Поддержка помогает тестировать новые версии RouterOS и OpenVPN, поддерживать
ARMv7/ARM64-сборки и развивать автоматическую синхронизацию маршрутов.

## 📄 Файлы проекта

| Файл | Назначение |
|---|---|
| [`Dockerfile`](Dockerfile) | Multi-arch образ |
| [`entrypoint.sh`](entrypoint.sh) | Supervisor и сеть |
| [`route_sync.py`](route_sync.py) | Сверка routes/address-list |
| [`route-hook.sh`](route-hook.sh) | OpenVPN route hooks |
| [`deploy-routeros.rsc`](deploy-routeros.rsc) | Автоматическая установка |
| [`routeros.rsc`](routeros.rsc) | Ручной пример |
| [`PROFILE-COMPATIBILITY.md`](PROFILE-COMPATIBILITY.md) | Совместимость профиля |
