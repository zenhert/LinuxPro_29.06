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

    - name: Deploy RAS server config
      template:
        src: templates/ras-server.conf.j2
        dest: /etc/openvpn/server.conf
        mode: '0600'

    - name: Fetch certs to host
      fetch:
        src: "/etc/openvpn/pki/{{ item }}"
        dest: "{{ playbook_dir }}/files/{{ item | basename }}"
        flat: yes
      loop:
        - ca.crt
        - issued/client.crt
        - private/client.key

- name: Create client.ovpn on host
  hosts: server
  tasks:
    - name: Render client.ovpn locally
      template:
        src: "{{ playbook_dir }}/templates/client.ovpn.j2"
        dest: "{{ playbook_dir }}/files/client.ovpn"
      delegate_to: localhost
      become: false
```

Создание шаблонов:
```
zenhert@linpro:~/vpn-lab$ nano ansible/templates/tap-server.conf.j2
zenhert@linpro:~/vpn-lab$ cat ansible/templates/tap-server.conf.j2
dev tap
ifconfig 10.10.10.1 255.255.255.0
topology subnet
secret /etc/openvpn/static.key
data-ciphers AES-256-CBC
data-ciphers-fallback AES-256-CBC
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
data-ciphers AES-256-CBC
data-ciphers-fallback AES-256-CBC
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
data-ciphers AES-256-CBC
data-ciphers-fallback AES-256-CBC
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
data-ciphers AES-256-CBC
data-ciphers-fallback AES-256-CBC
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
topology subnet
ca /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/issued/server.crt
key /etc/openvpn/pki/private/server.key
dh /etc/openvpn/pki/dh.pem
server 10.10.10.0 255.255.255.0
ifconfig-pool-persist ipp.txt
client-to-client
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
zenhert@linpro:~/vpn-lab$ vagrant ssh client -c "ip a show tap0; ping -c 3 10.10.10.1"
--- 10.10.10.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2001ms
```
ЗЫ: пинг пошел, туннель работает.

Замер скорости через `TAP`:
```
zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "sudo systemctl reset-failed iperf3 2>/dev/null || true; sudo pkill iperf3 || true; sudo iperf3 -s -D"
zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "ss -tlnp | grep 5201"
LISTEN 0      4096               *:5201
zenhert@linpro:~/vpn-lab$ vagrant ssh client -c "iperf3 -c 10.10.10.1 -t 10"
Connecting to host 10.10.10.1, port 5201
[  5] local 10.10.10.2 port 41638 connected to 10.10.10.1 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  5.25 MBytes  44.0 Mbits/sec    0    267 KBytes
[  5]   1.00-2.00   sec  5.50 MBytes  46.1 Mbits/sec    0    504 KBytes
[  5]   2.00-3.00   sec  5.12 MBytes  43.0 Mbits/sec    0    742 KBytes
[  5]   3.00-4.00   sec  4.88 MBytes  40.8 Mbits/sec    0    975 KBytes
[  5]   4.00-5.00   sec  5.00 MBytes  41.9 Mbits/sec    0   1.18 MBytes
[  5]   5.00-6.00   sec  5.50 MBytes  46.2 Mbits/sec   47    932 KBytes
[  5]   6.00-7.00   sec  4.12 MBytes  34.6 Mbits/sec    0   1.01 MBytes
[  5]   7.00-8.00   sec  5.50 MBytes  46.1 Mbits/sec    0   1.10 MBytes
[  5]   8.00-9.00   sec  4.00 MBytes  33.6 Mbits/sec    0   1.17 MBytes
[  5]   9.00-10.00  sec  5.38 MBytes  45.0 Mbits/sec    0   1.22 MBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  50.2 MBytes  42.1 Mbits/sec   47             sender
[  5]   0.00-10.26  sec  47.8 MBytes  39.0 Mbits/sec                  receiver

