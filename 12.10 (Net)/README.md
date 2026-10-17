# Отчёт по домашнему заданию по практике с архитектурой сети (12.10)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 17.10.2026
- **Задание:** 
  - В теоретической части требуется: 
    - Найти свободные подсети;
    - Посчитать количество узлов в каждой подсети, включая свободные;
    - Указать Broadcast-адрес для каждой подсети;
    - Проверить, нет ли ошибок при разбиении.
  - В практической части требуется: 
    - Соединить офисы в сеть согласно логической схеме и настроить роутинг;
    - Интернет-трафик со всех серверов должен ходить через inetRouter;
    - Все сервера должны видеть друг друга (должен проходить ping);
    - У всех новых серверов отключить дефолт на NAT (eth0), который vagrant поднимает для связи;
    - Добавить дополнительные сетевые интерфейсы, если потребуется.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы
Топология сети:
- Central - Directors	192.168.0.0/28 (14 хостов, x.y.0.15 - broadcast)
- Central - Office HW	192.168.0.32/28 (14 хостов, x.y.0.47 - broadcast)
- Central - WiFi 192.168.0.64/26 (62 хостов, x.y.0.127 - broadcast)
- Office1 - Dev	192.168.2.0/26 (62 хостов, x.y.2.63 - broadcast)
- Office1 - Test	192.168.2.64/26 (62 хостов, x.y.2.127 - broadcast)
- Office1 - Managers	192.168.2.128/26 (62 хостов, x.y.2.191 - broadcast)
- Office1 - Office HW	192.168.2.192/26 (62 хостов, x.y.2.255 - broadcast)
- Office2 - Dev	192.168.1.0/25 (126 хостов, x.y.1.127 - broadcast)
- Office2 - Test	192.168.1.128/26 (62 хостов, x.y.1.191 - broadcast)
- Office2 - Office HW	192.168.1.192/26 (62 хостов, x.y.1.255 - broadcast)
- Inet <-> Central	192.168.255.0/30 (2 хоста, x.y.255.3 - broadcast)
- Central <-> Office1	192.168.255.8/30 (2 хоста, x.y.255.11 - broadcast)
- Central <-> Office2	192.168.255.4/30 (2 хоста, x.y.255.7 - broadcast)

Структура проекта:
network-lab:
  - Vagrantfile
  - ansible:
    - provision.yml
    - hosts
    - templates:
      - 90-otus-routes-inetRouter.yaml
      - 90-otus-routes-centralRouter.yaml
      - 90-otus-routes-centralServer.yaml
      - 90-otus-routes-office1Router.yaml
      - 90-otus-routes-office1Server.yaml
      - 90-otus-routes-office2Router.yaml
      - 90-otus-routes-office2Server.yaml
      - iptables_rules.ipv4
      - iptables_restore
  - README.md

### 1. Подготовка структуры и необходимых файлов
Создание директорий:
```
zenhert@linpro:~$ mkdir -p ~/network-lab/ansible/templates
zenhert@linpro:~$ cd ~/network-lab/
```

