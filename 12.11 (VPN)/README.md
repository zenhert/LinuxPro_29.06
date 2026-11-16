# Отчёт по домашнему заданию по практике с VPN (12.11)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 16.11.2026
- **Задание:** 
  - Настроить VPN между двумя ВМ в tun/tap режимах, замерить скорость в туннелях, сделать вывод от отличающихся показателях;
  - Поднять RAS на базе OpenVPN с клиентскими сертификатами, подключиться с локальной машины на ВМ.

---

## Исходное состояние

- VMWare ESXI 
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы
Структура проекта:
vpn-lab:
  - Vagrantfile
  - ansible.cfg
  - ansible:
    - hosts
    - provision.yml
    - templates:
      - tap-server.conf.j2
      - tap-client.conf.j2
      - tun-server.conf.j2
      - tun-client.conf.j2
      - ras-server.conf.j2
      - client.ovpn.j2
    - files
  - README.md

### 1. Подготовка структуры и необходимых файлов
Создание директорий:
```
zenhert@linpro:~$ mkdir -p ~/vpn-lab/ansible/templates ~/vpn-lab/ansible/files
zenhert@linpro:~$ cd ~/vpn-lab
```

Создание `Vagrantfile`:
```
zenhert@linpro:~/vpn-lab$ nano Vagrantfile
zenhert@linpro:~/vpn-lab$ cat Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu2404"

  config.vm.define "server" do |server|
    server.vm.hostname = "server.loc"
    server.vm.network "private_network", ip: "192.168.56.10"
    server.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
  end

  config.vm.define "client" do |client|
    client.vm.hostname = "client.loc"
    client.vm.network "private_network", ip: "192.168.56.20"
    client.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end

    client.vm.provision "ansible" do |ansible|
      ansible.playbook = "ansible/provision.yml"
      ansible.inventory_path = "ansible/hosts"
      ansible.host_key_checking = false
      ansible.limit = "all"
    end
  end
end
```

Создание `ansible.cfg`:
```
zenhert@linpro:~/vpn-lab$ nano ansible.cfg
zenhert@linpro:~/vpn-lab$ cat ansible.cfg
[defaults]
host_key_checking = false
inventory = ansible/hosts
command_warnings = false
```

Создание `ansible/hosts`:
```
zenhert@linpro:~/vpn-lab$ nano ansible/hosts
zenhert@linpro:~/vpn-lab$ cat ansible/hosts
[server]
server ansible_host=192.168.56.10 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/server/virtualbox/private_key

[client]
client ansible_host=192.168.56.20 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/client/virtualbox/private_key
```

Создание `ansible/provision.yml`:
``` 
zenhert@linpro:~/vpn-lab$ nano ansible/provision.yml
zenhert@linpro:~/vpn-lab$ cat ansible/provision.yml
---
- name: Common setup
  hosts: all
  become: yes
  tasks:
    - name: Install OpenVPN and iperf3
      apt:
        name:
          - openvpn
          - iperf3
        state: present
        update_cache: true

    - name: Disable ufw
      systemd:
        name: ufw
        state: stopped
        enabled: false

- name: Configure Static Key (TUN/TAP)
  hosts: server
  become: yes
  tasks:
    - name: Generate static key
      command: openvpn --genkey secret /etc/openvpn/static.key
      args:
        creates: /etc/openvpn/static.key

    - name: Fetch static key to host
      fetch:
        src: /etc/openvpn/static.key
        dest: ansible/files/static.key
        flat: yes

- name: Deploy static key to client
  hosts: client
  become: yes
  tasks:
    - name: Copy static key
      copy:
        src: ansible/files/static.key
        dest: /etc/openvpn/static.key
        mode: '0600'

- name: Deploy TUN/TAP configs
  hosts: all
  become: yes
  tasks:
    - name: Deploy tap config
      template:
        src: "templates/tap-{{ inventory_hostname }}.conf.j2"
        dest: /etc/openvpn/tap.conf
        mode: '0600'

    - name: Deploy tun config
      template:
        src: "templates/tun-{{ inventory_hostname }}.conf.j2"
        dest: /etc/openvpn/tun.conf
        mode: '0600'

- name: Setup RAS (OpenVPN Server with PKI)
  hosts: server
  become: yes
  tasks:
    - name: Install easy-rsa
      apt:
        name: easy-rsa
        state: present

    - name: Init PKI
      command: /usr/share/easy-rsa/easyrsa init-pki
      args:
        chdir: /etc/openvpn
        creates: /etc/openvpn/pki

    - name: Build CA (no pass)
      shell: echo 'rasvpn' | /usr/share/easy-rsa/easyrsa --batch build-ca nopass
      args:
        chdir: /etc/openvpn
        creates: /etc/openvpn/pki/ca.crt

    - name: Gen Server req
      shell: echo 'rasvpn' | /usr/share/easy-rsa/easyrsa --batch gen-req server nopass
      args:
        chdir: /etc/openvpn
        creates: /etc/openvpn/pki/private/server.key

    - name: Sign Server req
      shell: echo 'yes' | /usr/share/easy-rsa/easyrsa --batch sign-req server server
      args:
        chdir: /etc/openvpn
        creates: /etc/openvpn/pki/issued/server.crt

    - name: Gen DH
      shell: /usr/share/easy-rsa/easyrsa --batch gen-dh
      args:
        chdir: /etc/openvpn
        creates: /etc/openvpn/pki/dh.pem
      async: 300
      poll: 10

    - name: Gen Client req
      shell: echo 'client' | /usr/share/easy-rsa/easyrsa --batch gen-req client nopass
      args:
        chdir: /etc/openvpn
        creates: /etc/openvpn/pki/private/client.key

    - name: Sign Client req
      shell: echo 'yes' | /usr/share/easy-rsa/easyrsa --batch sign-req client client
      args:
        chdir: /etc/openvpn
        creates: /etc/openvpn/pki/issued/client.crt

    - name: Create client config dir
      file:
        path: /etc/openvpn/client
        state: directory
        mode: '0755'

    - name: Set iroute
      copy:
        content: "iroute 10.10.10.0 255.255.255.0\n"
        dest: /etc/openvpn/client/client

    - name: Deploy RAS server config
      template:
        src: templates/ras-server.conf.j2
        dest: /etc/openvpn/server.conf
        mode: '0600'

    - name: Fetch certs to host
      fetch:
        src: "/etc/openvpn/pki/{{ item }}"
        dest: "ansible/files/{{ item | basename }}"
        flat: yes
      loop:
        - ca.crt
        - issued/client.crt
        - private/client.key

- name: Create client.ovpn on host
  hosts: localhost
  connection: local
  tasks:
    - name: Render client.ovpn
      template:
        src: ansible/templates/client.ovpn.j2
        dest: ansible/files/client.ovpn
```

