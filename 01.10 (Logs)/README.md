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
  config.vm.box = "generic/ubuntu2204"

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
        state: present
        update_cache: true

    - name: Configure nginx access_log to remote syslog
      ansible.builtin.replace:
        path: /etc/nginx/nginx.conf
        regexp: '^\s*access_log /var/log/nginx/access\.log;'
        replace: "\taccess_log syslog:server=192.168.59.11:514,tag=nginx_access;"
      notify: restart nginx

    - name: Configure nginx error_log (remote all + local crit)
      ansible.builtin.replace:
        path: /etc/nginx/nginx.conf
        regexp: '^\s*error_log /var/log/nginx/error\.log;'
        replace: "\terror_log syslog:server=192.168.59.11:514,tag=nginx_error info;\n\terror_log /var/log/nginx/error.log crit;"
      notify: restart nginx

    - name: Add syslog user to adm group (to read audit.log)
      ansible.builtin.user:
        name: syslog
        groups: adm
        append: true

    - name: Make auditd write logs readable by adm group
      ansible.builtin.lineinfile:
        path: /etc/audit/auditd.conf
        regexp: '^log_group ='
        line: 'log_group = adm'
      notify: restart auditd

    - name: Ensure /var/log/audit directory mode allows adm read
      ansible.builtin.file:
        path: /var/log/audit
        state: directory
        mode: '0750'
        owner: root
        group: adm

    - name: Deploy audit rule for nginx configs
      ansible.builtin.copy:
        src: files/nginx.rules
        dest: /etc/audit/rules.d/nginx.rules
        mode: '0640'
        owner: root
        group: root
      notify: reload audit rules

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

    - name: restart auditd
      ansible.builtin.service:
        name: auditd
        state: restarted

    - name: reload audit rules
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
    action(type="omfile" dynaFile="RemoteLogs")
    stop
}

# nginx error logs
if $programname == "nginx_error" then {
    action(type="omfile" dynaFile="RemoteLogs")
    stop
}

# audit logs (facility local6)
if $syslogfacility-text == "local6" then {
    action(type="omfile" file="/var/log/rsyslog/%HOSTNAME%/audit.log")
    stop
}

# Critical system logs from remote hosts
if $fromhost-ip != "127.0.0.1" and $syslogseverity <= 2 then {
    action(type="omfile" file="/var/log/rsyslog/%HOSTNAME%/syslog.log")
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
      startmsg.regex="^type=")

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
zenhert@linpro:~/rsyslog-homework/ansibl
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

Проверка на `web`:
```
zenhert@linpro:~/rsyslog-homework$ vagrant ssh web
Last login: Thu Oct  8 08:59:05 2026 from 10.0.2.2
vagrant@web:~$ sudo -i
root@web:~# nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
root@web:~# systemctl status nginx
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/lib/systemd/system/nginx.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2026-10-08 08:19:39 UTC; 5h 29min ago
```
Конфиг валиден, `nginx` запущен.

Генерация тестовых запросов и ошибок, проверка `audit` и логов:
```

```

