Создание `Vagrantfile`:
```
zenhert@linpro:~/network-lab$ nano Vagrantfile
zenhert@linpro:~/network-lab$ cat Vagrantfile
MACHINES = {
  :inetRouter => {
    :box_name => "ubuntu2404",
    :vm_name  => "inetRouter",
    :net => [
      ["192.168.255.1", 2, "255.255.255.252", "router-net"],
      ["192.168.50.10", 8, "255.255.255.0"],
    ]
  },
  :centralRouter => {
    :box_name => "ubuntu2404",
    :vm_name  => "centralRouter",
    :net => [
      ["192.168.255.2", 2, "255.255.255.252", "router-net"],
      ["192.168.0.1",   3, "255.255.255.240", "dir-net"],
      ["192.168.0.33",  4, "255.255.255.240", "hw-net"],
      ["192.168.0.65",  5, "255.255.255.192", "mgt-net"],
      ["192.168.255.9", 6, "255.255.255.252", "office1-central"],
      ["192.168.255.5", 7, "255.255.255.252", "office2-central"],
      ["192.168.50.11", 8, "255.255.255.0"],
    ]
  },
  :centralServer => {
    :box_name => "ubuntu2404",
    :vm_name  => "centralServer",
    :net => [
      ["192.168.0.2",   2, "255.255.255.240", "dir-net"],
      ["192.168.50.12", 8, "255.255.255.0"],
    ]
  },
  :office1Router => {
    :box_name => "ubuntu2404",
    :vm_name  => "office1Router",
    :net => [
      ["192.168.255.10", 2, "255.255.255.252", "office1-central"],
      ["192.168.2.1",    3, "255.255.255.192", "dev1-net"],
      ["192.168.2.65",   4, "255.255.255.192", "test1-net"],
      ["192.168.2.129",  5, "255.255.255.192", "managers-net"],
      ["192.168.2.193",  6, "255.255.255.192", "office1-net"],
      ["192.168.50.20",  8, "255.255.255.0"],
    ]
  },
  :office1Server => {
    :box_name => "ubuntu2404",
    :vm_name  => "office1Server",
    :net => [
      ["192.168.2.130", 2, "255.255.255.192", "managers-net"],
      ["192.168.50.21", 8, "255.255.255.0"],
    ]
  },
  :office2Router => {
    :box_name => "ubuntu2404",
    :vm_name  => "office2Router",
    :net => [
      ["192.168.255.6", 2, "255.255.255.252", "office2-central"],
      ["192.168.1.1",   3, "255.255.255.128", "dev2-net"],
      ["192.168.1.129", 4, "255.255.255.192", "test2-net"],
      ["192.168.1.193", 5, "255.255.255.192", "office2-net"],
      ["192.168.50.30", 8, "255.255.255.0"],
    ]
  },
  :office2Server => {
    :box_name => "ubuntu2404",
    :vm_name  => "office2Server",
    :net => [
      ["192.168.1.2",   2, "255.255.255.128", "dev2-net"],
      ["192.168.50.31", 8, "255.255.255.0"],
    ]
  }
}

Vagrant.configure("2") do |config|
  MACHINES.each do |boxname, boxconfig|
    config.vm.define boxname do |box|
      box.vm.box = boxconfig[:box_name]
      box.vm.host_name = boxconfig[:vm_name]

      box.vm.provider "virtualbox" do |v|
        v.memory = 768
        v.cpus = 1
      end

      boxconfig[:net].each do |ipconf|
        box.vm.network("private_network",
                       ip: ipconf[0],
                       adapter: ipconf[1],
                       netmask: ipconf[2],
                       virtualbox__intnet: ipconf[3])
      end

      # Ansible запускается один раз, после создания последней ВМ
      if boxconfig[:vm_name] == "office2Server"
        box.vm.provision "ansible" do |ansible|
          ansible.playbook = "ansible/provision.yml"
          ansible.inventory_path = "ansible/hosts"
          ansible.host_key_checking = false
          ansible.limit = "all"
        end
      end
    end
  end
end
```

Создание `hosts`:
```
zenhert@linpro:~/network-lab$ nano ansible/hosts
zenhert@linpro:~/network-lab$ cat ansible/hosts
[routers]
inetRouter    ansible_host=192.168.50.10 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/inetRouter/virtualbox/private_key
centralRouter ansible_host=192.168.50.11 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/centralRouter/virtualbox/private_key
office1Router ansible_host=192.168.50.20 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/office1Router/virtualbox/private_key
office2Router ansible_host=192.168.50.30 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/office2Router/virtualbox/private_key

[servers]
centralServer ansible_host=192.168.50.12 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/centralServer/virtualbox/private_key
office1Server ansible_host=192.168.50.21 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/office1Server/virtualbox/private_key
office2Server ansible_host=192.168.50.31 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/office2Server/virtualbox/private_key

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

Создание `provision`:
```
zenhert@linpro:~/network-lab$ nano ansible/provision.yml
zenhert@linpro:~/network-lab$ cat ansible/provision.yml
---
- name: Common setup
  hosts: all
  become: true
  tasks:
    - name: Install traceroute
      apt:
        name: traceroute
        state: present
        update_cache: true

