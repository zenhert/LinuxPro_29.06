# Отчёт по домашнему заданию по практике с логами (01.10)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 06.10.2026
- **Задание:** 
  - Поднять две машины — web и log:
    - На web поднимаем nginx;
    - Настраиваем центральный лог-сервер на любой системе по выбору:
      - journald;
      - rsyslog;
      - elk.
  - Настраиваем аудит, который будет отслеживать изменения конфигураций nginx;
  - Все критичные логи с web должны собираться и локально и удаленно;
  - Все логи с nginx должны уходить на удаленный сервер (локально только критичные);
  - Логи аудита должны также уходить на удаленную систему.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы
Структура проекта:
rsyslog-homework:
  - Vagrantfile
  - ansible:
    - playbook.yml
    - files:
      - nginx.rules
    - templates:
      - rsyslog-server.conf.j2
      - rsyslog-client.conf.j2
  - README.md

### 1. Подготовка структуры и необходимых файлов
Создание директорий:
```
zenhert@linpro:~$ mkdir -p ~/rsyslog-homework/ansible/{files,templates}
zenhert@linpro:~$ cd ~/rsyslog-homework/
```

Создание Vagrantfile:
```
zenhert@linpro:~/rsyslog-homework$ nano Vagrantfile
zenhert@linpro:~/rsyslog-homework$ cat Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu2404"

  config.vm.define "web" do |web|
    web.vm.hostname = "web"
    web.vm.network "private_network", ip: "192.168.59.10"
    web.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
  end

  config.vm.define "log" do |log|
    log.vm.hostname = "log"
    log.vm.network "private_network", ip: "192.168.59.11"
    log.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
  end

  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "ansible/playbook.yml"
    ansible.groups = {
      "logservers" => ["log"],
      "webservers" => ["web"]
    }
    ansible.verbose = "v"
  end
end
```

Создание Ansible-playbook:
```
zenhert@linpro:~/rsyslog-homework$ cd ansible/
zenhert@linpro:~/rsyslog-homework/ansible$ nano playbook.yml
zenhert@linpro:~/rsyslog-homework/ansible$ cat playbook.yml
---
- name: Common configuration for all hosts
  hosts: all
  become: true
  tasks:
    - name: Set timezone to UTC
      community.general.timezone:
        name: UTC

    - name: Add cluster hosts to /etc/hosts
      ansible.builtin.lineinfile:
        path: /etc/hosts
        line: "{{ item }}"
        state: present
      loop:
        - "192.168.59.10 web"
        - "192.168.59.11 log"

    - name: Install rsyslog
      ansible.builtin.apt:
        name: rsyslog
        state: present
        update_cache: true


- name: Configure central log server
  hosts: logservers
  become: true
  tasks:
    - name: Ensure /var/log/rsyslog exists
      ansible.builtin.file:
        path: /var/log/rsyslog
        state: directory
        mode: '0755'

    - name: Deploy rsyslog server config
      ansible.builtin.template:
        src: templates/rsyslog-server.conf.j2
        dest: /etc/rsyslog.d/10-remote.conf
        mode: '0644'
      notify: restart rsyslog

  handlers:
    - name: restart rsyslog
      ansible.builtin.service:
        name: rsyslog
        state: restarted


- name: Configure web server
  hosts: webservers
  become: true
  tasks:
    - name: Install nginx and auditd
      ansible.builtin.apt:
        name:
          - nginx
          - auditd
          - audispd-plugins
        state: present
        update_cache: true

    - name: Show current nginx log settings (для отладки)
      ansible.builtin.command: grep -E "access_log|error_log" /etc/nginx/nginx.conf
      register: nginx_logs
      changed_when: false

    - name: Print current nginx log settings
      ansible.builtin.debug:
        var: nginx_logs.stdout_lines

    - name: Configure nginx access_log to remote syslog
      ansible.builtin.replace:
        path: /etc/nginx/nginx.conf
        regexp: '^\s*access_log\s+/var/log/nginx/access\.log.*;'
        replace: "\taccess_log syslog:server=192.168.59.11:514,tag=nginx_access;"
      notify: restart nginx

    - name: Configure nginx error_log (remote all + local crit)
      ansible.builtin.replace:
        path: /etc/nginx/nginx.conf
        regexp: '^\s*error_log\s+/var/log/nginx/error\.log.*;'
        replace: "\terror_log syslog:server=192.168.59.11:514,tag=nginx_error info;\n\terror_log /var/log/nginx/error.log crit;"
      notify: restart nginx

    - name: Add syslog user to adm group (to read audit.log)
      ansible.builtin.user:
        name: syslog
        groups: adm
        append: true

    - name: Deploy audit rule for nginx configs
      ansible.builtin.copy:
        src: files/nginx.rules
        dest: /etc/audit/rules.d/nginx.rules
        mode: '0640'
        owner: root
        group: root
      notify: load audit rules

    - name: Deploy rsyslog client config
      ansible.builtin.template:
        src: templates/rsyslog-client.conf.j2
        dest: /etc/rsyslog.d/10-forward.conf
        mode: '0644'
      notify: restart rsyslog

  handlers:
    - name: restart nginx
      ansible.builtin.service:
        name: nginx
        state: restarted

    - name: restart rsyslog
      ansible.builtin.service:
        name: rsyslog
        state: restarted

    - name: load audit rules
      ansible.builtin.command: augenrules --load
      changed_when: true
```

