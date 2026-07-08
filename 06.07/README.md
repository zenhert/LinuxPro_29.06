# Отчёт по домашнему заданию по работе с mdadm (07.06)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 08.07.2026
- **Задание:** 
  - Добавить в виртуальную машину несколько дисков
  - Собрать RAID-0/1/5/10 на выбор
  - Сломать и починить RAID
  - Создать GPT таблицу, пять разделов и смонтировать их в системе

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: [Ubuntu 24.04.1 LTS]

---

## Ход работы

### 1. Добавление и подготовка дисков
Проверка наличия дисков и их размера:
```
zenhert@linpro:~$ sudo lshw -short | grep disk
/0/3/0.0.0    /dev/sda    disk       429GB Virtual disk
/0/3/0.1.0    /dev/sdb    disk       107GB Virtual disk
/0/3/0.2.0    /dev/sdc    disk       10GB Virtual disk
/0/3/0.3.0    /dev/sdd    disk       10GB Virtual disk
/0/3/0.4.0    /dev/sde    disk       10GB Virtual disk
/0/3/0.5.0    /dev/sdf    disk       10GB Virtual disk
/0/2/0.0.0    /dev/cdrom  disk       VMware SATA CD00
```

zenhert@linpro:~$ sudo fdisk -l
```
Disk /dev/sdf: 10 GiB, 10737418240 bytes, 20971520 sectors
Disk model: Virtual disk
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes

Disk /dev/sdd: 10 GiB, 10737418240 bytes, 20971520 sectors
Disk model: Virtual disk
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes

Disk /dev/sdc: 10 GiB, 10737418240 bytes, 20971520 sectors
Disk model: Virtual disk
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes

Disk /dev/sde: 10 GiB, 10737418240 bytes, 20971520 sectors
Disk model: Virtual disk
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
```
Зануление суперблоков:
```
zenhert@linpro:~$ sudo mdadm --zero-superblock --force /dev/sd{c,d,e,f}
mdadm: Unrecognised md component device - /dev/sdc
mdadm: Unrecognised md component device - /dev/sdd
mdadm: Unrecognised md component device - /dev/sde
mdadm: Unrecognised md component device - /dev/sdf
```
Данный вывод говорит, что утилита mdadm не обнаружила на указанных дисках метаданных.
```
zenhert@linpro:~$ sudo mdadm --examine /dev/sd{c,d,e,f}
mdadm: No md superblock detected on /dev/sdc.
mdadm: No md superblock detected on /dev/sdd.
mdadm: No md superblock detected on /dev/sde.
mdadm: No md superblock detected on /dev/sdf.
```
Проверка показала отсутствие суперблоков, диски чисты.