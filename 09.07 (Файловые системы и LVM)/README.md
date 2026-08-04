# Отчёт по домашнему заданию по работе с LVM (09.07)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 16.07.2026
- **Задание:** 
  - Уменьшить том под / до 8G
  - Выделить том под /home
  - Выделить том под /var - сделать в mirror
  - /home - сделать том для снапшотов
  - Прописать монтирование в fstab. Попробовать с разными опциями и разными файловыми системами (на выбор)
  - Работа со снапшотами:
    - сгенерить файлы в /home/
    - снять снапшот
    - удалить часть файлов
    - восстановиться со снапшота

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы

### 1. Уменьшить том под / до 8G
Проверка наличия дисков и их размера:
```
root@linpro:~# lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda      8:0    0  400G  0 disk
sdb      8:16   0  100G  0 disk
├─sdb1   8:17   0    1G  0 part /boot/efi
└─sdb2   8:18   0 98.9G  0 part /
sdc      8:32   0   10G  0 disk
sdd      8:48   0   10G  0 disk
sde      8:64   0   10G  0 disk
sdf      8:80   0   10G  0 disk
sr0     11:0    1 1024M  0 rom
```

Подготовка тома для / раздела:
```
root@linpro:~# pvcreate /dev/sdc
  Physical volume "/dev/sdc" successfully created.
root@linpro:~# vgcreate vg_zen /dev/sdc
  Volume group "vg_zen" successfully created
root@linpro:~# lvcreate -n lv_zen -l +100%FREE /dev/vg_zen -y
  Logical volume "lv_zen" created.
```

Создание файловой системы и монтирование:
```
root@linpro:~# mkfs.ext4 /dev/vg_zen/lv_zen
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2620416 4k blocks and 655360 inodes
Filesystem UUID: 5a826aa6-7293-4405-ad60-97fe36e32efc
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632
```
```
root@linpro:~# mount /dev/vg_zen/lv/zen /mnt
mount: /mnt: special device /dev/vg_zen/lv/zen does not exist.
       dmesg(1) may have more information after failed mount system call.
root@linpro:~# mount /dev/vg_zen/lv_zen /mnt
root@linpro:~# rsync -avxHAX --progress / /mnt/
sent 7,149,870,503 bytes  received 1,601,491 bytes  150,557,305.14 bytes/sec
total size is 7,146,374,175  speedup is 1.00
```

Конфигурирование grub для перехода на новый /:
```
root@linpro:~# for i in /proc/ /sys/ /dev/ /run/ /boot/;  do mount --bind $i /mnt/$i; done
root@linpro:~# chroot /mnt/
root@linpro:/# grub-mkconfig -o /boot/grub/grub.cfg
Sourcing file `/etc/default/grub'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.8.0-134-generic
Found initrd image: /boot/initrd.img-6.8.0-134-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done
```

Обновление образа initrd:
```
root@linpro:/# update-initramfs -u
update-initramfs: Generating /boot/initrd.img-6.8.0-134-generic
root@linpro:~# exit
root@linpro:~# reboot
```

Новый раздел подготовлен:
```
zenhert@linpro:~$ lsblk
NAME            MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda               8:0    0  400G  0 disk
sdb               8:16   0  100G  0 disk
├─sdb1            8:17   0    1G  0 part /boot/efi
└─sdb2            8:18   0 98.9G  0 part
sdc               8:32   0   10G  0 disk
└─vg_zen-lv_zen 252:0    0   10G  0 lvm  /
sdd               8:48   0   10G  0 disk
sde               8:64   0   10G  0 disk
sdf               8:80   0   10G  0 disk
sr0              11:0    1 1024M  0 rom
```

Необходимо изменить размер тома и вернуть на него рут:

Создание физического тома LVM:
```
root@linpro:~# pvcreate /dev/sdb2
WARNING: ext4 signature detected on /dev/sdb2 at offset 1080. Wipe it? [y/n]: y
  Wiping ext4 signature on /dev/sdb2.
  Physical volume "/dev/sdb2" successfully created.
