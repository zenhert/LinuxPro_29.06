#!/bin/bash
set -euo pipefail

# === Конфигурация ===
LOG_DIR="/var/log/nginx"
ACCESS_LOG_PATTERN="access.log*"
STATE_FILE="/tmp/nginx_report_last_run"
LOCK_FILE="/tmp/nginx_report.lock"
REPORT_TMP="/tmp/nginx_report_$$"
MAIL_TO="root@localhost"

# === Функции ===

# Очистка временных файлов при выходе/ошибке
cleanup() {
    rm -f "$REPORT_TMP" "$REPORT_TMP.body"
}
trap cleanup EXIT ERR

# Блокировка от повторного запуска
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Скрипт уже выполняется, выход." | systemd-cat -t nginx_report
    exit 1
fi

# Определение временного диапазона
CURRENT_TIME=$(date +%s)
if [ -f "$STATE_FILE" ]; then
    LAST_TIME=$(cat "$STATE_FILE")
else
    LAST_TIME=$(date -d "1 hour ago" +%s)
fi

DATE_FROM=$(date -d @$LAST_TIME '+%Y-%m-%d %H:%M:%S')
DATE_TO=$(date '+%Y-%m-%d %H:%M:%S')

# Поиск лог-файлов через find
mapfile -t LOG_FILES < <(find "$LOG_DIR" -name "$ACCESS_LOG_PATTERN" -type f ! -name "*.gz" 2>/dev/null)
if [ ${#LOG_FILES[@]} -eq 0 ]; then
    echo "Не найдено лог-файлов по маске $ACCESS_LOG_PATTERN в $LOG_DIR" | systemd-cat -t nginx_report
    exit 1
fi

# Фильтрация по времени
export LC_TIME=C
for f in "${LOG_FILES[@]}"; do
    while read -r line; do
        ts_raw=$(echo "$line" | awk '{print $4}' | tr -d '[]')
        if [ -z "$ts_raw" ]; then continue; fi
        # Преобразуем "10/Aug/2026:16:34:14" в "Aug 10 16:34:14 2026"
        ts_fixed=$(echo "$ts_raw" | awk -F'[/:]' '{print $2,$1,$4":"$5":"$6,$3}')
        epoch=$(date -d "$ts_fixed" +%s 2>/dev/null)
        if [ -n "$epoch" ] && [ "$epoch" -ge "$LAST_TIME" ] && [ "$epoch" -le "$CURRENT_TIME" ]; then
            echo "$line"
        fi
    done < "$f"
done > "$REPORT_TMP"

# === Формирование статистики ===

# Топ-10 IP
TOP_IPS=$(awk '{print $1}' "$REPORT_TMP" | sort | uniq -c | sort -nr | head -10)

# Топ-10 URL
TOP_URLS=$(awk '{print $7}' "$REPORT_TMP" | sort | uniq -c | sort -nr | head -10)

# HTTP-коды с подсчётом
HTTP_CODES=$(awk '{print $9}' "$REPORT_TMP" | grep -E '^[0-9]{3}$' | sort | uniq -c | sort -nr)

# Ошибки (4xx и 5xx) — первые 20 строк
ERRORS=$(awk '{if ($9 >= 400) print $0}' "$REPORT_TMP" | head -20)

# === Сборка письма ===
{
    echo "Subject: Nginx report ($DATE_FROM — $DATE_TO)"
    echo "To: $MAIL_TO"
    echo "Content-Type: text/plain; charset=utf-8"
    echo
    echo "=== Отчёт о работе веб-сервера ==="
    echo "Период: $DATE_FROM — $DATE_TO"
    echo "Сформирован: $(date)"
    echo "Проанализировано файлов: ${#LOG_FILES[@]}"
    echo
    echo "=== Топ IP-адресов ==="
    echo "$TOP_IPS"
    echo
    echo "=== Топ запрашиваемых URL ==="
    echo "$TOP_URLS"
    echo
    echo "=== HTTP-коды ответов ==="
    echo "$HTTP_CODES"
    echo
    echo "=== Ошибки (первые 20) ==="
    echo "$ERRORS"
} > "$REPORT_TMP.body"

# === Отправка ===
if command -v sendmail &>/dev/null; then
    sendmail -t < "$REPORT_TMP.body"
else
    mail -s "Nginx report ($DATE_FROM - $DATE_TO)" "$MAIL_TO" < "$REPORT_TMP.body"
fi

# Сохранение времени последнего запуска
echo "$CURRENT_TIME" > "$STATE_FILE"

cleanup