Создание шаблона сервера:
```
zenhert@linpro:~/rsyslog-homework/ansible$ cd templates/
zenhert@linpro:~/rsyslog-homework/ansible/templates$ nano rsyslog-server.conf.j2
zenhert@linpro:~/rsyslog-homework/ansible/templates$ cat rsyslog-server.conf.j2
# Load TCP/UDP input modules
module(load="imtcp")
input(type="imtcp" port="514")
module(load="imudp")
input(type="imudp" port="514")

# Template for dynamic log paths
template(name="RemoteLogs" type="string"
         string="/var/log/rsyslog/%HOSTNAME%/%PROGRAMNAME%.log")

# nginx access logs
if $programname == "nginx_access" then {
    action(type="omfile" dynaFile="RemoteLogs" createDirs="on")
    stop
}

# nginx error logs
if $programname == "nginx_error" then {
    action(type="omfile" dynaFile="RemoteLogs" createDirs="on")
    stop
}

# audit logs (facility local6)
if $syslogfacility-text == "local6" then {
    action(type="omfile" file="/var/log/rsyslog/%HOSTNAME%/audit.log" createDirs="on")
    stop
}

# Critical system logs from remote hosts
if $fromhost-ip != "127.0.0.1" and $syslogseverity <= 2 then {
    action(type="omfile" file="/var/log/rsyslog/%HOSTNAME%/syslog.log" createDirs="on")
    stop
}
```

Создание шаблона клиента:
```
zenhert@linpro:~/rsyslog-homework/ansible/templates$ nano rsyslog-client.conf.j2
zenhert@linpro:~/rsyslog-homework/ansible/templates$ cat rsyslog-client.conf.j2
# Load imfile to read the audit log
module(load="imfile")

# Read audit log and tag it
input(type="imfile"
      File="/var/log/audit/audit.log"
      Tag="audit"
      Facility="local6"
      Severity="info"
      PersistStateInterval="1"
      readMode="2")

# Forward audit logs to remote server
local6.* @@192.168.59.11:514

# Forward critical system logs to remote server
*.crit @@192.168.59.11:514
```

Правило `audit`:
```
zenhert@linpro:~/rsyslog-homework/ansible/templates$ cd ../files/
zenhert@linpro:~/rsyslog-homework/ansible/files$ nano nginx.rules
zenhert@linpro:~/rsyslog-homework/ansible/files$ cat nginx.rules
-w /etc/nginx/ -p wa -k nginx_config
```

