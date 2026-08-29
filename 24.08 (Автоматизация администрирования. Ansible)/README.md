# Отчёт по домашнему заданию по практике с Ansible (28.08)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 29.08.2026
- **Задание:** 
  Подготовить стенд на Vagrant как минимум с одним сервером. На этом сервере, используя Ansible необходимо развернуть nginx со следующими условиями:
    - необходимо использовать модуль yum/apt;
    - конфигурационный файлы должны быть взяты из шаблона jinja2 с переменными;
    - после установки nginx должен быть в режиме enabled в systemd;
    - должен быть использован notify для старта nginx после установки;
    - сайт должен слушать на нестандартном порту - 8080, для этого использовать переменные в Ansible.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS 

---

## Ход работы

### 1. Подготовить стенд на Vagrant как минимум с одним сервером
Структура репозитория:
- ansible_nginx_lab/
  - Vagrantfile
  - ansible.cfg
  - staging/hosts
  - templates/nginx.conf.j2
  - nginx.yml

Создание новой директории и попытка развернуть стенд:
```
zenhert@linpro:~$ mkdir ansible_nginx_lab
zenhert@linpro:~/ansible_nginx_lab$ ls
Vagrantfile
zenhert@linpro:~/ansible_nginx_lab$ vagrant up
Bringing machine 'nginx' up with 'virtualbox' provider...
==> nginx: Box 'generic/ubuntu2204' could not be found. Attempting to find and install...
    nginx: Box Provider: virtualbox
    nginx: Box Version: >= 0
==> nginx: Loading metadata for box 'generic/ubuntu2204'
    nginx: URL: https://vagrantcloud.com/api/v2/vagrant/generic/ubuntu2204

The box 'generic/ubuntu2204' could not be found or could not be accessed in the remote catalog.
If this is a private box on the HashiCorp Vagrant Public Registry, please verify
you're logged in via `vagrant cloud auth login`. Also, please double-check the name.
The expanded URL and error message are shown below:

URL: https://vagrantcloud.com/api/v2/vagrant/generic/ubuntu2204
Error: Recv failure: Connection timed out
```
Vagrantfile был скачен из методички. Ввиду невозможности скачать бокс с сайта, бокс будет добавлен вручную:
https://portal.cloud.hashicorp.com/vagrant/discover/generic/ubuntu2204
```
zenhert@linpro:~/ansible_nginx_lab$ ls
ubuntu2204.box  Vagrantfile
zenhert@linpro:~/ansible_nginx_lab$ vagrant box add generic/ubuntu2204 ubuntu2204.box --provider virtualbox
==> box: Successfully added box 'generic/ubuntu2204' (v0) for 'virtualbox (amd64)'!
zenhert@linpro:~/ansible_nginx_lab$ vagrant box list
generic/ubuntu2204 (virtualbox, 0, (amd64))
zenhert@linpro:~/ansible_nginx_lab$ vagrant up
zenhert@linpro:~/ansible_nginx_lab$ vagrant status
Current machine states:
nginx                     running (virtualbox)
```

## Настройка Ansible
Проверка установки:
```
zenhert@linpro:~/ansible_nginx_lab$ ansible --version
ansible [core 2.16.3]
```

Создание структуры стенда:
```
zenhert@linpro:~/ansible_nginx_lab$ touch ansible.cfg
zenhert@linpro:~/ansible_nginx_lab$ mkdir staging
zenhert@linpro:~/ansible_nginx_lab$ cd staging
zenhert@linpro:~/ansible_nginx_lab/staging$ touch hosts
zenhert@linpro:~/ansible_nginx_lab$ mkdir templates
zenhert@linpro:~/ansible_nginx_lab$ cd templates/
zenhert@linpro:~/ansible_nginx_lab/templates$ touch nginx.conf.j2
zenhert@linpro:~/ansible_nginx_lab$ touch nginx.yml
```

