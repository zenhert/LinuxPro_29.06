# Отчёт по домашнему заданию по практике с iptables (19.10)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 01.11.2026
- **Задание:** 
  - Реализовать knocking port:
    - centralRouter может попасть на ssh inetRouter через knock-скрипт.
  - Добавить inetRouter2, который виден с хоста или форвардится порт через локалхост;
  - Запустить nginx на centralServer;
  - Пробросить 80 порт на inetRouter2 8080;
  - Дефолт в инет оставить через inetRouter.

---

## Исходное состояние

- VMWare ESXI 
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы
Структура проекта:
iptables-lab:
  - Vagrantfile
  - ansible:
    - provision.yml
    - hosts
    - templates:
      - knock.sh.j2
      - iptables-inetRouter.sh.j2
      - iptables-inetRouter2.sh.j2
  - README.md

### 1. Подготовка структуры и необходимых файлов
Создание директорий:
```
zenhert@linpro:~$ mkdir -p ~/iptables-lab/ansible/templates
zenhert@linpro:~$ cd ~/iptables-lab
```

Создание `Vagrantfile`:
```
zenhert@linpro:~/iptables-lab$ nano Vagrantfile
zenhert@linpro:~/iptables-lab$ cat Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu2404"

  config.vm.define "inetRouter" do |r|
    r.vm.hostname = "inetRouter"
    r.vm.network "private_network", ip: "192.168.255.1", netmask: "255.255.255.252", virtualbox__intnet: "inet-central"
    r.vm.network "private_network", ip: "192.168.50.10", adapter: 3
    r.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end
  end

  config.vm.define "centralRouter" do |r|
    r.vm.hostname = "centralRouter"
    r.vm.network "private_network", ip: "192.168.255.2", netmask: "255.255.255.252", virtualbox__intnet: "inet-central"
    r.vm.network "private_network", ip: "192.168.255.5", netmask: "255.255.255.252", virtualbox__intnet: "central-inet2"
    r.vm.network "private_network", ip: "192.168.0.1", netmask: "255.255.255.240", virtualbox__intnet: "central-lan"
    r.vm.network "private_network", ip: "192.168.50.12", adapter: 5
    r.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end
  end

  config.vm.define "inetRouter2" do |r|
    r.vm.hostname = "inetRouter2"
    r.vm.network "private_network", ip: "192.168.255.6", netmask: "255.255.255.252", virtualbox__intnet: "central-inet2"
    r.vm.network "private_network", ip: "192.168.50.11", adapter: 3
    r.vm.network "forwarded_port", guest: 8080, host: 8080, host_ip: "127.0.0.1"
    r.vm.provider "virtualbox" do |vb|
      vb.memory = 512
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end
  end

  config.vm.define "centralServer" do |r|
    r.vm.hostname = "centralServer"
    r.vm.network "private_network", ip: "192.168.0.2", netmask: "255.255.255.240", virtualbox__intnet: "central-lan"
    r.vm.network "private_network", ip: "192.168.50.13", adapter: 3
    r.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end

    # Ansible запускается в самом конце, после создания всех ВМ
    r.vm.provision "ansible" do |ansible|
      ansible.playbook = "ansible/provision.yml"
      ansible.inventory_path = "ansible/hosts"
      ansible.host_key_checking = false
      ansible.limit = "all"
    end
  end
end
```

Создание `ansible/hosts`:
```
zenhert@linpro:~/iptables-lab$ nano ansible/hosts
zenhert@linpro:~/iptables-lab$ cat ansible/hosts
[routers]
inetRouter    ansible_host=192.168.50.10 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/inetRouter/virtualbox/private_key
centralRouter ansible_host=192.168.50.12 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/centralRouter/virtualbox/private_key
inetRouter2   ansible_host=192.168.50.11 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/inetRouter2/virtualbox/private_key

[servers]
centralServer ansible_host=192.168.50.13 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/centralServer/virtualbox/private_key

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

Создание `ansible/provision.yml`:
``` 
zenhert@linpro:~/iptables-lab$ nano ansible/provision.yml
zenhert@linpro:~/iptables-lab$ cat ansible/provision.yml
---
- name: Common setup
  hosts: all
  become: true
  tasks:
    - name: Disable ufw
      systemd:
        name: ufw
        state: stopped
        enabled: false

    - name: Install required packages
      apt:
        name:
          - iptables
          - nginx
          - netcat-openbsd
        state: present
        update_cache: true

