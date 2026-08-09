#!/bin/bash
set -e

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    echo "Запускать скрипт нужно из-под sudo."
    exit 1
fi

# Логирование
exec > >(tee -a /root/nfss_setup.log) 2>&1
echo "=== $(date) Начало настройки NFS-сервера ==="

# Переменные
SHARE_DIR="/srv/share/upload"
EXPORT_FILE="/etc/exports"
SERVER_IP="10.101.2.20"
CLIENT_IP="10.101.2.21/32"

echo "Установка nfs-kernel-server..."
apt update
apt install nfs-kernel-server -y

echo "Создание структуры каталогов..."
mkdir -p "$SHARE_DIR"

echo "Настройка прав..."
chown -R nobody:nogroup /srv/share
chmod -R 755 /srv/share
chmod 0777 "$SHARE_DIR"

echo "Настройка /etc/exports..."
cat << EOF > "$EXPORT_FILE"
/srv/share ${CLIENT_IP}(rw,sync,root_squash,no_subtree_check)
EOF

echo "Проверка экспорта..."
exportfs -r

echo "Проверка экспорта..."
exportfs -s

echo "Проверка работы NFS-сервера..."
ss -tulpn | grep -E '111|2049' || echo "Порты не найдены, проверь запуск служб."

echo "=== $(date) Настройка сервера завершена ==="