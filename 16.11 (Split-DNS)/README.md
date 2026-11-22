# Отчёт по домашнему заданию по практике с DNS (16.11)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 22.11.2026
- **Задание:** 
  - Взять стенд https://github.com/erlong15/vagrant-bind, добавить `client2`;
  - Завести в зоне `dns.lab` имена `web1` (client) и `web2` (client2);
  - Завести зону `newdns.lab` с записью `www` (на оба клиента);
  - Настроить Split-DNS:
     - `client` видит обе зоны, но в `dns.lab` только `web1`;
     - `client2` видит только `dns.lab` (с `web1` и `web2`).

---

## Исходное состояние

- VMWare ESXI 
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы
Структура проекта:
dns-lab:
  - Vagrantfile
  - ansible.cfg
  - ansible:
    - hosts
    - provision.yml
    - templates:
      - master-named.conf.j2
      - slave-named.conf.j2
      - servers-resolv.conf.j2
      - client-resolv.conf.j2
      - named.dns.lab.j2
      - named.dns.lab.client.j2
      - named.newdns.lab.j2
      - named.dns.lab.rev.j2
  - README.md

### 1. Подготовка структуры и необходимых файлов
Создание директорий:
```
zenhert@linpro:~$ mkdir -p ~/dns-lab/ansible/templates
zenhert@linpro:~$ cd ~/dns-lab
```

Создание `Vagrantfile`:
```
zenhert@linpro:~/dns-lab$ nano Vagrantfile
zenhert@linpro:~/dns-lab$ cat Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu2404"

  config.vm.provider "virtualbox" do |v|
    v.memory = 512
    v.cpus = 1
  end

  config.vm.define "ns01" do |ns01|
    ns01.vm.network "private_network", ip: "192.168.50.10", virtualbox__intnet: "dns"
    ns01.vm.network "private_network", ip: "192.168.60.10", adapter: 3   # hostonly для Ansible
    ns01.vm.hostname = "ns01"
  end

  config.vm.define "ns02" do |ns02|
    ns02.vm.network "private_network", ip: "192.168.50.11", virtualbox__intnet: "dns"
    ns02.vm.network "private_network", ip: "192.168.60.11", adapter: 3
    ns02.vm.hostname = "ns02"
  end

  config.vm.define "client" do |client|
    client.vm.network "private_network", ip: "192.168.50.15", virtualbox__intnet: "dns"
    client.vm.network "private_network", ip: "192.168.60.15", adapter: 3
    client.vm.hostname = "client"
  end

  config.vm.define "client2" do |client2|
    client2.vm.network "private_network", ip: "192.168.50.16", virtualbox__intnet: "dns"
    client2.vm.network "private_network", ip: "192.168.60.16", adapter: 3
    client2.vm.hostname = "client2"

    client2.vm.provision "ansible" do |ansible|
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
zenhert@linpro:~/dns-lab$ nano ansible.cfg
zenhert@linpro:~/dns-lab$ cat ansible.cfg
[defaults]
host_key_checking = false
inventory = ansible/hosts
command_warnings = false
```

Создание `ansible/hosts`:
```
zenhert@linpro:~/dns-lab$ nano ansible/hosts
zenhert@linpro:~/dns-lab$ cat ansible/hosts
[ns]
ns01 ansible_host=192.168.60.10 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/ns01/virtualbox/private_key
ns02 ansible_host=192.168.60.11 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/ns02/virtualbox/private_key

[clients]
client  ansible_host=192.168.60.15 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/client/virtualbox/private_key
client2 ansible_host=192.168.60.16 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/client2/virtualbox/private_key
```