- name: Enable forwarding and disable rp_filter on routers
  hosts: [inetRouter, centralRouter, inetRouter2]
  become: true
  tasks:
    - name: Enable IP forwarding
      ansible.posix.sysctl:
        name: net.ipv4.ip_forward
        value: '1'
        state: present
        sysctl_set: true
        reload: true

    - name: Disable strict rp_filter (Required for asymmetric routing)
      ansible.posix.sysctl:
        name: "{{ item }}"
        value: '0'
        state: present
        sysctl_set: true
        reload: true
      loop:
        - net.ipv4.conf.all.rp_filter
        - net.ipv4.conf.default.rp_filter

- name: Configure routing (Netplan overrides)
  hosts: [centralRouter, centralServer, inetRouter2]
  become: true
  tasks:
    - name: Override Netplan for centralServer
      copy:
        content: |
          network:
            version: 2
            ethernets:
              eth0:
                dhcp4: true
                dhcp4-overrides:
                  use-routes: false
              eth1:
                routes:
                  - to: default
                    via: 192.168.0.1
        dest: /etc/netplan/99-otus-override.yaml
        mode: '0600'
      when: inventory_hostname == "centralServer"
      notify: apply netplan

    - name: Override Netplan for centralRouter
      copy:
        content: |
          network:
            version: 2
            ethernets:
              eth0:
                dhcp4: true
                dhcp4-overrides:
                  use-routes: false
              eth1:
                routes:
                  - to: default
                    via: 192.168.255.1
              eth2:
                routes:
                  - to: 10.0.2.0/24
                    via: 192.168.255.6
        dest: /etc/netplan/99-otus-override.yaml
        mode: '0600'
      when: inventory_hostname == "centralRouter"
      notify: apply netplan

    - name: Override Netplan for inetRouter2
      copy:
        content: |
          network:
            version: 2
            ethernets:
              eth0:
                dhcp4: true
              eth1:
                routes:
                  - to: 192.168.0.0/28
                    via: 192.168.255.5
        dest: /etc/netplan/99-otus-override.yaml
        mode: '0600'
      when: inventory_hostname == "inetRouter2"
      notify: apply netplan

  handlers:
    - name: apply netplan
      command: netplan apply

- name: Configure inetRouter (NAT + Port Knocking)
  hosts: inetRouter
  become: true
  tasks:
    - name: Deploy iptables script
      template:
        src: templates/iptables-inetRouter.sh.j2
        dest: /usr/local/bin/iptables-inetRouter.sh
        mode: '0755'

    - name: Apply iptables script
      shell: /usr/local/bin/iptables-inetRouter.sh

- name: Configure inetRouter2 (Port Forwarding)
  hosts: inetRouter2
  become: true
  tasks:
    - name: Deploy iptables script
      template:
        src: templates/iptables-inetRouter2.sh.j2
        dest: /usr/local/bin/iptables-inetRouter2.sh
        mode: '0755'

    - name: Apply iptables script
      shell: /usr/local/bin/iptables-inetRouter2.sh

- name: Configure centralRouter (Knock script)
  hosts: centralRouter
  become: true
  tasks:
    - name: Deploy knock script
      template:
        src: templates/knock.sh.j2
        dest: /usr/local/bin/knock.sh
        mode: '0755'

- name: Configure centralServer (Nginx)
  hosts: centralServer
  become: true
  tasks:
    - name: Ensure nginx is running
      systemd:
        name: nginx
        state: started
        enabled: true
