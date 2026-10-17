# Отчёт по домашнему заданию по практике с бэкапами (08.10)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 17.10.2026
- **Задание:** 
  - Настроить стенд Vagrant с двумя виртуальными машинами:
    - backup-server и client.
  - Настроить удаленный бэкап каталога /etc с сервера client при помощи borgbackup. Резервные копии должны соответствовать следующим критериям:
    - Директория для резервных копий /var/backup. Это должна быть отдельная точка монтирования. В данном случае для демонстрации размер не принципиален, достаточно будет и 2GB;
    - Репозиторий для резервных копий должен быть зашифрован ключом или паролем - на усмотрение студента;
    - Имя бэкапа должно содержать информацию о времени снятия бекапа;
    - Глубина бекапа должна быть год, хранить можно по последней копии на конец месяца, кроме последних трех. Последние три месяца должны содержать копии на каждый день. Т.е. должна быть правильно настроена политика удаления старых бэкапов;
    - Резервная копия снимается каждые 5 минут. Такой частый запуск в целях демонстрации;
    - Написан скрипт для снятия резервных копий. Скрипт запускается из соответствующей Cron джобы, либо systemd timer-а - на усмотрение студента;
    - Настроено логирование процесса бекапа. Для упрощения можно весь вывод перенаправлять в logger с соответствующим тегом. Если настроите не в syslog, то обязательна ротация логов.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

## Схема сети
Client(192.168.60.11) -> Backup(192.168.60.10)
                    SSH:22

`/etc` (источник бэкап) -> `/var/backup/repo`(`/dev/sdb 2GB ext4`, репозиторий)

Соединение — SSH, ключ `/root/.ssh/id_borg` на client, авторизация через `authorized_keys` пользователя `borg` на backup, доступ ограничен `--restrict-to-path /var/backup`

## Особенности проектирования и реализации
- Отдельная точка монтирования `/var/backup`:
  - В `Vagrantfile` для `backup` создается дополнительный диск `/dev/sdb` размером 2 ГБ. Ansible форматирует его в `ext4` с меткой `borgbackup`, монтирует через `fstab` по метке, а не по имени устройства — это устойчивее к переименованию диска при перезапуске.
- Шифрование `repokey`:
  - Репозиторий инициализирован с `--encryption=repokey`. Ключ хранится в самом репозитории в зашифрованном виде, пароль — в файле `/root/.borg-passphrase` с правами `0600` на `client`. Такой вариант удобен для восстановления на другой машине: достаточно знать пароль и иметь доступ к репозиторию.
- SSH-ключ генерируется на контроллере:
  - При первом прогоне Ansible создаёт пару ключей в `ansible/keys/id_borg` через `delegate_to: localhost`. Приватный ключ копируется на `client`, публичный — в `authorized_keys` пользователя `borg` на `backup`. Это решает проблему порядка провижининга при использовании `ansible.limit = "all"` в Vagrant.
- Ограничение `borg serve`:
  - В `authorized_keys` используется `command="borg serve --restrict-to-path /var/backup",restrict`. Даже если ключ скомпрометируют, потенциальный злоумышленник не сможет выйти за пределы `/var/backup` — ни через `borg`, ни через shell.
- Репозиторий во вложенном каталоге `/var/backup/repo`:
  - После `mkfs.ext4` в `/var/backup` автоматически создаётся `lost+found`, а `borg init` отказывается работать в непустой директории. Вынос репозитория в подкаталог решает проблему, при этом `--restrict-to-path /var/backup` по-прежнему покрывает его.
- Systemd timer вместо cron:
  - Таймер `OnBootSec=2min`, `OnUnitActiveSec=5min` с `Persistent=true` — если система была выключена, пропущенные запуски выполнятся при старте. Логирование настроено через `logger -t borg-backup`, поэтому всё уходит в journald. Отдельная ротация логов не нужна — journald сам ротирует.
- Политика retention реализована через `borg prune --keep-daily 90 --keep-monthly 12 --keep-yearly 1`:
  - последние 90 дней — ежедневные копии (три месяца);
  - старше 3 месяцев — по одной копии на конец месяца;
  - глубина — 1 год.
- Компрессия `lz4`:
  - Быстрая и с разумной степенью сжатия, оптимальна для частого снятия бэкапов каждые 5 минут.

---

