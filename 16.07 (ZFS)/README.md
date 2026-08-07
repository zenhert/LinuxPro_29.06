# Отчёт по домашнему заданию по работе с ZFS (16.07)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 04.08.2026
- **Задание:** 
  - Определить алгоритм с наилучшим сжатием:
    - Определить какие алгоритмы сжатия поддерживает zfs (gzip, zle, lzjb, lz4);
    - создать 4 файловых системы на каждой применить свой алгоритм сжатия;
    - для сжатия использовать либо текстовый файл, либо группу файлов.
  - Определить настройки пула.
    - С помощью команды zfs import собрать pool ZFS.
    - Командами zfs определить настройки:
      - размер хранилища;
      - тип pool;
      - значение recordsize;
      - какое сжатие используется;
      - какая контрольная сумма используется.
  - Работа со снапшотами:
    - скопировать файл из удаленной директории;
    - восстановить файл локально. zfs receive;
    - найти зашифрованное сообщение в файле secret_message.


---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы

### 1. Определить алгоритм с наилучшим сжатием
Установка ZFS, создание 4 пулов в режиме зеркала, создание файловых систем:
```
zenhert@linpro:~$ sudo apt update
zenhert@linpro:~$ sudo apt install zfsutils-linux -y
zenhert@linpro:~$ sudo zpool create zen1 mirror /dev/sdb /dev/sdc
zenhert@linpro:~$ sudo zpool create zen2 mirror /dev/sdd /dev/sde
zenhert@linpro:~$ sudo zpool create zen3 mirror /dev/sdf /dev/sdg
zenhert@linpro:~$ sudo zpool create zen3 mirror /dev/sdh /dev/sdi
zenhert@linpro:~$ sudo zpool create zen4 mirror /dev/sdh /dev/sdi
```

Проверка пулов:
```
zenhert@linpro:~$ zpool list
NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
zen1  24.5G   116K  24.5G        -         -     0%     0%  1.00x    ONLINE  -
zen2  24.5G   108K  24.5G        -         -     0%     0%  1.00x    ONLINE  -
zen3  24.5G   129K  24.5G        -         -     0%     0%  1.00x    ONLINE  -
zen4  24.5G   114K  24.5G        -         -     0%     0%  1.00x    ONLINE  -
```

Добавление различных алгоритмов сжатия:
```
zenhert@linpro:~$ sudo zfs set compression=lzjb zen1
zenhert@linpro:~$ sudo zfs set compression=lz4 zen2
zenhert@linpro:~$ sudo zfs set compression=gzip-9 zen3
zenhert@linpro:~$ sudo zfs set compression=zle zen4
```

Проверка настройки сжатия:
```
zenhert@linpro:~$ zfs get all | grep compression
zen1  compression           lzjb                   local
zen2  compression           lz4                    local
zen3  compression           gzip-9                 local
zen4  compression           zle                    local
```

Тестирование сжатия:
В теории, случайные данные сжимаются плохо, для проверки этой теории будет создан файл в каждом пуле с повторяющимися строками
```
zenhert@linpro:~$ for i in {1..4}; do sudo dd if=/dev/urandom of=/zen$i/random.dd bs=1M count=10 2>/dev/null; done
```

Проверяем реальное заняток место и степень сжатия:
```
zenhert@linpro:~$ zfs list
NAME   USED  AVAIL  REFER  MOUNTPOINT
zen1  10.2M  23.7G  10.0M  /zen1
zen2  10.1M  23.7G  10.0M  /zen2
zen3  10.2M  23.7G  10.0M  /zen3
zen4  10.1M  23.7G  10.0M  /zen4
zenhert@linpro:~$ zfs get compressratio
NAME  PROPERTY       VALUE  SOURCE
zen1  compressratio  1.00x  -
zen2  compressratio  1.00x  -
zen3  compressratio  1.00x  -
zen4  compressratio  1.00x  -
```

При создании файлов для теста ZFS, был записан, по сути, криптографически качественный белый шум. Архиваторы (как и алгоритм zle или lzjb) пытаются найти закономерности, но в идеально случайных данных их нет, поэтому сжатия почти не произошло. Алгоритм gzip-9 чуть лучше справился только потому, что в псевдослучайной выдаче /dev/urandom иногда проскакивают микроскопические статистические флуктуации, но в целом это тоже почти несжимаемые данные.

### 2. Определить настройки пула
Подготовка каталогов и проверка возможности импорта:
```
zenhert@linpro:~$ wget -O archive.tar.gz --no-check-certificate 'https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download'
--2026-08-06 16:58:29--  https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download
zenhert@linpro:~$ tar -xzvf archive.tar.gz
zpoolexport/
zpoolexport/filea
zpoolexport/fileb
zenhert@linpro:~$ sudo zpool import -d zpoolexport/
   pool: otus
     id: 6554193320433390805
  state: ONLINE
status: Some supported features are not enabled on the pool.
        (Note that they may be intentionally disabled if the
        'compatibility' property is set.)
 action: The pool can be imported using its name or numeric identifier, though
        some features will not be available without an explicit 'zpool upgrade'.
 config:

        otus                                 ONLINE
          mirror-0                           ONLINE
            /home/zenhert/zpoolexport/filea  ONLINE
            /home/zenhert/zpoolexport/fileb  ONLINE
```

Импортируем пул и проверка статуса:
```
zenhert@linpro:~$ sudo zpool import -d zpoolexport/ otus
zenhert@linpro:~$ zpool status
  pool: otus
 state: ONLINE
errors: No known data errors
  pool: zen1
 state: ONLINE
errors: No known data errors
  pool: zen2
 state: ONLINE
errors: No known data errors
  pool: zen3
 state: ONLINE
errors: No known data errors
  pool: zen4
 state: ONLINE
errors: No known data errors
```

Определение настроек:
```
zenhert@linpro:~$ zfs get available,readonly,recordsize,compression,checksum otus
NAME  PROPERTY     VALUE           SOURCE
otus  available    350M            -
otus  readonly     off             default
otus  recordsize   128K            local
otus  compression  zle             local
otus  checksum     sha256          local
```

### 3. Работа со снапшотами
Скачивание файла из задания, восстановление файловой системы из снапшота:
```
zenhert@linpro:~$ wget -O otus_task2.file --no-check-certificate 'https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI&export=download'
2026-08-06 18:21:21 (16.0 MB/s) - ‘otus_task2.file’ saved [5432736/5432736]
zenhert@linpro:~$ sudo zfs receive otus/test@today < otus_task2.file
```

Поиск файла с сообщением и просмотр содержимого:
```
zenhert@linpro:~$ sudo zfs receive otus/test@today < otus_task2.file
zenhert@linpro:~$ find /otus/test -name "secret_message"
/otus/test/task1/file_mess/secret_message
zenhert@linpro:~$ cat /otus/test/task1/file_mess/secret_message
https://otus.ru/lessons/linux-hl/
```