- name: Enable IP forwarding on routers
  hosts: routers
  become: true
  tasks:
    - name: sysctl net.ipv4.conf.all.forwarding=1
      ansible.posix.sysctl:
        name: net.ipv4.conf.all.forwarding
        value: '1'
        state: present
        sysctl_set: true
        reload: true

- name: Configure NAT on inetRouter
  hosts: inetRouter
  become: true
  tasks:
    - name: Disable ufw
      systemd:
        name: ufw
        state: stopped
        enabled: false

    - name: Deploy iptables rules file
      copy:
        src: templates/iptables_rules.ipv4
        dest: /etc/iptables_rules.ipv4
        owner: root
        group: root
        mode: '0644'

    - name: Deploy iptables restore script
      copy:
        src: templates/iptables_restore
        dest: /etc/network/if-pre-up.d/iptables
        owner: root
        group: root
        mode: '0755'

    - name: Apply iptables rules now
      shell: /sbin/iptables-restore < /etc/iptables_rules.ipv4
      changed_when: true

- name: Deploy network configs
  hosts: all
  become: true
  tasks:
    - name: Deploy 90-otus-routes.yaml
      template:
        src: "templates/90-otus-routes-{{ inventory_hostname }}.yaml"
        dest: /etc/netplan/90-otus-routes.yaml
        owner: root
        group: root
        mode: '0600'
      register: netplan_change

    - name: Apply netplan
      command: netplan apply
      when: netplan_change.changed