## Ход работы
Структура проекта:
borg-homework:
  - Vagrantfile
  - .gitignore
  - ansible:
    - playbook.yml
    - templates:
      - borg-backup.sh.j2
      - borg-backup.service.j2
      - borg-backup.timer.j2
  - README.md

### 1. Подготовка структуры и необходимых файлов
Создание директорий:
```
zenhert@linpro:~$ mkdir -p ~/borg-homework/ansible/templates
zenhert@linpro:~$ cd ~/borg-homework/
```

Подготовка `Vagrantfile`:
```
zenhert@linpro:~/borg-homework$ cat Vagrantfile

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu2404"

  config.vm.define "backup" do |backup|
    backup.vm.hostname = "backup"
    backup.vm.network "private_network", ip: "192.168.60.10"
    backup.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1

      disk = File.join(Dir.pwd, "backup_disk.vdi")
      unless File.exist?(disk)
        vb.customize ["createhd", "--filename", disk, "--size", 2048]
      end
      vb.customize ["storageattach", :id,
                    "--storagectl", "SATA Controller",
                    "--port", 1, "--device", 0,
                    "--type", "hdd", "--medium", disk]
    end
  end

  config.vm.define "client" do |client|
    client.vm.hostname = "client"
    client.vm.network "private_network", ip: "192.168.60.11"
    client.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
  end

  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "ansible/playbook.yml"
    ansible.groups = {
      "backup_servers" => ["backup"],
      "clients"        => ["client"]
    }
    ansible.limit = "all"
    ansible.verbose = "v"
  end
end
```