Заполнение файла `ansible.cfg` и `hosts`:
```
zenhert@linpro:~/ansible_nginx_lab$ nano ansible.cfg
zenhert@linpro:~/ansible_nginx_lab$ cat ansible.cfg
[defaults]
inventory = staging/hosts
remote_user = vagrant
host_key_checking = False
retry_files_enabled = False
```
Перед записью `hosts` нужно проверить порт, т.к. Vagrant уже мог назначить порт 2222:
```
zenhert@linpro:~/ansible_nginx_lab$ vagrant ssh-config
Host nginx
  Port 2222
zenhert@linpro:~/ansible_nginx_lab$ nano staging/hosts
zenhert@linpro:~/ansible_nginx_lab$ cat staging/hosts
[web]
nginx ansible_host=127.0.0.1 ansible_port=2222 ansible_user=vagrant ansible_private_key_file=.vagrant/machines/nginx/virtualbox/private_key
```

Проверка доступности хоста:
```
zenhert@linpro:~/ansible_nginx_lab$ ansible nginx -m ping
nginx | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

Ad-Hoc команды (по методичке):
  - Необходимо выполнить команды без `playbook`, чтобы убедиться в управлении:
    - Проверка версии ядра;
    - Проверка статуса `firewalld`;
    - Проверка `uptime`.
```
zenhert@linpro:~/ansible_nginx_lab$ ansible nginx -m command -a "uname -r"
nginx | CHANGED | rc=0 >>
5.15.0-91-generic
zenhert@linpro:~/ansible_nginx_lab$ ansible nginx -m systemd -a "name=firewalld state=stopped"
nginx | FAILED! => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "msg": "Could not find the requested service firewalld: host"
}
zenhert@linpro:~/ansible_nginx_lab$ ansible nginx -m command -a "uptime"
nginx | CHANGED | rc=0 >>
 20:45:29 up  1:36,  1 user,  load average: 0.00, 0.00, 0.00
```
`firewalld` отсутствует - это нормально, т.к. в Ubuntu его обычно нет, следовательно команда показывает, что сервис не найден.

## Написание Playbook
Создание шаблона `nginx.conf.j2`
```
zenhert@linpro:~/ansible_nginx_lab$ nano templates/nginx.conf.j2
zenhert@linpro:~/ansible_nginx_lab$ cat templates/nginx.conf.j2
events {
    worker_connections 1024;
}

http {
    server {
        listen {{ nginx_listen_port }} default_server;
        server_name default_server;
        root /usr/share/nginx/html;

        location / {
        }
    }
}
```

Создание `playbook` `nginx.yml`:
```
zenhert@linpro:~/ansible_nginx_lab$ nano nginx.yml
zenhert@linpro:~/ansible_nginx_lab$ cat nginx.yml
---
- name: NGINX | Install and configure NGINX
  hosts: web
  become: true
  vars:
    nginx_listen_port: 8080

  tasks:
    - name: NGINX | Install nginx
      apt:
        name: nginx
        state: present
        update_cache: yes
      tags:
        - nginx-install

    - name: NGINX | Create NGINX config file from template
      template:
        src: templates/nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify:
        - restart nginx
      tags:
        - nginx-configuration

  handlers:
    - name: restart nginx
      systemd:
        name: nginx
        state: restarted
        enabled: yes
```

Запуск `playbook`:
```
zenhert@linpro:~/ansible_nginx_lab$ ansible-playbook nginx.yml
PLAY [NGINX | Install and configure NGINX] 
TASK [Gathering Facts] 
ok: [nginx]
TASK [NGINX | Install nginx] 
changed: [nginx]
TASK [NGINX | Create NGINX config file from template] 
changed: [nginx]
RUNNING HANDLER [restart nginx] 
changed: [nginx]
PLAY RECAP 
nginx                      : ok=4    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
Задача выполнилась без ошибок

Проверка порта, доступности через `curl`, включен ли `nginx`:
```
zenhert@linpro:~/ansible_nginx_lab$ ansible nginx -m shell -a "ss -tnlp | grep 8080"
nginx | CHANGED | rc=0 >>
LISTEN 0      511          0.0.0.0:8080      0.0.0.0:*
```
```
zenhert@linpro:~/ansible_nginx_lab$ ansible nginx -m shell -a "curl -s http://localhost:8080 | head -5"
nginx | CHANGED | rc=0 >>
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
```
```
zenhert@linpro:~/ansible_nginx_lab$ ansible nginx -m command -a "systemctl is-enabled nginx"
nginx | CHANGED | rc=0 >>
enabled
```
Был использован `curl` изнутри ВМ через `ansible`, в условиях internal-сети. Как вариант, можно добавить проброс порта в Vagrantfile.