### 2. Запуск стенда и проверка
Запуск стенда:
```
zenhert@linpro:~/rsyslog-homework/ansible/files$ cd ~/rsyslog-homework
zenhert@linpro:~/rsyslog-homework$ vagrant up
Bringing machine 'web' up with 'virtualbox' provider...
Bringing machine 'log' up with 'virtualbox' provider...
zenhert@linpro:~/rsyslog-homework$ vagrant status
Current machine states:

web                       running (virtualbox)
log                       running (virtualbox)
```

Проверка на `web`(запущен ли nginx, валиден ли конфиг, текущие настройки логирования, проверка rsyslog):
```
zenhert@linpro:~/rsyslog-homework$ vagrant ssh web
Last login: Mon Oct 12 13:02:41 2026 from 10.0.2.2
vagrant@web:~$ sudo -i
root@web:~# nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
root@web:~# systemctl status nginx --no-pager
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-10-12 13:03:49 UTC; 4min 47s ago
root@web:~# grep -E "access_log|error_log" /etc/nginx/nginx.conf
        error_log syslog:server=192.168.59.11:514,tag=nginx_error info;
        error_log /var/log/nginx/error.log crit;
        access_log syslog:server=192.168.59.11:514,tag=nginx_access;
root@web:~# systemctl status rsyslog --no-pager
● rsyslog.service - System Logging Service
     Loaded: loaded (/usr/lib/systemd/system/rsyslog.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-10-12 13:03:47 UTC; 9min ago
```

Генерация событий на `web`(генерация запросов, ошибка 403, изменение конфига, проверка аудита):
```
root@web:~# for i in {1..5}; do curl -s http://localhost/ > /dev/null; done
root@web:~# mv /var/www/html/index.nginx-debian.html /tmp/
root@web:~# curl -s -o /dev/null -w "HTTP код: %{http_code}\n" http://localhost/
HTTP код: 403
root@web:~# mv /tmp/index.nginx-debian.html /var/www/html/
root@web:~# echo "# audit test $(date)" >> /etc/nginx/nginx.conf
root@web:~# ausearch -k nginx_config --start recent | tail -10
type=PATH msg=audit(1791811523.467:344): item=0 name="/etc/nginx/" inode=525841 dev=fc:00 mode=040755 ouid=0 ogid=0 rdev=00:00 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1791811523.467:344): cwd="/root"
type=SYSCALL msg=audit(1791811523.467:344): arch=c000003e syscall=257 success=yes exit=3 a0=ffffff9c a1=5a794e0107d0 a2=441 a3=1b6 items=2 ppid=1718 pid=1719 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts1 ses=4 comm="bash" exe="/usr/bin/bash" subj=unconfined key="nginx_config"
----
time->Mon Oct 12 13:30:56 2026
type=PROCTITLE msg=audit(1791811856.720:347): proctitle="-bash"
type=PATH msg=audit(1791811856.720:347): item=1 name="/etc/nginx/nginx.conf" inode=655378 dev=fc:00 mode=0100644 ouid=0 ogid=0 rdev=00:00 nametype=NORMAL cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(1791811856.720:347): item=0 name="/etc/nginx/" inode=525841 dev=fc:00 mode=040755 ouid=0 ogid=0 rdev=00:00 nametype=PARENT cap_fp=0 cap_fi=0 cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(1791811856.720:347): cwd="/root"
type=SYSCALL msg=audit(1791811856.720:347): arch=c000003e syscall=257 success=yes exit=3 a0=ffffff9c a1=5a794e010860 a2=441 a3=1b6 items=2 ppid=1718 pid=1719 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts1 ses=4 comm="bash" exe="/usr/bin/bash" subj=unconfined key="nginx_config"
```

Проверка на `log`(проверка 514 порта, какие файлы создались, логи nginx, audit-логи, критичные системные логи):
```

```
