Создание Ansible-playbook:
```
zenhert@linpro:~/borg-homework$ nano ansible/playbook.yml
zenhert@linpro:~/borg-homework$ cat ansible/playbook.yml
---
# 1. Генерация SSH-ключа на контроллере (хосте)
# Ключ создаётся один раз и раздаётся обеим машинам.
- name: Generate borg SSH keypair on controller
  hosts: all
  gather_facts: false
  tasks:
    - name: Ensure local keys directory exists
      ansible.builtin.file:
        path: "{{ playbook_dir }}/keys"
        state: directory
        mode: '0700'
      delegate_to: localhost
      run_once: true

    - name: Generate ed25519 keypair
      ansible.builtin.command:
        cmd: ssh-keygen -t ed25519 -N '' -f {{ playbook_dir }}/keys/id_borg -C borg@client
        creates: "{{ playbook_dir }}/keys/id_borg"
      delegate_to: localhost
      run_once: true

# 2. Общие настройки
- name: Common configuration
  hosts: all
  become: true
  tasks:
    - name: Set timezone UTC
      ansible.builtin.command: timedatectl set-timezone UTC
      changed_when: false

    - name: Populate /etc/hosts
      ansible.builtin.lineinfile:
        path: /etc/hosts
        line: "{{ item }}"
        state: present
      loop:
        - "192.168.60.10 backup"
        - "192.168.60.11 client"

    - name: Install borgbackup
      ansible.builtin.apt:
        name: borgbackup
        state: present
        update_cache: true

# 3. Backup-сервер
- name: Configure backup server
  hosts: backup_servers
  become: true
  tasks:
    - name: Create borg user
      ansible.builtin.user:
        name: borg
        shell: /bin/bash
        create_home: true
        state: present

    - name: Check if /dev/sdb already has a filesystem
      ansible.builtin.command: blkid /dev/sdb
      register: sdb_blkid
      changed_when: false
      failed_when: false

    - name: Format backup disk as ext4 with label
      ansible.builtin.command:
        cmd: mkfs.ext4 -F -L borgbackup /dev/sdb
      when: sdb_blkid.rc != 0

    - name: Ensure /var/backup mount point exists
      ansible.builtin.file:
        path: /var/backup
        state: directory
        mode: '0755'

    - name: Add /var/backup to fstab
      ansible.builtin.lineinfile:
        path: /etc/fstab
        line: "LABEL=borgbackup /var/backup ext4 defaults 0 0"
        state: present

    - name: Check if /var/backup is mounted
      ansible.builtin.command: mountpoint -q /var/backup
      register: mount_check
      changed_when: false
      failed_when: false

    - name: Mount /var/backup
      ansible.builtin.command: mount /var/backup
      when: mount_check.rc != 0

    - name: Set ownership on /var/backup
      ansible.builtin.file:
        path: /var/backup
        owner: borg
        group: borg
        mode: '0700'

    - name: Ensure repository subdirectory exists
      ansible.builtin.file:
        path: /var/backup/repo
        state: directory
        owner: borg
        group: borg
        mode: '0700'

    - name: Ensure /home/borg/.ssh exists
      ansible.builtin.file:
        path: /home/borg/.ssh
        state: directory
        owner: borg
        group: borg
        mode: '0700'

    - name: Install client public key for borg (restricted to /var/backup)
      ansible.builtin.copy:
        content: "command=\"borg serve --restrict-to-path /var/backup\",restrict {{ lookup('file', playbook_dir + '/keys/id_borg.pub') }}\n"
        dest: /home/borg/.ssh/authorized_keys
        owner: borg
        group: borg
        mode: '0600'

# 4. Клиент — инициализация репозитория, скрипт, таймер
- name: Configure client backups
  hosts: clients
  become: true
  vars:
    borg_repo: "borg@192.168.60.10:/var/backup/repo/"
    borg_passphrase: "OtusBackupPassphrase2026!"
  tasks:
    - name: Ensure /root/.ssh exists
      ansible.builtin.file:
        path: /root/.ssh
        state: directory
        mode: '0700'

    - name: Install borg private key on client
      ansible.builtin.copy:
        src: "{{ playbook_dir }}/keys/id_borg"
        dest: /root/.ssh/id_borg
        owner: root
        group: root
        mode: '0600'

    - name: Store borg passphrase in root-only file
      ansible.builtin.copy:
        content: "{{ borg_passphrase }}\n"
        dest: /root/.borg-passphrase
        owner: root
        group: root
        mode: '0600'

    - name: Add backup host to known_hosts
      ansible.builtin.shell: |
        ssh-keyscan -H 192.168.60.10 >> /root/.ssh/known_hosts 2>/dev/null
      changed_when: false

    - name: Check if borg repo already initialized
      ansible.builtin.command:
        cmd: borg list {{ borg_repo }}
      environment:
        BORG_PASSPHRASE: "{{ borg_passphrase }}"
        BORG_RSH: "ssh -i /root/.ssh/id_borg -o StrictHostKeyChecking=accept-new"
      register: borg_check
      changed_when: false
      failed_when: false

    - name: Initialize borg repository
      ansible.builtin.command:
        cmd: borg init --encryption=repokey {{ borg_repo }}
      environment:
        BORG_PASSPHRASE: "{{ borg_passphrase }}"
        BORG_RSH: "ssh -i /root/.ssh/id_borg -o StrictHostKeyChecking=accept-new"
      when: borg_check.rc != 0

    - name: Deploy backup script
      ansible.builtin.template:
        src: templates/borg-backup.sh.j2
        dest: /usr/local/bin/borg-backup.sh
        mode: '0755'

    - name: Deploy systemd service
      ansible.builtin.template:
        src: templates/borg-backup.service.j2
        dest: /etc/systemd/system/borg-backup.service
        mode: '0644'
      notify: reload systemd

    - name: Deploy systemd timer
      ansible.builtin.template:
        src: templates/borg-backup.timer.j2
        dest: /etc/systemd/system/borg-backup.timer
        mode: '0644'
      notify: reload systemd

    - name: Enable and start timer
      ansible.builtin.systemd:
        name: borg-backup.timer
        enabled: true
        state: started
        daemon_reload: true

  handlers:
    - name: reload systemd
      ansible.builtin.systemd:
        daemon_reload: true
```

Создание шаблонов:
```
zenhert@linpro:~/borg-homework$ nano ansible/templates/borg-backup.sh.j2
zenhert@linpro:~/borg-homework$ cat ansible/templates/borg-backup.sh.j2
#!/bin/bash
set -euo pipefail

REPO="{{ borg_repo }}"
BACKUP_TARGET="/etc"
BACKUP_NAME="etc-$(date +%Y-%m-%d_%H:%M:%S)"

export BORG_PASSPHRASE="$(cat /root/.borg-passphrase)"
export BORG_RSH="ssh -i /root/.ssh/id_borg -o StrictHostKeyChecking=accept-new"

log() { logger -t borg-backup "$*"; }

log "START: creating ${BACKUP_NAME}"
if borg create --stats --compression lz4 "${REPO}::${BACKUP_NAME}" "${BACKUP_TARGET}" 2>&1 \
        | logger -t borg-backup; then
    log "CREATE OK: ${BACKUP_NAME}"
else
    log "CREATE FAILED: ${BACKUP_NAME}"
    exit 1
fi

log "CHECK: starting repository check"
if borg check "${REPO}" 2>&1 | logger -t borg-backup; then
    log "CHECK OK"
else
    log "CHECK FAILED"
fi

log "PRUNE: applying retention policy (daily=90, monthly=12, yearly=1)"
if borg prune --list \
        --keep-daily 90 \
        --keep-monthly 12 \
        --keep-yearly 1 \
        "${REPO}" 2>&1 | logger -t borg-backup; then
    log "PRUNE OK"
else
    log "PRUNE FAILED"
fi

log "DONE"
```

