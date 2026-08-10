# Отчёт по домашнему заданию по работе с загрузчиком (27.07)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 10.08.2026
- **Задание:** 
  - Написать service, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова (файл лога и ключевое слово должны задаваться в /etc/default);
  - Установить spawn-fcgi и создать unit-файл (spawn-fcgi.sevice) с помощью переделки init-скрипта (https://gist.github.com/cea2k/1318020);
  - Доработать unit-файл Nginx (nginx.service) для запуска нескольких инстансов сервера с разными конфигурационными файлами одновременно.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы

### 1. Написать service, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова
Создание конфигцрационного файла для переменных:
```
root@linpro:~# cat > /etc/default/watchlog << EOF
# Configuration file for my watchlog service
# Place it to /etc/default

# File and word in that file that we will be monit
WORD="ALERT"
LOG=/var/log/watchlog.log
EOF
```

Создание лог-файла с ключевым словом:
```
root@linpro:~# cat > /var/log/watchlog.log << EOF
Everything is fine
No alerts here
ALERT: Something happened
ALERT: Critical error
Normal message
EOF
root@
```

Создание скрипта мониторинга:
```
root@linpro:~# cat > /opt/watchlog.sh << 'EOF'
#!/bin/bash
WORD=$1
LOG=$2
DATE=`date`

if grep $WORD $LOG &> /dev/null
then
    logger "$DATE: I found word, Master!"
else
    exit 0
fi
EOF

chmod +x /opt/watchlog.sh
```

Создание unit-сервиса:
```
root@linpro:~# cat > /etc/systemd/system/watchlog.service << EOF
[Unit]
Description=My watchlog service

[Service]
Type=oneshot
EnvironmentFile=/etc/default/watchlog
ExecStart=/opt/watchlog.sh \$WORD \$LOG
EOF
```
PS: `\$WORD` и `\$LOG` экранированы `(\$)` чтобы `systemd` не интерпретировал их как переменные окружения при запуске.

Создание юнита таймера:
```
root@linpro:~# cat > /etc/systemd/system/watchlog.timer << EOF
[Unit]
Description=Run watchlog script every 30 second

[Timer]
OnUnitActiveSec=30
Unit=watchlog.service

[Install]
WantedBy=multi-user.target
EOF
```

Запуск и проверка таймера:
```
root@linpro:~# systemctl start watchlog.service
root@linpro:~# systemctl start watchlog.timer
```

Если все хорошо, то через минут при просмотре логов будет видно следующее:
```
root@linpro:~# tail -n 20 /var/log/syslog | grep "I found word"
2026-08-10T14:15:35.550403+00:00 linpro root: Mon Aug 10 14:15:35 UTC 2026: I found word, Master!
```

### 2. Установить spawn-fcgi и создать unit-файл с помощью переделки init-скрипта
Установка необходимых пакетов:
```
root@linpro:~# sudo apt update && sudo apt upgrade -y
root@linpro:~# apt install -y spawn-fcgi php php-cgi php-cli apache2 libapache2-mod-fcgid
```

Создание конфигурационного файла для `spawn-fcgi`:
```
root@linpro:~# mkdir -p /etc/spawn-fcgi
cat > /etc/spawn-fcgi/fcgi.conf << EOF
# You must set some working options before the "spawn-fcgi" service will work.
# If SOCKET points to a file, then this file is cleaned up by the init script.
#
# See spawn-fcgi(1) for all possible options.
#
# Example :
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u www-data -g www-data -s \$SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
EOF
```
PS: `\$SOCKET` здесь тоже экранирован `(\$)`, чтобы sysmted подставил значение переменной из самого файла.

Создание 











