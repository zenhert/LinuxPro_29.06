# Отчёт по домашнему заданию по обновлению ядра Linux (06.29)

- **Автор:** [Павлов Сергей]
- **Дата выполнения:** [01.07.2026]
- **Задание:** Обновить ядро до актуальной версии.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: [Ubuntu 22.04.5 LTS]
- Текущая версия ядра:
  [zenhert@lp:~$ uname -r
    5.15.0-185-generic]

---

## Ход работы

### 1. Поиск и скачивание пакетов на ВМ
https://kernel.ubuntu.com/mainline/v7.1.2/amd64/
```
zenhert@lp:~$ mkdir distr && cd distr
zenhert@lp:~/distr$
zenhert@lp:~/distr$ wget https://kernel.ubuntu.com/mainline/v7.1.2/amd64/linux-headers-7.1.2-070102-generic_7.1.2-070102.202606271039_amd64.deb
zenhert@lp:~/distr$ wget https://kernel.ubuntu.com/mainline/v7.1.2/amd64/linux-headers-7.1.2-070102_7.1.2-070102.202606271039_all.deb
zenhert@lp:~/distr$ wget https://kernel.ubuntu.com/mainline/v7.1.2/amd64/linux-image-unsigned-7.1.2-070102-generic_7.1.2-070102.202606271039_amd64.deb
zenhert@lp:~/distr$ wget https://kernel.ubuntu.com/mainline/v7.1.2/amd64/linux-modules-7.1.2-070102-generic_7.1.2-070102.202606271039_amd64.deb
```

### 2. Установка пакетов
```
zenhert@lp:~/distr$ sudo dpkg -i *.deb
```
Во время установки пакетов возникла проблема. Я пытался установить самое свежее ядро 7.1.2 на Ubuntu 22.04 чтобы посмотреть что будет (интереса ради). Однако, как оказалось, новое ядро требует более новых версий системных библиотек (libc6, libdw1t64, libelf1t64, libssl3t64), которых в старом ядре нет. Пакеты с суффиксом t64 появились только в Ubuntu 24.04.

### 3. Проверка установки
```
zenhert@lp:~$ ls -al /boot
-rw-r--r--  1 root root    307299 Jun 27 10:39 config-7.1.2-070102-generic
-rw-r--r--  1 root root 186216018 Jul  1 15:14 initrd.img-7.1.2-070102-generic
-rw-------  1 root root  11899340 Jun 27 10:39 System.map-7.1.2-070102-generic
-rw-------  1 root root  17457664 Jun 27 10:39 vmlinuz-7.1.2-070102-generic
lrwxrwxrwx  1 root root        26 Jun 30 15:17 vmlinuz.old -> vmlinuz-5.15.0-185-generic
```
Сам образ ядра и модули установились успешно. Не настроились только заголовки (linux-headers). Это критично только при планировки компилировании модулей ядра.
Обновлять конфигурацию загрузчика не стал, т.к. данная ВМ создавалась только для задания и эксперимента, в дальнейших заданиях будет использоваться Ubuntu 24.04

### 4. Проверка версии ядра
```
zenhert@lp:~$ uname -r
7.1.2-070102-generic
```
На этом обновление ядра закончено.