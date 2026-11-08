# Отчёт по домашнему заданию по практике с OSPF (02.11)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 08.11.2026
- **Задание:** 
  - Поднять три виртуалки;
  - Объединить их разными VLAN:
    - Поднять OSPF между машинами на базе Quagga;
    - Изобразить ассиметричный роутинг;
    - Сделать один из линков "дорогим", но что бы при этоми роутинг был симметричным.

---

## Исходное состояние

- VMWare ESXI 
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы
Структура проекта:
ospf-lab:
  - Vagrantfile
  - ansible.cfg
  - ansible:
    - hosts
    - provision.yml
    - defaults:
      - main.yml
    - templates:
      - daemons
      - frr.conf.j2
  - README.md

### 1. Подготовка структуры и необходимых файлов
Создание директорий:
```
zenhert@linpro:~$ mkdir -p ~/ospf-lab/ansible/templates
zenhert@linpro:~$ mkdir -p ~/ospf-lab/ansible/defaults
zenhert@linpro:~$ cd ~/ospf-lab
```

Создание `Vagrantfile`:
```
zenhert@linpro:~/ospf-lab$ nano Vagrantfile
zenhert@linpro:~/ospf-lab$ cat Vagrantfile
MACHINES = {
  :router1 => {
    :box_name => "ubuntu2404",
    :vm_name => "router1",
    :net => [
      {ip: '10.0.10.1', adapter: 2, netmask: "255.255.255.252", virtualbox__intnet: "r1-r2"},
      {ip: '10.0.12.1', adapter: 3, netmask: "255.255.255.252", virtualbox__intnet: "r1-r3"},
      {ip: '192.168.10.1', adapter: 4, netmask: "255.255.255.0", virtualbox__intnet: "net1"},
      {ip: '192.168.50.10', adapter: 5},
    ]
  },
  :router2 => {
    :box_name => "ubuntu2404",
    :vm_name => "router2",
    :net => [
      {ip: '10.0.10.2', adapter: 2, netmask: "255.255.255.252", virtualbox__intnet: "r1-r2"},
      {ip: '10.0.11.2', adapter: 3, netmask: "255.255.255.252", virtualbox__intnet: "r2-r3"},
      {ip: '192.168.20.1', adapter: 4, netmask: "255.255.255.0", virtualbox__intnet: "net2"},
      {ip: '192.168.50.11', adapter: 5},
    ]
  },
  :router3 => {
    :box_name => "ubuntu2404",
    :vm_name => "router3",
    :net => [
      {ip: '10.0.11.1', adapter: 2, netmask: "255.255.255.252", virtualbox__intnet: "r2-r3"},
      {ip: '10.0.12.2', adapter: 3, netmask: "255.255.255.252", virtualbox__intnet: "r1-r3"},
      {ip: '192.168.30.1', adapter: 4, netmask: "255.255.255.0", virtualbox__intnet: "net3"},
      {ip: '192.168.50.12', adapter: 5},
    ]
  }
}

Vagrant.configure("2") do |config|
  MACHINES.each do |boxname, boxconfig|
    config.vm.define boxname do |box|
      box.vm.box = boxconfig[:box_name]
      box.vm.host_name = boxconfig[:vm_name]

      # Провижининг Ansible запускаем только после создания последней ВМ
      if boxconfig[:vm_name] == "router3"
        box.vm.provision "ansible" do |ansible|
          ansible.playbook = "ansible/provision.yml"
          ansible.inventory_path = "ansible/hosts"
          ansible.host_key_checking = false
          ansible.limit = "all"
        end
      end

      boxconfig[:net].each do |ipconf|
        box.vm.network "private_network", **ipconf
      end
    end
  end
end
```

Создание `ansible.cfg`:
```
zenhert@linpro:~/ospf-lab$ nano ansible.cfg
zenhert@linpro:~/ospf-lab$ cat ansible.cfg
[defaults]
host_key_checking = false
inventory = ansible/hosts
command_warnings = false
```

Создание `ansible/hosts`:
```
zenhert@linpro:~/ospf-lab$ nano ansible/hosts
zenhert@linpro:~/ospf-lab$ cat ansible/hosts
[routers]
router1 ansible_host=192.168.50.10 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/router1/virtualbox/private_key router_id=1.1.1.1
router2 ansible_host=192.168.50.11 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/router2/virtualbox/private_key router_id=2.2.2.2
router3 ansible_host=192.168.50.12 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/router3/virtualbox/private_key router_id=3.3.3.3
```

Создание `ansible/provision.yml`:
``` 
zenhert@linpro:~/ospf-lab$ nano ansible/provision.yml
zenhert@linpro:~/ospf-lab$ cat ansible/provision.yml
---
- name: Setup OSPF routers
  hosts: all
  become: yes
  vars_files:
    - defaults/main.yml
  tasks:
    - name: Disable ufw
      systemd:
        name: ufw
        state: stopped
        enabled: false

    - name: Install base tools
      apt:
        name:
          - vim
          - traceroute
          - tcpdump
          - net-tools
          - curl
          - gnupg
        state: present
        update_cache: true

    - name: Add GPG key for FRR
      shell: |
        curl -s https://deb.frrouting.org/frr/keys.asc | gpg --dearmor > /usr/share/keyrings/frr.gpg
      args:
        creates: /usr/share/keyrings/frr.gpg

    - name: Add FRR repository
      apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/frr.gpg] https://deb.frrouting.org/frr {{ ansible_distribution_release }} frr-stable"
        state: present

    - name: Install FRR packages
      apt:
        name:
          - frr
          - frr-pythontools
        state: present
        update_cache: true

    - name: Enable IP forwarding
      ansible.posix.sysctl:
        name: net.ipv4.conf.all.forwarding
        value: '1'
        state: present
        sysctl_set: true
        reload: true

    - name: Disable rp_filter (Required for asymmetric routing)
      ansible.posix.sysctl:
        name: net.ipv4.conf.all.rp_filter
        value: '0'
        state: present
        sysctl_set: true
        reload: true

    - name: Deploy daemons config
      template:
        src: templates/daemons
        dest: /etc/frr/daemons
        owner: frr
        group: frr
        mode: '0640'
      notify: restart frr

    - name: Deploy frr.conf
      template:
        src: templates/frr.conf.j2
        dest: /etc/frr/frr.conf
        owner: frr
        group: frr
        mode: '0640'
      notify: restart frr

  handlers:
    - name: restart frr
      service:
        name: frr
        state: restarted
        enabled: true
```

