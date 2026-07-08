# Отчёт по домашнему заданию по работе с mdadm (07.06)

- **Автор:** [Павлов Сергей]
- **Дата выполнения:** [08.07.2026]
- **Задание:** Добавить в виртуальную машину несколько дисков
  Собрать RAID-0/1/5/10 на выбор
  Сломать и починить RAID
  Создать GPT таблицу, пять разделов и смонтировать их в системе.


---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: [Ubuntu 24.04.1 LTS]

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