iperf Done.
```

Остановка `iperf`:
```
zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "sudo systemctl stop iperf3"
```

Запуск `TUN`:
```
zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "sudo systemctl stop openvpn@tap"
zenhert@linpro:~/vpn-lab$ vagrant ssh client -c "sudo systemctl stop openvpn@tap"
zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "sudo systemctl start openvpn@tun"
zenhert@linpro:~/vpn-lab$ vagrant ssh client -c "sudo systemctl start openvpn@tun"
zenhert@linpro:~/vpn-lab$ vagrant ssh client -c "ip a show tun0; ping -c 3 10.10.10.1"
--- 10.10.10.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
```
ЗЫ: перед запуском `TUN` нужно остановить `TAP`. 
ЗЫЫ: пинг пошел, туннель работает.

Замер скорости через `TUN`:
```

zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "sudo systemctl reset-failed iperf3 2>/dev/null || true; sudo pkill iperf3 || true; sudo iperf3 -s -D"
zenhert@linpro:~/vpn-lab$ vagrant ssh server -c "ss -tlnp | grep 5201"
LISTEN 0      4096               *:5201            *:*
zenhert@linpro:~/vpn-lab$ vagrant ssh client -c "iperf3 -c 10.10.10.1 -t 10"
Connecting to host 10.10.10.1, port 5201
[  5] local 10.10.10.2 port 54602 connected to 10.10.10.1 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  5.38 MBytes  45.1 Mbits/sec    0    263 KBytes
[  5]   1.00-2.00   sec  5.38 MBytes  45.1 Mbits/sec    0    515 KBytes
[  5]   2.00-3.00   sec  4.88 MBytes  40.9 Mbits/sec   36    482 KBytes
[  5]   3.00-4.00   sec  5.62 MBytes  47.2 Mbits/sec    0    552 KBytes
[  5]   4.00-5.00   sec  4.75 MBytes  39.9 Mbits/sec    0    605 KBytes
[  5]   5.00-6.00   sec  4.88 MBytes  40.9 Mbits/sec    0    644 KBytes
[  5]   6.00-7.00   sec  4.50 MBytes  37.7 Mbits/sec    5    478 KBytes
[  5]   7.00-8.00   sec  4.75 MBytes  39.9 Mbits/sec    0    513 KBytes
[  5]   8.00-9.00   sec  4.88 MBytes  40.9 Mbits/sec    0    535 KBytes
[  5]   9.00-10.01  sec  5.62 MBytes  46.9 Mbits/sec    0    547 KBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.01  sec  50.6 MBytes  42.4 Mbits/sec   41             sender
[  5]   0.00-10.11  sec  49.0 MBytes  40.7 Mbits/sec                  receiver

iperf Done.
```
ЗЫ: перед запуском `iperf` необходимо сбросить старый юнит, иначе старый процесс остается в памяти и может конфликтовать. 
ЗЫЫ: переключение TAP <-> TUN - Оба конфига лежат в `/etc/openvpn/` одновременно. Переключение — `systemctl stop openvpn@tap && systemctl start openvpn@tun`. Перед запуском нового режима обязательно останавливать старый, иначе оба пытаются занять один и тот же туннельный интерфейс.

Сравнение `TAP` и `TUN`:
- TAP (L2): эмулирует Ethernet-интерфейс, передаются целые кадры с MAC-адресами, есть широковещательный трафик. Больше оверхеда.
- TUN (L3): работает с IP-пакетами, без MAC-адресов и broadcast. Меньше оверхеда, ниже задержка.
- Результаты замеров: `TAP` показал ~42.1 Mbits/sec (sender) / 39.0 Mbits/sec (receiver), `TUN` — ~42.4 Mbits/sec (sender) / 40.7 Mbits/sec (receiver). Разница небольшая, потому что в виртуальной среде VirtualBox ограничивающим фактором выступает не оверхед инкапсуляции, а скорость внутренней шины и CPU. В реальной сети разница TUN/TAP была бы более заметной.

Проверка подключения к RAS c хоста:
```
zenhert@linpro:~/vpn-lab$ cd ~/vpn-lab/ansible/files/
zenhert@linpro:~/vpn-lab/ansible/files$ sudo openvpn --config client.ovpn --daemon
2026-11-21 20:02:01 WARNING: Compression for receiving enabled. Compression has been used in the past to break encryption. Sent packets are not compressed unless "allow-compression yes" is also set.
zenhert@linpro:~/vpn-lab/ansible/files$ ping -c 4 10.10.10.1
--- 10.10.10.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3057ms
```
ЗЫ: подключение успешно, пинг идет.