Создание `ansible/defaults/main.yml`:
```
zenhert@linpro:~/ospf-lab$ nano ansible/defaults/main.yml
zenhert@linpro:~/ospf-lab$ cat ansible/defaults/main.yml
---
symmetric_routing: false
```

Создание шаблонов:
```
zenhert@linpro:~/ospf-lab$ nano ansible/templates/daemons
zenhert@linpro:~/ospf-lab$ cat ansible/templates/daemons
zebra=yes
bgpd=no
ospfd=yes
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no
```
```
zenhert@linpro:~/ospf-lab$ nano ansible/templates/frr.conf.j2
zenhert@linpro:~/ospf-lab$ cat ansible/templates/frr.conf.j2
{% set r1r2_ips = ['10.0.10.1', '10.0.10.2'] %}
{% set ospf_ips = ['10.0.10.1','10.0.10.2','10.0.11.1','10.0.11.2','10.0.12.1','10.0.12.2',
                   '192.168.10.1','192.168.20.1','192.168.30.1'] %}
frr version 8.1
frr defaults traditional
hostname {{ ansible_hostname }}
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
{% for iface in ansible_facts['interfaces'] | sort %}
{% if ansible_facts[iface]['ipv4'] is defined and ansible_facts[iface]['ipv4']['address'] is defined %}
{% set if_ip = ansible_facts[iface]['ipv4']['address'] %}
{% if if_ip in ospf_ips %}
interface {{ iface }}
 description {{ if_ip }}
 ip ospf mtu-ignore
 ip ospf hello-interval 10
 ip ospf dead-interval 30
{% if if_ip in r1r2_ips %}
{% if ansible_hostname == 'router1' or (ansible_hostname == 'router2' and symmetric_routing | bool) %}
 ip ospf cost 1000
{% endif %}
{% endif %}
!
{% endif %}
{% endif %}
{% endfor %}

router ospf
{% if router_id is defined %}
 ospf router-id {{ router_id }}
{% endif %}
{% for iface in ansible_facts['interfaces'] | sort %}
{% if ansible_facts[iface]['ipv4'] is defined and ansible_facts[iface]['ipv4']['address'] is defined %}
{% set if_ip = ansible_facts[iface]['ipv4']['address'] %}
{% if if_ip in ospf_ips %}
 network {{ ansible_facts[iface]['ipv4']['network'] }}/{{ ansible_facts[iface]['ipv4']['prefix'] }} area 0
{% endif %}
{% endif %}
{% endfor %}
!
log file /var/log/frr/frr.log
```

### 2. Запуск стенда и проверка
Запуск стенда:
```
zenhert@linpro:~/ospf-lab$ vagrant up
Bringing machine 'router1' up with 'virtualbox' provider...
Bringing machine 'router2' up with 'virtualbox' provider...
Bringing machine 'router3' up with 'virtualbox' provider...
zenhert@linpro:~/ospf-lab$ vagrant status
Current machine states:

router1                   running (virtualbox)
router2                   running (virtualbox)
router3                   running (virtualbox)
```

Проверка базового `OSPF`:
```
zenhert@linpro:~/ospf-lab$ vagrant ssh router1 -c "traceroute 192.168.30.1"
traceroute to 192.168.30.1 (192.168.30.1), 30 hops max, 60 byte packets
 1  192.168.30.1 (192.168.30.1)  0.652 ms  0.545 ms  0.512 ms
```
ЗЫ: трафик идет напрямую

Проверка асимметричного роутинга:
```
zenhert@linpro:~/ospf-lab$ vagrant ssh router1
vagrant@router1:~$ sudo vtysh
router1# show ip route ospf
IPv4 unicast VRF default:
O   10.0.10.0/30 [110/300] via 10.0.12.2, eth2, weight 1, 00:00:42
O>* 10.0.11.0/30 [110/200] via 10.0.12.2, eth2, weight 1, 00:00:42
O>* 192.168.20.0/24 [110/300] via 10.0.12.2, eth2, weight 1, 00:00:42
O>* 192.168.30.0/24 [110/200] via 10.0.12.2, eth2, weight 1, 00:00:42

zenhert@linpro:~/ospf-lab$ vagrant ssh router2
vagrant@router2:~$ sudo vtysh
router2# show ip route ospf
IPv4 unicast VRF default:
O>* 10.0.12.0/30 [110/200] via 10.0.10.1, eth1, weight 1, 00:01:52
  *                        via 10.0.11.1, eth2, weight 1, 00:01:52
O>* 192.168.10.0/24 [110/200] via 10.0.10.1, eth1, weight 1, 00:01:52
O>* 192.168.30.0/24 [110/200] via 10.0.11.1, eth2, weight 1, 00:01:52
```
ЗЫ: для проверки использовался вывод команды `show ip route ospf` из `FRR`. Маршруты до одной и той же пары сетей на разных роутерах проходят через разные интерфейсы.