Создание шаблонов:
```
zenhert@linpro:~/vpn-lab$ nano ansible/templates/tap-server.conf.j2
zenhert@linpro:~/vpn-lab$ cat ansible/templates/tap-server.conf.j2
dev tap
ifconfig 10.10.10.1 255.255.255.0
topology subnet
secret /etc/openvpn/static.key
comp-lzo
status /var/log/openvpn-status.log
log /var/log/openvpn.log
verb 3
```
```
zenhert@linpro:~/vpn-lab$ nano ansible/templates/tap-client.conf.j2
zenhert@linpro:~/vpn-lab$ cat ansible/templates/tap-client.conf.j2
dev tap
remote 192.168.56.10
ifconfig 10.10.10.2 255.255.255.0
topology subnet
secret /etc/openvpn/static.key
comp-lzo
status /var/log/openvpn-status.log
log /var/log/openvpn.log
verb 3
```
```
zenhert@linpro:~/vpn-lab$ nano ansible/templates/tun-server.conf.j2
zenhert@linpro:~/vpn-lab$ cat ansible/templates/tun-server.conf.j2
dev tun
ifconfig 10.10.10.1 255.255.255.0
topology subnet
secret /etc/openvpn/static.key
comp-lzo
status /var/log/openvpn-status.log
log /var/log/openvpn.log
verb 3
```
```
zenhert@linpro:~/vpn-lab$ nano ansible/templates/tun-client.conf.j2
zenhert@linpro:~/vpn-lab$ cat ansible/templates/tun-client.conf.j2
dev tun
remote 192.168.56.10
ifconfig 10.10.10.2 255.255.255.0
topology subnet
route 192.168.56.0 255.255.255.0
secret /etc/openvpn/static.key
comp-lzo
status /var/log/openvpn-status.log
log /var/log/openvpn.log
verb 3
```
```
zenhert@linpro:~/vpn-lab$ nano ansible/templates/ras-server.conf.j2
zenhert@linpro:~/vpn-lab$ cat ansible/templates/ras-server.conf.j2
port 1207
proto udp
dev tun
ca /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/issued/server.crt
key /etc/openvpn/pki/private/server.key
dh /etc/openvpn/pki/dh.pem
server 10.10.10.0 255.255.255.0
ifconfig-pool-persist ipp.txt
client-to-client
client-config-dir /etc/openvpn/client
keepalive 10 120
comp-lzo
persist-key
persist-tun
status /var/log/openvpn-status.log
log /var/log/openvpn.log
verb 3
```
```
zenhert@linpro:~/vpn-lab$ nano ansible/templates/client.ovpn.j2
zenhert@linpro:~/vpn-lab$ cat ansible/templates/client.ovpn.j2
client
dev tun
proto udp
remote 192.168.56.10 1207
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
comp-lzo
verb 3
ca ca.crt
cert client.crt
key client.key
route 192.168.56.0 255.255.255.0
```

### 2. Запуск стенда и проверка
Запуск стенда:
```
zenhert@linpro:~/vpn-lab$ vagrant up
Bringing machine 'server' up with 'virtualbox' provider...
Bringing machine 'client' up with 'virtualbox' provider...
zenhert@linpro:~/vpn-lab$ vagrant status
Current machine states:
server                    running (virtualbox)
client                    running (virtualbox)
```

Запуск `TAP`:
```
zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "sudo systemctl start openvpn@tap"
zenhert@linpro:~/vpn-lab$ vagrant ssh client -c "sudo systemctl start openvpn@tap"
```

Замер скорости через `TAP`:
```

```