```

Создание шаблонов:
```
zenhert@linpro:~/iptables-lab$ nano ansible/templates/iptables-inetRouter.sh.j2
zenhert@linpro:~/iptables-lab$ cat ansible/templates/iptables-inetRouter.sh.j2
#!/bin/bash
# Очистка
iptables -F
iptables -t nat -F

# Разрешаем loopback и established
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Port Knocking (1111 -> 2222 -> 3333)
iptables -A INPUT -p tcp --dport 1111 -m recent --name KNOCK1 --set -j DROP
iptables -A INPUT -p tcp --dport 2222 -m recent --name KNOCK1 --rcheck --seconds 10 -m recent --name KNOCK2 --set -j DROP
iptables -A INPUT -p tcp --dport 3333 -m recent --name KNOCK2 --rcheck --seconds 10 -m recent --name KNOCK3 --set -j DROP

# Разрешаем SSH только после стука
iptables -A INPUT -p tcp --dport 22 -m recent --name KNOCK3 --rcheck --seconds 10 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP

# NAT (MASQUERADE) для выхода в интернет
iptables -t nat -A POSTROUTING ! -d 192.168.0.0/16 -o eth0 -j MASQUERADE
```
```
zenhert@linpro:~/iptables-lab$ nano ansible/templates/iptables-inetRouter2.sh.j2
zenhert@linpro:~/iptables-lab$ cat ansible/templates/iptables-inetRouter2.sh.j2
#!/bin/bash
# Очистка
iptables -F
iptables -t nat -F

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# DNAT (Проброс 8080 на centralServer:80)
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 192.168.0.2:80

# SNAT (ОБЯЗАТЕЛЬНО для VirtualBox, иначе curl на 127.0.0.1 будет висеть)
iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -d 192.168.0.2 -p tcp --dport 80 -j SNAT --to-source 192.168.255.6

# Разрешаем форвардинг
iptables -A FORWARD -p tcp -d 192.168.0.2 --dport 80 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
```
```
zenhert@linpro:~/iptables-lab$ nano ansible/templates/knock.sh.j2
zenhert@linpro:~/iptables-lab$ cat ansible/templates/knock.sh.j2
#!/bin/bash
TARGET="192.168.255.1"
PORTS="1111 2222 3333"

echo "Стучим в $TARGET..."
for port in $PORTS; do
    nc -z -w 1 $TARGET $port
    sleep 0.5
done

echo "Стук завершен. Пробуем SSH..."
ssh -o StrictHostKeyChecking=no vagrant@$TARGET
```

### 2. Запуск стенда и проверка
Запуск стенда:
```
zenhert@linpro:~/iptables-lab$ vagrant up
Bringing machine 'inetRouter' up with 'virtualbox' provider...
Bringing machine 'centralRouter' up with 'virtualbox' provider...
Bringing machine 'inetRouter2' up with 'virtualbox' provider...
Bringing machine 'centralServer' up with 'virtualbox' provider...
zenhert@linpro:~/iptables-lab$ vagrant status
Current machine states:

inetRouter                running (virtualbox)
centralRouter             running (virtualbox)
inetRouter2               running (virtualbox)
centralServer             running (virtualbox)
```

Проверка `Port Knocking`:
```
zenhert@linpro:~/iptables-lab$ vagrant ssh centralRouter
vagrant@centralRouter:~$ sudo -i
root@centralRouter:~# ssh -o ConnectTimeout=3 vagrant@192.168.255.1
ssh: connect to host 192.168.255.1 port 22: Connection timed out
root@centralRouter:~# /usr/local/bin/knock.sh
Начинаем стучать в 192.168.255.1...
Стук завершен. Пробуем SSH...
vagrant@192.168.255.1's password:
Last login: Sun Nov  1 09:35:54 2026 from 192.168.50.1
```
ЗЫ: после запуска скрипта SSH-соединение установилось - Port Knocking работает

Проверка проброса 8080 на `centralServer`:
```
zenhert@linpro:~/iptables-lab$ curl -I --max-time 5 http://127.0.0.1:8080
HTTP/1.1 200 OK
```
ЗЫ: проброс порта успешно выполнен