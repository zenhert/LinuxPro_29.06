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
- Хостовая ОС: Ubuntu 24.04.1 LTS

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
Можно приступать к созданию RAID-массива.

### 2. Сборка RAID-10
Создание RAID-массива:
```
zenhert@linpro:~$ sudo mdadm --create --verbose /dev/md0 -l 10 -n 4 /dev/sd{c,d,e,f}
mdadm: layout defaults to n2
mdadm: layout defaults to n2
mdadm: chunk size defaults to 512K
mdadm: size set to 10476544K
mdadm: Defaulting to version 1.2 metadata
mdadm: array /dev/md0 started.
```

Проверка сборки:
```
zenhert@linpro:~$ cat /proc/mdstat
md0 : active raid10 sdf[3] sde[2] sdd[1] sdc[0]
      20953088 blocks super 1.2 512K chunks 2 near-copies [4/4] [UUUU]
```
```
zenhert@linpro:~$ sudo mdadm -D /dev/md0
/dev/md0:
        Raid Level : raid10
    Number   Major   Minor   RaidDevice State
       0       8       32        0      active sync set-A   /dev/sdc
       1       8       48        1      active sync set-B   /dev/sdd
       2       8       64        2      active sync set-A   /dev/sde
       3       8       80        3      active sync set-B   /dev/sdf
```
RAID собрался успешно.

### 3. Вывод из строя RAID-массива
Для эмуляции выход из строя отного из дисков массива, "зафейлил" один из дисков вручную:
```
zenhert@linpro:~$ sudo mdadm /dev/md0 --fail /dev/sdc
mdadm: set /dev/sdc faulty in /dev/md0
zenhert@linpro:~$ cat /proc/mdstat
md0 : active raid10 sdf[3] sde[2] sdd[1] sdc[0](F)
      20953088 blocks super 1.2 512K chunks 2 near-copies [4/3] [_UUU]
zenhert@linpro:~$ sudo mdadm -D /dev/md0
/dev/md0:
        Raid Level : raid10
             State : clean, degraded
    Active Devices : 3
   Working Devices : 3
    Failed Devices : 1
     Spare Devices : 0
    Number   Major   Minor   RaidDevice State
       -       0        0        0      removed
       1       8       48        1      active sync set-B   /dev/sdd
       2       8       64        2      active sync set-A   /dev/sde
       3       8       80        3      active sync set-B   /dev/sdf
       0       8       32        -      faulty   /dev/sdc
```

Диск выведен из строя, теперь его необходимо удалить:
```
zenhert@linpro:~$ sudo mdadm /dev/md0 --remove /dev/sdc
mdadm: hot removed /dev/sdc from /dev/md0
```

Теперь необходимо добавить новый диск для восстановления массива:
```
zenhert@linpro:~$ sudo mdadm /dev/md0 --add /dev/sdc
mdadm: added /dev/sdc
```

Диск должен пройти стадию rebuilding, проверим состояние:
```
zenhert@linpro:~$ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10]
md0 : active raid10 sdc[4] sdf[3] sde[2] sdd[1]
      20953088 blocks super 1.2 512K chunks 2 near-copies [4/4] [UUUU]
unused devices: <none>
```
```
zenhert@linpro:~$ sudo mdadm -D /dev/md0
/dev/md0:
        Raid Level : raid10
             State : clean
    Active Devices : 4
   Working Devices : 4
    Failed Devices : 0
     Spare Devices : 0
    Number   Major   Minor   RaidDevice State
       4       8       32        0      active sync set-A   /dev/sdc
       1       8       48        1      active sync set-B   /dev/sdd
       2       8       64        2      active sync set-A   /dev/sde
       3       8       80        3      active sync set-B   /dev/sdf
```
RAID-массив восстановлен.

### 4. Создание GPT таблицы и разделов на RAID-массиве
Создание таблицы GPT
```
zenhert@linpro:~$ sudo parted -s /dev/md0 mklabel gpt
```

Создание разделов:
```
zenhert@linpro:~$ sudo parted /dev/md0 mkpart primary ext4 0% 20%
zenhert@linpro:~$ sudo parted /dev/md0 mkpart primary ext4 20% 40%
zenhert@linpro:~$ sudo parted /dev/md0 mkpart primary ext4 40% 60%
zenhert@linpro:~$ sudo parted /dev/md0 mkpart primary ext4 60% 80%
zenhert@linpro:~$ sudo parted /dev/md0 mkpart primary ext4 80% 100%
```

Создание файловой системы на разделах:
```
zenhert@linpro:~$ for i in $(seq 1 5); do sudo mkfs.ext4 /dev/md0p$i; done
Filesystem UUID: 4fc5f7d6-aee1-4019-92a5-0673e5969789
Filesystem UUID: 87a2b4d9-fb02-4c86-bfd5-40710551830b
Filesystem UUID: a492090d-86d1-465f-99c8-23ba3e0738b8
Filesystem UUID: 08c94f7d-4d85-4686-be6f-25397a58a1b3
Filesystem UUID: 6bbec936-67c5-4b69-83e2-be9eadf9a357
```

Монтирование разделов по каталогам:
```
zenhert@linpro:~$ sudo mkdir -p /raid/part{1,2,3,4,5}
zenhert@linpro:~$ sudo -i
root@linpro:~# for i in $(seq 1 5); do mount /dev/md0p$i /raid/part$i; done
```

Таблица GPT создана, разделы смонтированы.