```
zenhert@linpro:~/borg-homework$ nano ansible/templates/borg-backup.service.j2
zenhert@linpro:~/borg-homework$ cat ansible/templates/borg-backup.service.j2
[Unit]
Description=Borg Backup of /etc to remote
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/borg-backup.sh
Nice=10
IOSchedulingClass=idle
```

```
zenhert@linpro:~/borg-homework$ nano ansible/templates/borg-backup.timer.j2
zenhert@linpro:~/borg-homework$ cat ansible/templates/borg-backup.timer.j2
[Unit]
Description=Run borg backup every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true
AccuracySec=10s

[Install]
WantedBy=timers.target
```

### 2. Запуск стенда и проверка
Развертывание стенда:
```
zenhert@linpro:~/borg-homework$ vagrant up
Bringing machine 'backup' up with 'virtualbox' provider...
Bringing machine 'client' up with 'virtualbox' provider...
backup                     : ok=16   changed=2    unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
client                     : ok=16   changed=9    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Проверка на `backup`:
```
zenhert@linpro:~/borg-homework$ vagrant ssh backup
vagrant@backup:~$ sudo -i
root@backup:~# lsblk
NAME                      MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0  64G  0 disk
├─sda1                      8:1    0   1M  0 part
├─sda2                      8:2    0   2G  0 part /boot
└─sda3                      8:3    0  62G  0 part
  └─ubuntu--vg-ubuntu--lv 252:0    0  31G  0 lvm  /
sdb                         8:16   0   2G  0 disk /var/backup
root@backup:~# df -h /var/backup
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        2.0G  1.3M  1.8G   1% /var/backup
root@backup:~# ll /var/backup/
total 28
drwx------  4 borg borg  4096 Oct 17 16:35 ./
drwxr-xr-x 14 root root  4096 Oct 17 16:35 ../
drwx------  2 root root 16384 Oct 17 16:35 lost+found/
drwx------  3 borg borg  4096 Oct 17 16:37 repo/
root@backup:~# getent passwd borg
borg:x:1001:1001::/home/borg:/bin/bash
```

Проверка на `client`:
```
zenhert@linpro:~/borg-homework$ vagrant ssh client
vagrant@client:~$ sudo -i
root@client:~# systemctl list-timers | grep borg
-                                  - Sat 2026-10-17 16:42:44 UTC     21ms ago borg-backup.timer            borg-backup.service
root@client:~# systemctl status borg-backup.timer --no-pager
● borg-backup.timer - Run borg backup every 5 minutes
     Loaded: loaded (/etc/systemd/system/borg-backup.timer; enabled; preset: enabled)
     Active: active (waiting) since Sat 2026-10-17 16:37:05 UTC; 6min ago
    Trigger: Sat 2026-10-17 16:47:44 UTC; 4min 33s left
   Triggers: ● borg-backup.service