```

Создание группы томов на физическом:
```
root@linpro:~# vgcreate vg_root /dev/sdb2
  Volume group "vg_root" successfully created
```

Создание логического тома размером 8G:
```
root@linpro:~# lvcreate -n vg_root/lv_root -L 8G /dev/vg_root
  Logical volume "lv_root" created.
```

Проверка нового тома:
```
root@linpro:~# lsblk
NAME                MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                   8:0    0  400G  0 disk
sdb                   8:16   0  100G  0 disk
├─sdb1                8:17   0    1G  0 part /boot/efi
└─sdb2                8:18   0 98.9G  0 part
  └─vg_root-lv_root 252:1    0    8G  0 lvm
sdc                   8:32   0   10G  0 disk
└─vg_zen-lv_zen     252:0    0   10G  0 lvm  /
sdd                   8:48   0   10G  0 disk
sde                   8:64   0   10G  0 disk
sdf                   8:80   0   10G  0 disk
sr0                  11:0    1 1024M  0 rom
root@linpro:~#
```

Создание файловой системы и монтирование:
```
root@linpro:~# mkfs.ext4 /dev/vg_root/lv_root
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2097152 4k blocks and 524288 inodes
Filesystem UUID: e393ea2c-9b40-41a1-af70-a9da90dcc28e
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632
```
```
root@linpro:~# rsync -avxHAX --progress / /mnt/
sent 7,175,365,319 bytes  received 1,601,533 bytes  103,265,710.10 bytes/sec
total size is 7,171,856,940  speedup is 1.00
```

Конфигурирование grub:
```
root@linpro:~# for i in /proc/ /sys/ /dev/ /run/ /boot/; do mount --bind $i /mnt/$i; done
```
```
root@linpro:~# chroot /mnt/
root@linpro:/# grub-mkconfig -o /boot/grub/grub.cfg
Sourcing file `/etc/default/grub'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.8.0-134-generic
Found initrd image: /boot/initrd.img-6.8.0-134-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done
```

Выход из chroot и перезагрузка:
```
root@linpro:~# exit
root@linpro:~# reboot
```

Проверка успешного переноса /:
```
zenhert@linpro:~$ lsblk
NAME                MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                   8:0    0  400G  0 disk
sdb                   8:16   0  100G  0 disk
├─sdb1                8:17   0    1G  0 part /boot/efi
└─sdb2                8:18   0 98.9G  0 part
  └─vg_root-lv_root 252:1    0    8G  0 lvm  /
sdc                   8:32   0   10G  0 disk
└─vg_zen-lv_zen     252:0    0   10G  0 lvm
sdd                   8:48   0   10G  0 disk
sde                   8:64   0   10G  0 disk
sdf                   8:80   0   10G  0 disk
sr0                  11:0    1 1024M  0 rom
zenhert@linpro:~$
```

### 2. Выделить том /home
Выделение тома под /home:
```
zenhert@linpro:~$ sudo lvcreate -n lv_home -L 2G vg_root
  Logical volume "lv_home" created.
```

Создание логического тома размером 2G и создание файловой системы:
```
zenhert@linpro:~$ sudo mkfs.ext4 /dev/vg_root/lv_home
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 524288 4k blocks and 131072 inodes
Filesystem UUID: 8d96f29f-b113-4ba8-a06f-a0a53185f5e8
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912

Allocating group tables: done
Writing inode tables: done
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done
```

Монтирование и копирование содержимого /home в новый том:
```
zenhert@linpro:~$ sudo mount /dev/vg_root/lv_home /mnt
zenhert@linpro:~$ sudo rsync -avxHAX --progress /home/ /mnt/

sent 7,123 bytes  received 206 bytes  14,658.00 bytes/sec
total size is 6,284  speedup is 0.86
```

Очистка старого /home и монтирование нового тома:
```
zenhert@linpro:~$ sudo rm -rf /home/*
zenhert@linpro:~$ sudo umount /mnt/
zenhert@linpro:~$ sudo mount /dev/vg_root/lv_home /home
zenhert@linpro:~$ lsblk /dev/vg_root/lv_home
NAME            MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
vg_root-lv_home 252:2    0   2G  0 lvm  /home
```

