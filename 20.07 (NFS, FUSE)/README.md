# Отчёт по домашнему заданию по работе с NFS (16.07)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 09.08.2026
- **Задание:** 
  - Запустить 2 виртуальных машины (сервер NFS и клиента);
  - На сервере NFS должна быть подготовлена и экспортирована директория;
  - В экспортированной директории должна быть поддиректория с именем upload с правами на запись в неё;
  - Экспортированная директория должна автоматически монтироваться на клиенте при старте виртуальной машины (systemd, autofs или fstab — любым способом);
  - Монтирование и работа NFS на клиенте должна быть организована с использованием NFSv3.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS
- Сервер NFS (`nfss`): 10.101.2.20/24
- Клиент NFS (`nfsc`): 10.101.2.21/24

---

## Ход работы

### 1. Подготовка и описание скриптов для автоматической настройки NFS
Серверный скрипт (`nfss.sh`):
  - Устанавливает пакет `nfs-kernel-server`;
  - Создаёт каталог `/srv/share/upload` и назначает владельца `nobody:nogroup`;
  - Устанавливает права `755` на `/srv/share` и `777` на `/srv/share/upload` (для записи);
  - Настраивает `/etc/exports` для экспорта `/srv/share` клиенту `10.101.2.21/32` с опциями `rw,sync,root_squash,no_subtree_check`;
  - Применяет экспорт (`exportfs -r`) и выводит статус.

Клиентский скрипт (`nfsc.sh`):
  - Устанавливает пакет `nfs-common`;
  - Создаёт точку монтирования `/mnt`;
  - Добавляет в `/etc/fstab` запись для автоматического монтирования через `systemd.automount` с явным указанием `vers=3`;
  - Выполняет `systemctl daemon-reload` и `systemctl restart remote-fs.target`;
  - Выводит статус монтирования после первого обращения к `/mnt`.

### 2. Проверка работоспособности:
На сервере 10.101.2.20:
Создание проверочного файла
```
zenhert@nfss:~$ cd /srv/share/upload/
zenhert@nfss:/srv/share/upload$ touch check_file
zenhert@nfss:/srv/share/upload$ ls -la
total 8
drwxrwxrwx 2 nobody  nogroup 4096 Aug  9 20:18 .
drwxr-xr-x 3 nobody  nogroup 4096 Aug  9 19:10 ..
-rw-rw-r-- 1 zenhert zenhert    0 Aug  9 20:18 check_file
```

На клиенте 10.101.2.21:
Монтирование шары и проверка наличия проверочного файла, а также создание второго проверочного файла
```
zenhert@nfsc:/mnt/upload$ ls -la
total 8
drwxrwxrwx 2 nobody  nogroup 4096 Aug  9 20:18 .
drwxr-xr-x 3 nobody  nogroup 4096 Aug  9 19:10 ..
-rw-rw-r-- 1 zenhert zenhert    0 Aug  9 20:18 check_file
zenhert@nfsc:/mnt/upload$ touch client_file
zenhert@nfsc:/mnt/upload$ ls -la
total 8
drwxrwxrwx 2 nobody  nogroup 4096 Aug  9 20:19 .
drwxr-xr-x 3 nobody  nogroup 4096 Aug  9 19:10 ..
-rw-rw-r-- 1 zenhert zenhert    0 Aug  9 20:18 check_file
-rw-rw-r-- 1 zenhert zenhert    0 Aug  9 20:19 client_file
```

Снова на сервере 10.101.2.20:
Проверка появления файла, созданного на клиентской ВМ
```
zenhert@nfss:/srv/share/upload$ ls -la /srv/share/upload/
total 8
drwxrwxrwx 2 nobody  nogroup 4096 Aug  9 20:19 .
drwxr-xr-x 3 nobody  nogroup 4096 Aug  9 19:10 ..
-rw-rw-r-- 1 zenhert zenhert    0 Aug  9 20:18 check_file
-rw-rw-r-- 1 zenhert zenhert    0 Aug  9 20:19 client_file
```

Оба файла видны с обеих сторон - связка работает.
Выполненные скрипты логируют свои действия в `/root/nfss_setup.log` и `/root/nfsc_setup.log` соответственно. Данные файлы также приложены.
PS: При необходимости скрипты можно адаптировать под другие IP-адреса, изменив переменные в начале каждого скрипта.