Создание `ansible/provision.yml`:
``` 
zenhert@linpro:~/dns-lab$ nano ansible/provision.yml
zenhert@linpro:~/dns-lab$ cat ansible/provision.yml
---
- name: Common setup for all hosts
  hosts: all
  become: yes
  tasks:
    - name: Install bind9 and utilities
      apt:
        name:
          - bind9
          - bind9-utils
          - dnsutils
        state: present
        update_cache: true

    - name: Disable systemd-resolved (it blocks port 53 and overwrites resolv.conf)
      systemd:
        name: systemd-resolved
        state: stopped
        enabled: no

    - name: Remove symlink for resolv.conf
      file:
        path: /etc/resolv.conf
        state: absent

    - name: Ensure /etc/bind and /var/lib/bind directories exist
      file:
        path: "{{ item }}"
        state: directory
        owner: root
        group: bind
        mode: '0775'
      loop:
        - /etc/bind
        - /var/lib/bind

- name: Configure Master DNS (ns01)
  hosts: ns01
  become: yes
  tasks:
    - name: Deploy master named.conf
      template:
        src: templates/master-named.conf.j2
        dest: /etc/bind/named.conf
        owner: root
        group: bind
        mode: '0640'
      notify: restart bind9

    - name: Deploy zone files for ns01
      template:
        src: "templates/{{ item }}.j2"
        dest: "/var/lib/bind/{{ item }}"
        owner: root
        group: bind
        mode: '0640'
      loop:
        - named.dns.lab
        - named.dns.lab.client
        - named.newdns.lab
        - named.dns.lab.rev
      notify: restart bind9

    - name: Deploy resolv.conf for ns01
      template:
        src: templates/servers-resolv.conf.j2
        dest: /etc/resolv.conf
        owner: root
        group: root
        mode: '0644'

  handlers:
    - name: restart bind9
      systemd:
        name: bind9
        state: restarted
        enabled: yes

- name: Configure Slave DNS (ns02)
  hosts: ns02
  become: yes
  tasks:
    - name: Deploy slave named.conf
      template:
        src: templates/slave-named.conf.j2
        dest: /etc/bind/named.conf
        owner: root
        group: bind
        mode: '0640'
      notify: restart bind9

    - name: Deploy resolv.conf for ns02
      template:
        src: templates/servers-resolv.conf.j2
        dest: /etc/resolv.conf
        owner: root
        group: root
        mode: '0644'

  handlers:
    - name: restart bind9
      systemd:
        name: bind9
        state: restarted
        enabled: yes

- name: Configure clients
  hosts: clients
  become: yes
  tasks:
    - name: Deploy resolv.conf for clients
      template:
        src: templates/client-resolv.conf.j2
        dest: /etc/resolv.conf
        owner: root
        group: root
        mode: '0644'
```

Создание шаблонов:
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/servers-resolv.conf.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/servers-resolv.conf.j2
search dns.lab
{% if ansible_hostname == 'ns01' %}
nameserver 192.168.50.10
{% elif ansible_hostname == 'ns02' %}
nameserver 192.168.50.11
{% endif %}
```
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/client-resolv.conf.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/client-resolv.conf.j2
search dns.lab
nameserver 192.168.50.10
```
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/named.dns.lab.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/named.dns.lab.j2
$TTL 3600
$ORIGIN dns.lab.
@               IN      SOA     ns01.dns.lab. root.dns.lab. (
                            2711201407 ; serial
                            3600       ; refresh
                            600        ; retry
                            86400      ; expire
                            600        ; minimum
                        )
                IN      NS      ns01.dns.lab.
                IN      NS      ns02.dns.lab.

ns01            IN      A       192.168.50.10
ns02            IN      A       192.168.50.11

;Web
web1            IN      A       192.168.50.15
web2            IN      A       192.168.50.16
```
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/named.dns.lab.client.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/named.dns.lab.client.j2
$TTL 3600
$ORIGIN dns.lab.
@               IN      SOA     ns01.dns.lab. root.dns.lab. (
                            2711201407 ; serial
                            3600       ; refresh
                            600        ; retry
                            86400      ; expire
                            600        ; minimum
                        )
                IN      NS      ns01.dns.lab.
                IN      NS      ns02.dns.lab.

ns01            IN      A       192.168.50.10
ns02            IN      A       192.168.50.11

;Web
web1            IN      A       192.168.50.15
```
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/named.newdns.lab.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/named.newdns.lab.j2
$TTL 3600
$ORIGIN newdns.lab.
@               IN      SOA     ns01.dns.lab. root.dns.lab. (
                            2711201007 ; serial
                            3600       ; refresh
                            600        ; retry
                            86400      ; expire
                            600        ; minimum
                        )
                IN      NS      ns01.dns.lab.
                IN      NS      ns02.dns.lab.

