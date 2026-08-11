# Отчёт по домашнему заданию по работе по управлению процессами (10.08)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 11.08.2026
- **Задание:** 

      Вариант 1. Реализация аналога ps ax:
      - Создайте скрипт, который получает информацию о процессах через файловую систему /proc;
      - Реализуйте вывод не менее следующих полей: PID, PPID, состояние процесса, имя или команда запуска;
      - Проверьте работу скрипта на запущенной системе;
      - Зафиксируйте пример результата работы.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы

### 1. Создание скрипта, который получает информацию о процессах через файловую систему /proc
Скрипт читает каталоги `/proc/[0-9]*`:
  - PID – идентификатор процесса;
  - PPID – родительский PID (из /proc/PID/status);
  - STATE – состояние (например S, R, D, Z, T);
  - COMMAND – командная строка (из /proc/PID/cmdline, с заменой нулевых байтов на пробелы).

### 2. Реализация вывода и проверка скрипта
Выдача прав на выполнение и исполнение скрипта:
```
zenhert@linpro:~$ chmod +x ps_ax.sh
zenhert@linpro:~$ bash ./ps_ax.sh
PID      PPID     STATE  COMMAND
1        0        S      /usr/lib/systemd/systemd --system --deserialize=62
103      2        I      kworker/R-mld
104      2        I      kworker/2:1H-kblockd
105      2        I      kworker/R-ipv6_
34       2        S      idle_inject/3
35       2        S      migration/3
355      2        I      kworker/R-raid5
36       2        S      ksoftirqd/3
368334   2        I      kworker/6:2-events
371023   2        I      kworker/7:2-events
37318    1        S      /usr/lib/systemd/systemd-timesyncd
37387    1        S      /usr/lib/systemd/systemd-udevd
37389    2        S      psimon
37666    1        S      /usr/bin/VGAuthService
37667    1        S      /usr/bin/vmtoolsd
38       2        I      kworker/3:0H-events_highpri
38415    1        S      /usr/lib/systemd/systemd-resolved
39       2        S      cpuhp/4
396      2        S      jbd2/dm-0-8
397      2        I      kworker/R-ext4-
4        2        I      kworker/R-rcu_g
40       2        S      idle_inject/4
41       2        S      migration/4
42       2        S      ksoftirqd/4
434752   2        I      kworker/1:0-events
43490    1        S      /sbin/multipathd -d -s
438244   2        I      kworker/1:1-cgroup_release
44       2        I      kworker/4:0H-events_highpri
440067   2        I      kworker/2:1-cgroup_free
440332   2        I      kworker/4:1-events
441464   2        I      kworker/4:0-cgroup_release
441880   2        I      kworker/5:0-events
442640   2        I      kworker/3:0
443010   94455    S      pickup -l -t unix -u -c
443046   2        I      kworker/0:2-cgroup_free
443163   2        I      kworker/u16:0-events_power_efficient
443332   2        I      kworker/u16:3-events_unbound
443357   49201    S      sshd: zenhert [priv]
443364   49201    S      sshd: zenhert [priv]
443463   443357   S      sshd: zenhert@pts/0
443464   443463   S      -bash
443521   443364   S      sshd: zenhert@notty
443523   443521   S      /usr/lib/openssh/sftp-server
443683   2        I      kworker/6:1
444390   2        I      kworker/7:1-cgroup_free
446621   2        I      kworker/5:2-cgroup_release
446627   2        I      kworker/u16:1-flush-252:0
446652   2        I      kworker/5:1-cgroup_free
...
```

Скрипт использует только стандартные утилиты Linux (bash, awk, grep, tr) и не требует установки дополнительных пакетов.