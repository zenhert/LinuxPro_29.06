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


root@linpro:~# pvcreate /dev/sdb2
WARNING: ext4 signature detected on /dev/sdb2 at offset 1080. Wipe it? [y/n]: y
  Wiping ext4 signature on /dev/sdb2.
  Physical volume "/dev/sdb2" successfully created.

root@linpro:~# vgcreate vg_root /dev/sdb2
  Volume group "vg_root" successfully created



root@linpro:~# lvcreate -n vg_root/lv_root -L 8G /dev/vg_root
  Logical volume "lv_root" created.


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


root@linpro:~# mkfs.ext4 /dev/vg_root/lv_root
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2097152 4k blocks and 524288 inodes
Filesystem UUID: e393ea2c-9b40-41a1-af70-a9da90dcc28e
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632




root@linpro:~# rsync -avxHAX --progress / /mnt/
sent 7,175,365,319 bytes  received 1,601,533 bytes  103,265,710.10 bytes/sec
total size is 7,171,856,940  speedup is 1.00



root@linpro:~# for i in /proc/ /sys/ /dev/ /run/ /boot/; do mount --bind $i /mnt/$i; done


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

root@linpro:~# exit
root@linpro:~# reboot



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