```

Создание шаблонов `netplan`:

PS: файлы `90-otus-routes-*.yaml` - каждый содержит только `dhcp4-overrides` для eth0 и статические маршруты. Адреса остаются в `50-vagrant.yaml`, который Vagrant генерирует сам. Netplan глубоко мержит файлы, поэтому обе конфигурации сосуществуют.
```
zenhert@linpro:~/network-lab$ nano ansible/templates/90-otus-routes-inetRouter.yaml
zenhert@linpro:~/network-lab$ cat ansible/templates/90-otus-routes-inetRouter.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
    eth1:
      routes:
        - to: 192.168.0.0/16
          via: 192.168.255.2
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/90-otus-routes-centralRouter.yaml
zenhert@linpro:~/network-lab$ cat ansible/templates/90-otus-routes-centralRouter.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      dhcp6: false
    eth1:
      routes:
        - to: 0.0.0.0/0
          via: 192.168.255.1
    eth5:
      routes:
        - to: 192.168.2.0/24
          via: 192.168.255.10
    eth6:
      routes:
        - to: 192.168.1.0/24
          via: 192.168.255.6
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/90-otus-routes-centralServer.yaml
zenhert@linpro:~/network-lab$ cat ansible/templates/90-otus-routes-centralServer.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      dhcp6: false
    eth1:
      routes:
        - to: 0.0.0.0/0
          via: 192.168.0.1
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/90-otus-routes-office1Router.yaml
zenhert@linpro:~/network-lab$ cat ansible/templates/90-otus-routes-office1Router.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      dhcp6: false
    eth1:
      routes:
        - to: 0.0.0.0/0
          via: 192.168.255.9
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/90-otus-routes-office1Server.yaml
zenhert@linpro:~/network-lab$ cat ansible/templates/90-otus-routes-office1Server.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      dhcp6: false
    eth1:
      routes:
        - to: 0.0.0.0/0
          via: 192.168.2.129
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/90-otus-routes-office2Router.yaml
zenhert@linpro:~/network-lab$ cat ansible/templates/90-otus-routes-office2Router.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      dhcp6: false
    eth1:
      routes:
        - to: 0.0.0.0/0
          via: 192.168.255.5
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/90-otus-routes-office2Server.yaml
zenhert@linpro:~/network-lab$ cat ansible/templates/90-otus-routes-office2Server.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      dhcp6: false
    eth1:
      routes:
        - to: 0.0.0.0/0
          via: 192.168.1.1
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/iptables_rules.ipv4
zenhert@linpro:~/network-lab$ cat ansible/templates/iptables_rules.ipv4
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING ! -d 192.168.0.0/16 -o eth0 -j MASQUERADE
COMMIT
```
```
zenhert@linpro:~/network-lab$ nano ansible/templates/iptables_restore
zenhert@linpro:~/network-lab$ cat ansible/templates/iptables_restore
#!/bin/sh
/sbin/iptables-restore < /etc/iptables_rules.ipv4
```

### 2. Запуск стенда и проверка
```
zenhert@linpro:~/network-lab$ vagrant up
Bringing machine 'inetRouter' up with 'virtualbox' provider...
Bringing machine 'centralRouter' up with 'virtualbox' provider...
Bringing machine 'centralServer' up with 'virtualbox' provider...
Bringing machine 'office1Router' up with 'virtualbox' provider...
Bringing machine 'office1Server' up with 'virtualbox' provider...
Bringing machine 'office2Router' up with 'virtualbox' provider...
Bringing machine 'office2Server' up with 'virtualbox' provider...
centralRouter              : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
centralServer              : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
inetRouter                 : ok=12   changed=8    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
office1Router              : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
office1Server              : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
office2Router              : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
office2Server              : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Проверка связности:
```
zenhert@linpro:~/network-lab$ vagrant ssh office1Server
vagrant@office1Server:~$ sudo -i
root@office1Server:~# for ip in 192.168.0.2 192.168.1.2 192.168.2.130; do ping -c2 $ip; done
PING 192.168.0.2 (192.168.0.2) 56(84) bytes of data.
64 bytes from 192.168.0.2: icmp_seq=1 ttl=62 time=3.96 ms
64 bytes from 192.168.0.2: icmp_seq=2 ttl=62 time=2.01 ms

--- 192.168.0.2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 2.008/2.981/3.955/0.973 ms
PING 192.168.1.2 (192.168.1.2) 56(84) bytes of data.
64 bytes from 192.168.1.2: icmp_seq=1 ttl=61 time=6.15 ms
64 bytes from 192.168.1.2: icmp_seq=2 ttl=61 time=2.90 ms

--- 192.168.1.2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 2.898/4.521/6.145/1.623 ms
PING 192.168.2.130 (192.168.2.130) 56(84) bytes of data.
64 bytes from 192.168.2.130: icmp_seq=1 ttl=64 time=0.019 ms
64 bytes from 192.168.2.130: icmp_seq=2 ttl=64 time=0.035 ms

--- 192.168.2.130 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1049ms
rtt min/avg/max/mdev = 0.019/0.027/0.035/0.008 ms
```

Проверка интернета через `inetRouter`:
```
vagrant@office1Server:~$ traceroute 8.8.8.8
traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 60 byte packets
 1  _gateway (192.168.2.129)  1.139 ms  0.707 ms  0.487 ms
 2  192.168.255.9 (192.168.255.9)  2.955 ms  2.641 ms  3.071 ms
 3  192.168.255.1 (192.168.255.1)  4.261 ms  4.329 ms  4.647 ms
 4  _gateway (10.0.2.2)  4.682 ms  4.630 ms  4.769 ms
```

Проверка отключения дефолта на NAT на любом хосте:
```
vagrant@office1Server:~$ ip route
default via 192.168.2.129 dev eth1 proto static
```

Проверка NAT на `inetRouter`:
```
zenhert@linpro:~/network-lab$ vagrant ssh inetRouter
vagrant@inetRouter:~$ sudo iptables -t nat -L POSTROUTING -n -v
Chain POSTROUTING (policy ACCEPT 4 packets, 288 bytes)
 pkts bytes target     prot opt in     out     source               destination
   61  3927 MASQUERADE  0    --  *      eth0    0.0.0.0/0           !192.168.0.0/16
```

Маршрутизация работает, NAT работает, traceroute подтверждает путь через `inetRouter`, все сервисы пингуются.
