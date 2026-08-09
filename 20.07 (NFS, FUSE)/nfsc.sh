#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Запускать скрипт нужно из-под sudo."
    exit 1
fi

exec > >(tee -a /root/nfsc_setup.log) 2>&1
echo "=== $(date) Старт настройки NFS-клиента ==="

SERVER_IP="10.101.2.20"
MOUNT_POINT="/mnt"
FSTAB_ENTRY="${SERVER_IP}:/srv/share/ ${MOUNT_POINT} nfs vers=3,noauto,x-systemd.automount 0 0"

echo "Установка пакета nfs-common..."
apt update
apt install nfs-common -y

echo "Создание точки монтирования ${MOUNT_POINT}..."
mkdir -p "$MOUNT_POINT"

echo "Добавление записи в /etc/fstab..."
if grep -q "${SERVER_IP}:/srv/share" /etc/fstab; then
    echo "Запись уже существует, пропуск."
else
    echo "$FSTAB_ENTRY" >> /etc/fstab
fi

echo "Принудительный systemd daemon-reload и перезапуск remote-fs.target..."
systemctl daemon-reload
systemctl restart remote-fs.target

echo "Текущее монтирование:"
mount | grep mnt || echo "Автоматическое монтирование произойдёт при первом обращении к ${MOUNT_POINT}"

echo "Попытка активировать монтирование (обращение к ${MOUNT_POINT}):"
ls -la "$MOUNT_POINT" 2>/dev/null || true

echo "Проверка состояния монтирования после обращения:"
mount | grep mnt

echo "=== $(date) Настройка клиента завершена ==="