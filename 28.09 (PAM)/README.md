# Отчёт по домашнему заданию по практике с PAM (28.09)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 05.10.2026
- **Задание:** 
  - Настроить PAM с условием, чтобы в выходные все пользователи, кроме группы `admin`, не могли логиниться.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы
Структура:
pam-homework:
  - Vagrantfile
  - ansible:
    - playbook.yml
    - files:
      - login.sh

### 1. Подготовка структуры и файлов
Создание директории:
```
zenhert@linpro:~$ mkdir -p ~/pam-homework/ansible/files
zenhert@linpro:~$ cd ~/pam-homework/
```

Подготовка Vagrantfile:
```
zenhert@linpro:~/pam-homework$ nano Vagrantfile
zenhert@linpro:~/pam-homework$ cat Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu2204"
  config.vm.hostname = "pam"
  config.vm.network "private_network", ip: "192.168.57.10"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 1024
    vb.cpus = 2
  end

# Разрешение входа по паролю (для проверки PAM)
  config.vm.provision "shell", inline: <<-SHELL
    sed -i 's/^PasswordAuthentication.*$/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication.*$/PasswordAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart sshd.service
  SHELL

# Провижининг через Ansible
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "ansible/playbook.yml"
    ansible.verbose = "v"
  end
end
```

Подготовка playbook:

```
zenhert@linpro:~/pam-homework$ cd ansible/
zenhert@linpro:~/pam-homework/ansible$ nano playbook.yml
zenhert@linpro:~/pam-homework/ansible$ cat playbook.yml
- name: Configure PAM restrictions (weekend login for admins only)
  hosts: all
  become: true

  tasks:
    - name: Create users
      ansible.builtin.user:
        name: "{{ item }}"
        state: present
      loop:
        - zenadm
        - zen

    - name: Set password for
      ansible.builtin.shell: "echo '{{ item }}:Pa$$w0rd' | chpasswd"
      loop:
        - zenadm
        - zen
      changed_when: true

    - name: Create admin group
      ansible.builtin.group:
        name: admin
        state: present

    - name: Add users to admin group
      ansible.builtin.user:
        name: "{{ item }}"
        groups: admin
        append: true
      loop:
        - zenadm
        - root
        - vagrant

    - name: Copy login.sh script
      ansible.builtin.copy:
        src: files/login.sh
        dest: /usr/local/bin/login.sh
        mode: '0755'
        owner: root
        group: root

    - name: Insert pam_exec rule into sshd PAM config
      ansible.builtin.lineinfile:
        path: /etc/pam.d/sshd
        insertafter: '^@include common-auth'
        line: 'auth required pam_exec.so debug /usr/local/bin/login.sh'
        state: present

    - name: Ensure pam_exec rule is not duplicated
      ansible.builtin.replace:
        path: /etc/pam.d/sshd
        regexp: '(auth required pam_exec\.so debug /usr/local/bin/login\.sh\n){2,}'
        replace: 'auth required pam_exec.so debug /usr/local/bin/login.sh\n'
```

Подготовка скрипта:
```
zenhert@linpro:~/pam-homework/ansible$ cd files/
zenhert@linpro:~/pam-homework/ansible/files$ nano login.sh
zenhert@linpro:~/pam-homework/ansible/files$ cat login.sh
#!/bin/bash
# Скрипт для PAM: запрет входа в выходные для всех, кроме группы admin

# Если день недели суббота или воскресенье
if [ "$(date +%a)" = "Sat" ] || [ "$(date +%a)" = "Sun" ]; then
    # Проверка, входит ли пользователь в группу admin
    if getent group admin | grep -qw "$PAM_USER"; then
        exit 0   # админ — пропуск
    else
        exit 1   # не админ — запрет
    fi
else
    exit 0       # будний день — пропуск всех
fi
```

### 2. Запуск стенда и проверка
Запуск стенда:
```
zenhert@linpro:~/pam-homework/ansible/files$ cd ~/pam-homework
zenhert@linpro:~/pam-homework$ vagrant up
zenhert@linpro:~/pam-homework$ vagrant status
Current machine states:

default                   running (virtualbox)

The VM is running. 
```

Vagrant развернул ВМ и прогнал Ansible-плейбук, теперь проверка:
```
zenhert@linpro:~/pam-homework$ vagrant ssh
Last login: Mon Oct  5 06:37:10 2026 from 10.0.2.2
vagrant@pam:~$ sudo -i
root@pam:~# cat /etc/group | grep admin
admin:x:1003:zenadm,root,vagrant
root@pam:~# ls -la /usr/local/bin/login.sh
-rwxr-xr-x 1 root root 611 Oct  5 06:37 /usr/local/bin/login.sh
root@pam:~# grep pam_exec /etc/pam.d/sshd
auth required pam_exec.so debug /usr/local/bin/login.sh
root@pam:~# exit
logout
vagrant@pam:~$ exit
logout
```