ns01            IN      A       192.168.50.10
ns02            IN      A       192.168.50.11

;WWW
www             IN      A       192.168.50.15
www             IN      A       192.168.50.16
```
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/named.dns.lab.rev.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/named.dns.lab.rev.j2
$TTL 3600
@               IN      SOA     ns01.dns.lab. root.dns.lab. (
                            2711201407 ; serial
                            3600       ; refresh
                            600        ; retry
                            86400      ; expire
                            600        ; minimum
                        )
                IN      NS      ns01.dns.lab.
                IN      NS      ns02.dns.lab.

10              IN      PTR     ns01.dns.lab.
11              IN      PTR     ns02.dns.lab.
15              IN      PTR     web1.dns.lab.
16              IN      PTR     web2.dns.lab.
```
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/master-named.conf.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/master-named.conf.j2
options {
    listen-on port 53 { 192.168.50.10; 127.0.0.1; };
    listen-on-v6 port 53 { ::1; };
    directory       "/var/cache/bind";
    recursion yes;
    allow-query     { any; };
    dnssec-validation auto;
};

// Генерация ключей для TSIG (заранее сгенерированы)
key "client-key" {
    algorithm hmac-sha256;
    secret "IQg171Ht4mdGYcjjYKhI9gSc1fhoxzHZB+h2NMtyZWY=";
};
key "client2-key" {
    algorithm hmac-sha256;
    secret "m7r7SpZ9KBcA4kOl1JHQQnUiIlpQA1IJ9xkBHwdRAHc=";
};

// Access Control Lists
acl client { !key client2-key; key client-key; 192.168.50.15; };
acl client2 { !key client-key; key client2-key; 192.168.50.16; };

// VIEW 1: Для client1
view "client" {
    match-clients { client; };
    recursion yes;

    zone "dns.lab" {
        type master;
        file "/var/lib/bind/named.dns.lab.client";
    };
    zone "newdns.lab" {
        type master;
        file "/var/lib/bind/named.newdns.lab";
    };
};

// VIEW 2: Для client2
view "client2" {
    match-clients { client2; };
    recursion yes;

    zone "dns.lab" {
        type master;
        file "/var/lib/bind/named.dns.lab";
    };
    zone "50.168.192.in-addr.arpa" {
        type master;
        file "/var/lib/bind/named.dns.lab.rev";
    };
};

// VIEW 3: Default
view "default" {
    match-clients { any; };
    recursion yes;

    zone "." { type hint; file "/usr/share/dns/root.hints"; };
    zone "localhost" { type master; file "/etc/bind/db.local"; };
    zone "127.in-addr.arpa" { type master; file "/etc/bind/db.127"; };

    zone "dns.lab" {
        type master;
        file "/var/lib/bind/named.dns.lab";
    };
    zone "newdns.lab" {
        type master;
        file "/var/lib/bind/named.newdns.lab";
    };
    zone "50.168.192.in-addr.arpa" {
        type master;
        file "/var/lib/bind/named.dns.lab.rev";
    };
};
```
```
zenhert@linpro:~/dns-lab$ nano ansible/templates/slave-named.conf.j2
zenhert@linpro:~/dns-lab$ cat ansible/templates/slave-named.conf.j2
options {
    listen-on port 53 { 192.168.50.11; 127.0.0.1; };
    listen-on-v6 port 53 { ::1; };
    directory       "/var/cache/bind";
    recursion yes;
    allow-query     { any; };
    dnssec-validation auto;
};