Oct 17 16:37:05 client systemd[1]: Started borg-backup.timer - Run borg backup every 5 minutes.
root@client:~# ll /root/.ssh/id_borg*
-rw------- 1 root root 399 Oct 17 16:36 /root/.ssh/id_borg
```

Проверка логов первого запуска на `client`:
```
root@client:~# journalctl -t borg-backup -n 40 --no-pager
Oct 17 16:58:14 client borg-backup[3172]: START: creating etc-2026-10-17_16:58:14
Oct 17 16:58:16 client borg-backup[3174]: ------------------------------------------------------------------------------
Oct 17 16:58:16 client borg-backup[3174]: Repository: ssh://borg@192.168.60.10/var/backup/repo
Oct 17 16:58:16 client borg-backup[3174]: Archive name: etc-2026-10-17_16:58:14
Oct 17 16:58:16 client borg-backup[3174]: Archive fingerprint: f48a12f3f50c9ac8e5115dbc4097ae750a69464c0fda8602be30c09243853050
Oct 17 16:58:16 client borg-backup[3174]: Time (start): Sat, 2026-10-17 16:58:16
Oct 17 16:58:16 client borg-backup[3174]: Time (end):   Sat, 2026-10-17 16:58:16
Oct 17 16:58:16 client borg-backup[3174]: Duration: 0.18 seconds
Oct 17 16:58:16 client borg-backup[3174]: Number of files: 860
Oct 17 16:58:16 client borg-backup[3174]: Utilization of max. archive size: 0%
Oct 17 16:58:16 client borg-backup[3174]: ------------------------------------------------------------------------------
Oct 17 16:58:16 client borg-backup[3174]:                        Original size      Compressed size    Deduplicated size
Oct 17 16:58:16 client borg-backup[3174]: This archive:                2.33 MB              1.04 MB                637 B
Oct 17 16:58:16 client borg-backup[3174]: All archives:                7.00 MB              3.12 MB              1.08 MB
Oct 17 16:58:16 client borg-backup[3174]:
Oct 17 16:58:16 client borg-backup[3174]:                        Unique chunks         Total chunks
Oct 17 16:58:16 client borg-backup[3174]: Chunk index:                     817                 2550
Oct 17 16:58:16 client borg-backup[3174]: ------------------------------------------------------------------------------
Oct 17 16:58:16 client borg-backup[3177]: CREATE OK: etc-2026-10-17_16:58:14
Oct 17 16:58:16 client borg-backup[3178]: CHECK: starting repository check
Oct 17 16:58:18 client borg-backup[3183]: CHECK OK
Oct 17 16:58:18 client borg-backup[3184]: PRUNE: applying retention policy (daily=90, monthly=12, yearly=1)
Oct 17 16:58:19 client borg-backup[3186]: Keeping archive (rule: daily #1):        etc-2026-10-17_16:58:14              Sat, 2026-10-17 16:58:16 [f48a12f3f50c9ac8e5115dbc4097ae750a69464c0fda8602be30c09243853050]
Oct 17 16:58:19 client borg-backup[3186]: Pruning archive (1/1):                   etc-2026-10-17_16:53:04              Sat, 2026-10-17 16:53:06 [4458f1aae87546c6e8ebcde3b7ccee15d060bcd8e57b4f5bebdd4c7168040726]
Oct 17 16:58:19 client borg-backup[3186]: Keeping archive (rule: daily[oldest] #2): etc-2026-10-17_16:37:44              Sat, 2026-10-17 16:37:45 [230f7d0f61a1fecabb07f42390dbb7b1fffdb2aa2711889c5253a6b5713ad309]
Oct 17 16:58:19 client borg-backup[3189]: PRUNE OK
Oct 17 16:58:19 client borg-backup[3190]: DONE
```

Проверка списка архивов на `backup`
```
root@backup:~# sudo -u borg BORG_PASSPHRASE="OtusBackupPassphrase2026!" borg list /var/backup/repo/
etc-2026-10-17_16:37:44              Sat, 2026-10-17 16:37:45 [230f7d0f61a1fecabb07f42390dbb7b1fffdb2aa2711889c5253a6b5713ad309]
etc-2026-10-17_17:03:24              Sat, 2026-10-17 17:03:26 [2685438e456228b5050978359fcd872fef4b8b343cb635b584fc023be5e2ae22]
```

### 3. Восстановление из бэкапа
Просмотр актуальности списка архивов:
```
root@backup:~# sudo -u borg BORG_PASSPHRASE="OtusBackupPassphrase2026!" borg list /var/backup/repo/
etc-2026-10-17_16:37:44              Sat, 2026-10-17 16:37:45 [230f7d0f61a1fecabb07f42390dbb7b1fffdb2aa2711889c5253a6b5713ad309]
etc-2026-10-17_17:08:34              Sat, 2026-10-17 17:08:36 [4f5e7ae2eaaf841bf89fce6ff5085fe5c24682b45065ec003d964ad85a4c0488]
```

Восстановление из бэкапа:
```
root@backup:~# cd /tmp
root@backup:/tmp# sudo -u borg BORG_PASSPHRASE="OtusBackupPassphrase2026!"   borg extract /var/backup/repo/::etc-2026-10-17_17:13:35 etc/hostname
root@backup:/tmp# cat /tmp/etc/hostname
client
```
Вывод показал `client`, следовательно бэкап рабочий и данные извлекаются.