Проверка входа в будний день:
```
zenhert@linpro:~/pam-homework$ ssh zen@192.168.57.10
The authenticity of host '192.168.57.10 (192.168.57.10)' can't be established.
Warning: Permanently added '192.168.57.10' (ED25519) to the list of known hosts.
zen@192.168.57.10's password:
$ exit
Connection to 192.168.57.10 closed.
zenhert@linpro:~/pam-homework$ ssh zenadm@192.168.57.10
zenadm@192.168.57.10's password:
$ exit
Connection to 192.168.57.10 closed.
```

Перед проверкой входа в выходной день, нужно выключить синхронизацию времени и сменить дату вручную:
```
vagrant@pam:~$ sudo timedatectl set-ntp false
vagrant@pam:~$ sudo systemctl stop systemd-timesyncd.service
vagrant@pam:~$ sudo systemctl disable systemd-timesyncd.service
vagrant@pam:~$ sudo systemctl status systemd-timesyncd.service
○ systemd-timesyncd.service - Network Time Synchronization
     Loaded: loaded (/lib/systemd/system/systemd-timesyncd.service; disabled; vendor preset: enabled)
     Active: inactive (dead)
       Docs: man:systemd-timesyncd.service(8)
vagrant@pam:~$ sudo date -s "2026-10-10 12:00:00"
vagrant@pam:~$ date
Sat Oct 10 12:00:01 PM UTC 2026
```

Спустя некоторое время дата откатилась, причиной отката, несмотря на остановку службы синхронизации времени, оказалася запущенный процесс `VBoxService`, который синхронизирует время госте с хостом:
```
root@pam:~# sleep 15
root@pam:~# date
Mon Oct  5 08:08:59 AM UTC 2026
root@pam:~# ps aux | grep -i vbox
root         819  0.0  0.3 359872  2992 ?        Sl   06:34   0:01 /usr/sbin/VBoxService
root        4997  0.0  0.2   6612  2200 pts/1    S+   08:12   0:00 grep --color=auto -i vbox
root@pam:~# pkill -f VBoxService
root        5327  0.0  0.2   6480  2292 pts/1    S+   08:13   0:00 grep --color=auto -i vbox
root@pam:~# date -s "2026-10-10 12:00:00"
root@pam:~# date
Sat Oct 10 12:00:01 PM UTC 2026
root@pam:~# sleep 15
root@pam:~# date
Sat Oct 10 12:00:25 PM UTC 2026
```

Проверка входа в выходной день:
```
root@pam:~# PAM_USER=zen /usr/local/bin/login.sh; echo "zen exit: $?"
zen exit: 1
root@pam:~# PAM_USER=zenadm /usr/local/bin/login.sh; echo "zenadm exit: $?"
zenadm exit: 0
vagrant@pam:~$ ssh zen@192.168.57.10
zen@192.168.57.10's password:
zen@192.168.57.10: Permission denied (publickey,password).
vagrant@pam:~$ ssh zenadm@192.168.57.10
zenadm@192.168.57.10's password:
Last login: Mon Oct  5 07:08:19 2026 from 192.168.57.10
$ exit
Connection to 192.168.57.10 closed.
```

PAM настроен, в выходной день все, кроме членов группы `admin` не могут подключиться.

## Особенности проектирования и реализации
- Ограничение по дням недели реализовано через модуль PAM `pam_exec` и внешний скрипт `/usr/local/bin/login.sh`. Это связано с тем, что стандартный модуль `pam_time` не умеет работать с локальными группами пользователей — пришлось бы перечислять каждого пользователя вручную.
- Скрипт `login.sh` проверяет:
  1. День недели (суббота/воскресенье).
  2. Членство пользователя (`$PAM_USER`) в группе `admin`.
  Если сегодня выходной и пользователь не в `admin` — возвращается код 1 (отказ). В остальных случаях — код 0 (разрешение).
- Провижининг полностью выполнен через Ansible (`ansible/playbook.yml`), что позволяет воспроизвести конфигурацию с нуля одной командой `vagrant up`.
- Правило `pam_exec` вставляется в `/etc/pam.d/sshd` сразу после `@include common-auth`. Это важно: сначала должна пройти проверка пароля, и только потом — проверка дня недели.
- Для предотвращения дублирования строки в конфиге PAM добавлена задача с модулем `replace` — при повторном прогоне playbook строка не размножается.