view "default" {
    match-clients { any; };
    recursion yes;

    zone "." { type hint; file "/usr/share/dns/root.hints"; };
    zone "localhost" { type master; file "/etc/bind/db.local"; };
    zone "127.in-addr.arpa" { type master; file "/etc/bind/db.127"; };

    zone "dns.lab" {
        type slave;
        masters { 192.168.50.10; };
        file "/var/lib/bind/named.dns.lab";
    };
    zone "newdns.lab" {
        type slave;
        masters { 192.168.50.10; };
        file "/var/lib/bind/named.newdns.lab";
    };
    zone "50.168.192.in-addr.arpa" {
        type slave;
        masters { 192.168.50.10; };
        file "/var/lib/bind/named.dns.lab.rev";
    };
};
```

### 2. Запуск стенда и проверка
Запуск стенда:
```
zenhert@linpro:~/dns-lab$ vagrant up
Bringing machine 'ns01' up with 'virtualbox' provider...
Bringing machine 'ns02' up with 'virtualbox' provider...
Bringing machine 'client' up with 'virtualbox' provider...
Bringing machine 'client2' up with 'virtualbox' provider...
PLAY RECAP *********************************************************************
client                     : ok=7    changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
client2                    : ok=7    changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
ns01                       : ok=10   changed=8    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
ns02                       : ok=9    changed=7    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
zenhert@linpro:~/dns-lab$ vagrant status
Current machine states:
ns01                      running (virtualbox)
ns02                      running (virtualbox)
client                    running (virtualbox)
client2                   running (virtualbox)
```

Проверка Split-DNS на `client`:
```
zenhert@linpro:~/dns-lab$ vagrant ssh client -c "ping -c 2 web1.dns.lab; echo '---'; ping -c 2 www.newdns.lab; echo '---'; ping -c 2 web2.dns.lab"
PING web1.dns.lab (192.168.50.15) 56(84) bytes of data.
64 bytes from 192.168.50.15: icmp_seq=1 ttl=64 time=0.030 ms
64 bytes from 192.168.50.15: icmp_seq=2 ttl=64 time=0.052 ms

--- web1.dns.lab ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 0.030/0.041/0.052/0.011 ms
---
PING www.newdns.lab (192.168.50.15) 56(84) bytes of data.
64 bytes from 192.168.50.15: icmp_seq=1 ttl=64 time=0.031 ms
64 bytes from 192.168.50.15: icmp_seq=2 ttl=64 time=0.029 ms

--- www.newdns.lab ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 0.029/0.030/0.031/0.001 ms
---
ping: web2.dns.lab: Name or service not known
```

Проверка Split-DNS на `client1`:
```
zenhert@linpro:~/dns-lab$ vagrant ssh client2 -c "ping -c 2 web1.dns.lab; echo '---'; ping -c 2 web2.dns.lab; echo '---'; ping -c 2 www.newdns.lab"
PING web1.dns.lab (192.168.50.15) 56(84) bytes of data.
64 bytes from web1.dns.lab (192.168.50.15): icmp_seq=1 ttl=64 time=1.08 ms
64 bytes from web1.dns.lab (192.168.50.15): icmp_seq=2 ttl=64 time=0.735 ms

--- web1.dns.lab ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 0.735/0.908/1.082/0.173 ms
---
PING web2.dns.lab (192.168.50.16) 56(84) bytes of data.
64 bytes from web2.dns.lab (192.168.50.16): icmp_seq=1 ttl=64 time=0.013 ms
64 bytes from web2.dns.lab (192.168.50.16): icmp_seq=2 ttl=64 time=0.050 ms

--- web2.dns.lab ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 0.013/0.031/0.050/0.018 ms
---
ping: www.newdns.lab: Name or service not known
```

Настройка Split-DNS успешна. `client` видит обе зоны, но в `dns.lab` только `web1`, а `client1` видит только `dns.lab`.
