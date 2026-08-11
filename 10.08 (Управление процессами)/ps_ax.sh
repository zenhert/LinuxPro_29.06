#!/bin/bash

printf "%-8s %-8s %-6s %s\n" "PID" "PPID" "STATE" "COMMAND"

for pid_dir in /proc/[0-9]*; do
    pid="${pid_dir##*/}"
    
    # Пропуск, если процесс уже завершился
    if [[ ! -d "$pid_dir" ]]; then
        continue
    fi

    # Чтение status
    status_file="$pid_dir/status"
    if [[ ! -f "$status_file" ]]; then
        continue
    fi

    ppid=$(grep -E '^PPid:' "$status_file" 2>/dev/null | awk '{print $2}')
    state=$(grep -E '^State:' "$status_file" 2>/dev/null | awk '{print $2}')
    
    # Пропуск, если не удалось извлечь
    [[ -z "$ppid" ]] && ppid="?"
    [[ -z "$state" ]] && state="?"

    # Чтение команды из cmdline
    cmdline_file="$pid_dir/cmdline"
    if [[ -f "$cmdline_file" ]]; then
        # Замена нулевых байтов на пробелы
        cmd=$(tr '\0' ' ' < "$cmdline_file" 2>/dev/null)
        # Если командная строка пуста, использование имя из comm
        if [[ -z "$cmd" ]]; then
            cmd=$(cat "$pid_dir/comm" 2>/dev/null)
        fi
    else
        cmd=$(cat "$pid_dir/comm" 2>/dev/null)
    fi

    # Если не удалось прочитать comm
    [[ -z "$cmd" ]] && cmd="?"

    printf "%-8s %-8s %-6s %s\n" "$pid" "$ppid" "$state" "$cmd"
done