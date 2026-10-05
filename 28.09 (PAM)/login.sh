#!/bin/bash
# Скрипт для PAM: запрет входа в выходные для всех, кроме группы admin

# Если день недели суббота или воскресенье
if [ "$(date +%a)" = "Sat" ] || [ "$(date +%a)" = "Sun" ]; then
    # Проверка, входит ли пользователь в группу admin
    if getent group admin | grep -qw "$PAM_USER"; then
        exit 0   # админ — пропуск
    else
        exit 1   # не админ — запрет
    fi
else
    exit 0       # будний день — пропуск всех
fi
