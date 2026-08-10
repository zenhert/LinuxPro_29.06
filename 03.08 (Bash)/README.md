# Отчёт по домашнему заданию по работе с bash (03.08)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 10.08.2026
- **Задание:** 
  - Написать bash-скрипт, который ежечасно формирует и отправляет на email отчёт о работе веб-сервера.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS
- Будет использована ВМ из задания по работе с systemd, где уже установлен nginx

---

## Ход работы

### 1. Написать bash-скрипт, который ежечасно формирует и отправляет на email отчет о работе веб-сервера
Проверка запуска хотя бы одного инстанса nginx:
```
root@linpro:~# systemctl status nginx@first.service || systemctl status nginx
● nginx@first.service - A high performance web server and a 
     Active: active (running) since Mon 2026-08-10 15:06:23 UTC; 
    Process: 76591 ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx-first.conf -q -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
    Process: 76595 ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx-first.conf -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
```

Для отправки писем будет использоваться `mail` из пакета `mailutils`.
Установка почтовой утилиты:
```
root@linpro:~# sudo apt update
root@linpro:~# sudo apt install -y mailutils
```
При запросе типа почтовой системы будет выбран `Internet Site`, имя будет оставлено по умолчанию.

Чтобы скрипту было что анализировать, необходимо добавить демонстративные записи в `/var/log/nginx/access.log`:
```
root@linpro:~# sudo tee -a /var/log/nginx/access.log > /dev/null << 'EOF'
192.168.1.10 - - [10/Aug/2026:15:00:01 +0000] "GET /index.html HTTP/1.1" 200 612 "-" "Mozilla/5.0"
192.168.1.11 - - [10/Aug/2026:15:01:05 +0000] "POST /login HTTP/1.1" 401 45 "-" "curl/7.68.0"
10.0.0.5 - - [10/Aug/2026:15:02:10 +0000] "GET /images/logo.png HTTP/1.1" 304 0 "http://example.com/" "Mozilla/5.0"
192.168.1.10 - - [10/Aug/2026:15:03:15 +0000] "GET /api/data HTTP/1.1" 500 212 "-" "python-requests/2.25.1"
10.0.0.5 - - [10/Aug/2026:15:04:20 +0000] "GET /index.html HTTP/1.1" 200 612 "-" "Mozilla/5.0"
192.168.1.12 - - [10/Aug/2026:15:05:25 +0000] "GET /contact HTTP/1.1" 404 10 "-" "curl/7.68.0"
EOF
```
Даты должны соответствовать текущему дню, чтобы скрипт их захватил при анализе за последний час.

Будет создан скрипт, который:
- Собирает все access-логи через `find` (маска `access.log*`);
- Извлекает записи за последний час с помощью `AWK` (функция `filter_by_time`).
- Формирует топ IP, топ URL, распределение HTTP-кодов и список ошибок (4xx, 5xx);
- Использует `trap` для гарантированной очистки временных файлов;
- Защищён от повторного запуска через `flock`;
- Отправляет письмо через `sendmail` или `mail`.

Создание скрипта анализа лога и отправки отчета `(nginx_report.sh)`:
```
root@linpro:~# sudo tee /opt/nginx_report.sh
root@linpro:~# sudo chmod +x /opt/nginx_report.sh
```
PS: Файл скрипта приложен в репозитории.

PSS: `sed` напрямую в скрипте не задействован, т.к. `AWK` лучше справляется с разбором логов. Однако, стоит отметить, что `sed` можно использовать для быстрого парсинга одной строки, но для потоковой обработки выбран `AWK`. В рамках задания данный критерий выполнен в виде демонстрации.

Настройка Cron:
Добавление задания в `crontab` для root:
```
root@linpro:~# sudo crontab -e
0 * * * * /opt/nginx_report.sh
```

Ручная проверка:
```
root@linpro:~# sudo rm -f /tmp/nginx_report_last_run
root@linpro:~# sudo /opt/nginx_report.sh
root@linpro:~# sudo mail
"/var/mail/root": 2 messages 2 new
>N   1 root               Mon Aug 10 16:23  16/471   Test subject
 N   2 root               Mon Aug 10 17:05  35/1099  Nginx report (2026-08-10 16:05:32 — 2026-08-10 17:05:32)
```

Письмо с темой "Nginx report" успешно получено. Содержимое имеет всю требуемую статистику:
```
Return-Path: <root@linpro.fh.dev.ru>
X-Original-To: root@localhost
Delivered-To: root@localhost
Received: by linpro.fh.dev.ru (Postfix, from userid 0)
        id B85D46036F; Mon, 10 Aug 2026 17:05:32 +0000 (UTC)
Subject: Nginx report (2026-08-10 16:05:32 — 2026-08-10 17:05:32)
To: root@localhost
Content-Type: text/plain; charset=utf-8
Message-Id: <20260810170532.B85D46036F@linpro.fh.dev.ru>
Date: Mon, 10 Aug 2026 17:05:32 +0000 (UTC)
From: root <root@linpro.fh.dev.ru>
X-UID: 2

=== Отчёт о работе веб-сервера ===
Период: 2026-08-10 16:05:32 — 2026-08-10 17:05:32
Сформирован: Mon Aug 10 17:05:32 UTC 2026
Проанализировано файлов: 1

=== Топ IP-адресов ===
      2 192.168.1.200
      1 192.168.1.100
      1 10.10.0.3
      1 10.10.0.1

=== Топ запрашиваемых URL ===
      2 /test
      1 /status
      1 /index.html
      1 /data

=== HTTP-коды ответов ===
      4 200
      1 503

=== Ошибки (первые 20) ===
10.10.0.1 - - [10/Aug/2026:16:15:00 +0000] "GET /status HTTP/1.1" 503 1024 "-" "Wget"
```