Настройка автоматического монтирования:
```
root@linpro:~# echo "`blkid | grep home | awk '{print $2}'` \
/home ext4 defaults 0 0" >> /etc/fstab
```

Финальная проверка:
```
zenhert@linpro:~$ mount -a
zenhert@linpro:~$ cat -n /etc/fstab | grep home
    13  UUID="8d96f29f-b113-4ba8-a06f-a0a53185f5e8" /home ext4 defaults 0 0
```

### 3. Выделить том под /var в зеркало
Создание физического тома на дисках для зеркала:
```
zenhert@linpro:~$ sudo pvcreate /dev/sdd /dev/sde
  Physical volume "/dev/sdd" successfully created.
  Physical volume "/dev/sde" successfully created.
```

Создание группы томов для /var:
```
zenhert@linpro:~$ sudo vgcreate vg_var /dev/sdd /dev/sde
  Volume group "vg_var" successfully created
```

Создание логического тома с зеркалированием:
```
zenhert@linpro:~$ sudo lvcreate -L 950M -m1 -n lv_var vg_var
  Rounding up size to full physical extent 952.00 MiB
  Logical volume "lv_var" created.
```

Создание файловой системы, монтирование и копирование текущего /var:
```
zenhert@linpro:~$ sudo mkfs.ext4 /dev/vg_var/lv_var
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 243712 4k blocks and 60928 inodes
Filesystem UUID: b4fad066-fc41-49f5-bcf3-ea5e28bb87dd
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376

Allocating group tables: done
Writing inode tables: done
Creating journal (4096 blocks): done
Writing superblocks and filesystem accounting information: done
```
```
zenhert@linpro:~$ sudo mount /dev/vg_var/lv_var /mnt
zenhert@linpro:~$ sudo cp -aR /var/* /mnt/
```

Удаление старого /var и монтирование нового
```
zenhert@linpro:~$ sudo rm -rf /var/*
zenhert@linpro:~$ sudo umount /mnt
zenhert@linpro:~$ sudo mount /dev/vg_var/lv_var /var
```

Проверка монтирования:
```
zenhert@linpro:~$ ls /var
backups  cache  crash  lib  local  lock  log  lost+found  mail  opt  run  snap  spool  tmp
zenhert@linpro:~$ df -hT /var
Filesystem                Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_var-lv_var ext4  919M  682M  174M  80% /var
```

Автоматическое монтирование:
```
root@linpro:~# echo "`blkid | grep var | awk '{print $2}'` /var ext4 defaults 0 0" >> /etc/fstab
root@linpro:~# cat /etc/fstab | grep var
UUID="b4fad066-fc41-49f5-bcf3-ea5e28bb87dd" /var ext4 defaults 0 0
```

Финальная проверка всего fstab:
```
root@linpro:~# cat /etc/fstab
UUID="8d96f29f-b113-4ba8-a06f-a0a53185f5e8" /home ext4 defaults 0 0
UUID="b4fad066-fc41-49f5-bcf3-ea5e28bb87dd" /var ext4 defaults 0 0
```

### 4. Работа со снапшотами
Генерация файлов, снятие снапшота, удаление части файлов:
```
root@linpro:~# touch /home/file{1..20}
root@linpro:~# lvcreate -L 100M -s -n home_snap /dev/vg_root/lv_home
  Logical volume "home_snap" created.
root@linpro:~# rm -f /home/file{11..20}
```

Восстановление из снапшота:
```
root@linpro:~# umount /home
root@linpro:~# lvconvert --merge /dev/vg_root/home_snap
  Merging of volume vg_root/home_snap started.
  vg_root/lv_home: Merged: 100.00%
root@linpro:~# mount /home
```

Проверка восстановления:
```
root@linpro:~# ls /home
file1  file10  file11  file12  file13  file14  file15  file16  file17  file18  file19  file2  file20  file3  file4  file5  file6  file7  file8  file9  lost+found  zenhert
```