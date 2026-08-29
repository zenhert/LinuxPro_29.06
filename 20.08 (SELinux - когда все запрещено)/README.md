# Отчёт по домашнему заданию по практике с SELinux (20.08)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 25.08.2026
- **Задание:** 
  - Запустить Nginx на нестандартном порту 3-мя разными способами:
    - переключатели setsebool;
    - добавление нестандартного порта в имеющийся тип;
    - формирование и установка модуля SELinux.
  - Обеспечить работоспособность приложения при включенном selinux:
    - развернуть приложенный стенд https://github.com/Nickmob/vagrant_selinux_dns_problems;
    - выяснить причину неработоспособности механизма обновления зоны (см. README);
    - предложить решение (или решения) для данной проблемы;
    - выбрать одно из решений для реализации, предварительно обосновав выбор;
    - реализовать выбранное решение и продемонстрировать его работоспособность.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS 
- ВМ для Nginx: CentOS 7
- ВМ с Vagrant на Ubuntu 24.04.1 LTS

---

## Ход работы

### 1. Запустить Nginx на нестандартном порту 3-мя разными способами
Проверка SELinux:
```
[zenhert@localhost ~]$ getenforce
Enforcing
```

Ввиду EOL CentOS 7, его официальные зеркала больше не работают, но репозитории по-прежнему доступны, нужно перенастроить `yum` на использование `vault`:
Создание резервной копии:
```
[root@localhost ~]# cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
```
Отключение `mirrorlist` и замена `baseurl` на `vault.centos.org`:
```
[root@localhost ~]# sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo
[root@localhost ~]# sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo
[root@localhost ~]# sed -i 's|http://mirror.centos.org|http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo
```
Очистка кэша и повторное кэширование метаданных:
```
[root@localhost ~]# sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo
[root@localhost ~]# yum clean all
[root@localhost ~]# yum makecache
[root@localhost ~]# sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo
[root@localhost ~]# sed -i 's|http://mirror.centos.org|http://vault.centos.org|g' /etc/yum.repos.d/CentOS-Base.repo
[root@localhost ~]# yum clean all
Loaded plugins: fastestmirror
Cleaning repos: base extras updates
Cleaning up list of fastest mirrors
[root@localhost ~]# yum makecache
Loaded plugins: fastestmirror
Determining fastest mirrors
base                                                                                                                                                                                                                                                           | 3.6 kB  00:00:00
extras                                                                                                                                                                                                                                                         | 2.9 kB  00:00:00
updates                                                                                                                                                                                                                                                        | 2.9 kB  00:00:00
(1/10): base/7/x86_64/group_gz                                                                                                                                                                                                                                 | 153 kB  00:00:00
(2/10): base/7/x86_64/primary_db                                                                                                                                                                                                                               | 6.1 MB  00:00:00
(3/10): base/7/x86_64/other_db                                                                                                                                                                                                                                 | 2.6 MB  00:00:00
(4/10): base/7/x86_64/filelists_db                                                                                                                                                                                                                             | 7.2 MB  00:00:00
(5/10): extras/7/x86_64/primary_db                                                                                                                                                                                                                             | 253 kB  00:00:01
(6/10): extras/7/x86_64/filelists_db                                                                                                                                                                                                                           | 305 kB  00:00:01
(7/10): extras/7/x86_64/other_db                                                                                                                                                                                                                               | 154 kB  00:00:00
(8/10): updates/7/x86_64/filelists_db                                                                                                                                                                                                                          |  15 MB  00:00:00
(9/10): updates/7/x86_64/other_db                                                                                                                                                                                                                              | 1.6 MB  00:00:00
(10/10): updates/7/x86_64/primary_db                                                                                                                                                                                                                           |  27 MB  00:00:01
Metadata Cache Created
```

Установка `Nginx` и настройка портов:
```
[root@localhost ~]# yum install epel-release -y
Installed:
  epel-release.noarch 0:7-11
Complete!
```
```
[root@localhost ~]# yum install nginx -y
Installed:
  nginx.x86_64 1:1.20.1-10.el7
Dependency Installed:
  centos-indexhtml.noarch 0:7-9.el7.centos
  gperftools-libs.x86_64 0:2.6.1-1.el7
  nginx-filesystem.noarch 1:1.20.1-10.el7
  openssl11-libs.x86_64 1:1.1.1k-7.el7
Complete!
```
Отключение `firewalld`:
```
[root@localhost ~]# systemctl stop firewalld
[root@localhost ~]# systemctl disable firewalld
Removed symlink /etc/systemd/system/multi-user.target.wants/firewalld.service.
Removed symlink /etc/systemd/system/dbus-org.fedoraproject.FirewallD1.service.
```
Изменение портов в конфиге `Nginx`:
```
[root@localhost ~]# vi /etc/nginx/nginx.conf
        listen       4881;
        listen       [::]:4881;
```
Проверка конфига и службы:
```
[root@localhost ~]# nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```
```
[root@localhost ~]# systemctl status nginx.service
● nginx.service - The nginx HTTP and reverse proxy server
   Active: failed (Result: exit-code) since Wed 2026-08-26 16:57:42 MSK; 30s ago
Aug 26 16:57:42 localhost.localdomain nginx[18847]: nginx: [emerg] bind() to 0.0.0.0:4881 failed (13: Permission denied)
```

## Переключатели setsebool
```
[root@localhost ~]# yum install policycoreutils-python -y
Installed:
  policycoreutils-python.x86_64 0:2.5-34.el7
Dependency Installed:
  audit-libs-python.x86_64 0:2.8.5-4.el7
  checkpolicy.x86_64 0:2.5-8.el7
  libcgroup.x86_64 0:0.41-21.el7
  libsemanage-python.x86_64 0:2.5-14.el7
  python-IPy.noarch 0:0.75-6.el7
  setools-libs.x86_64 0:3.3.8-4.el7
Complete!
```

Нужно найти запись в `audit.log`:
```
[root@localhost ~]# grep nginx /var/log/audit/audit.log | tail -5
type=AVC msg=audit(1787752700.450:279): avc:  denied  { name_bind } for  pid=19089 comm="nginx" src=4881 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0
```
```
[root@localhost ~]# grep 1787752700.450:279 /var/log/audit/audit.log | audit2why
type=AVC msg=audit(1787752700.450:279): avc:  denied  { name_bind } for  pid=19089 comm="nginx" src=4881 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0

        Was caused by:
        The boolean nis_enabled was set incorrectly.
        Description:
        Allow nis to enabled

        Allow access by executing:
        # setsebool -P nis_enabled 1
```
Вывод показывает, что нужно включить boolean `nis_enabled`

Включение `boolean` и перезапуск `nginx`:
```
[root@localhost ~]# setsebool -P nis_enabled on
[root@localhost ~]# systemctl restart nginx
[root@localhost ~]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
   Active: active (running) since Wed 2026-08-26 17:41:38 MSK; 4s ago
Aug 26 17:41:38 localhost.localdomain systemd[1]: Started The nginx HTTP and reverse proxy server.
```
Nginx заработал, теперь необходимо сделать откат:
```
[root@localhost ~]# setsebool -P nis_enabled off
[root@localhost ~]# systemctl stop nginx
```

## Добавление нестандартного порта в имеющийся тип
Добавление порта в тип `http_port_t`:
```
[root@localhost ~]# semanage port -a -t http_port_t -p tcp 4881
[root@localhost ~]# semanage port -l | grep http_port_t
http_port_t                    tcp      4881, 80, 81, 443, 488, 8008, 8009, 8443, 9000
pegasus_http_port_t            tcp      5988
[root@localhost ~]# systemctl restart nginx
[root@localhost ~]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
   Active: active (running) since Wed 2026-08-26 17:46:53 MSK; 10s ago
Aug 26 17:46:53 localhost.localdomain systemd[1]: Started The nginx HTTP and reverse proxy server.
```
Повторный откат:
```
[root@localhost ~]# semanage port -d -t http_port_t -p tcp 4881
[root@localhost ~]# systemctl stop nginx
```

## Формирование и установка модуля SELinux
Создать и применить модуль:
```
[root@localhost ~]# grep nginx /var/log/audit/audit.log | audit2allow -M nginx
******************** IMPORTANT ***********************
To make this policy package active, execute:

semodule -i nginx.pp

[root@localhost ~]# semodule -i nginx.pp
[root@localhost ~]# systemctl start nginx
[root@localhost ~]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
   Active: active (running) since Wed 2026-08-26 17:50:38 MSK; 5s ago
Aug 26 17:50:38 localhost.localdomain systemd[1]: Started The nginx HTTP and reverse proxy server.
```
Nginx успешно запустился, снова откат:
```
[root@localhost ~]# semodule -r nginx
libsemanage.semanage_direct_remove_key: Removing last nginx module (no other nginx module exists at another priority).
[root@localhost ~]# systemctl stop nginx
```

### 2. Обеспечить работоспособность приложения при включенном selinux
Во время подготовки хоста для стенда с Vagrant были проверены и установлены следующие компоненты:
- Vagrant — версии 2.4.9. Установка из официального репозитория HashiCorp и прямыми ссылками на `.deb` завершилась ошибкой 404 (файлы недоступны), поэтому Vagrant был поставлен вручную из zip-архива:
  ```
  zenhert@linpro:~$ unzip vagrant_2.4.9_linux_amd64.zip -d vagrant_bin
  zenhert@linpro:~$ sudo install vagrant_bin/vagrant /usr/local/bin/vagrant
  zenhert@linpro:~$ vagrant --version
  Vagrant 2.4.9
  ```
- VirtualBox — проверен командой `VBoxManage --version`.
- Ansible — проверен командой `ansible --version`.
- Git — использовался для клонирования репозитория стенда.

## Развертывание стенда
Клонирование репозитория со стендом:
```
zenhert@linpro:~$ git clone https://github.com/Nickmob/vagrant_selinux_dns_problems.git
zenhert@linpro:~$ cd vagrant_selinux_dns_problems
```
При первом запуске `vagrant up` возникла проблема с загрузкой бокса `almalinux/9`: Vagrant Cloud отдавал 404 на файл бокса, независимо от выбранной версии (пробовали 9.4.20240805, 9.8.20260810 и другие). Также не помогли альтернативные боксы `bento/almalinux-9 и rockylinux/9`

В качестве решения было решено использовать ручной метод - бокс был скачан вручную с HCP Vagrant Registry через браузер (файл `8eb039d5-9bb6-11f1-832c-0a8d6f3931c9`) и добавлен в Vagrant локально:
```
zenhert@linpro:~$ cd ~/vagrant_selinux_dns_problems
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant box add almalinux/9 ./8eb039d5-9bb6-11f1-832c-0a8d6f3931c9.box
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant box list
almalinux/9 (virtualbox, 0, (amd64))
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant up
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant status
Current machine states:
ns01                      running (virtualbox)
client                    running (virtualbox)
```
После этого `vagrant up` успешно развернуть обе виртуальные машины.

PS: При первом запуске VirtualBox выдавал ошибку `VT-x is not available (VERR_VMX_NO_VMX)`. Причиной оказалась сам хост, т.к. работает как ВМ на VMWare ESXI. Для хоста была включена функция вложенной виртуализации (Nested Virtualization).

## Проверка неработоспособности механизма обновления зоны
Подключение к клиенту:
```
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant ssh client
###############################
### Welcome to the DNS lab! ###
###############################

- Use this client to test the enviroment
- with dig or nslookup. Ex:
    dig @192.168.50.10 ns01.dns.lab

- nsupdate is available in the ddns.lab zone. Ex:
    nsupdate -k /etc/named.zonetransfer.key
    server 192.168.50.10
    zone ddns.lab
    update add www.ddns.lab. 60 A 192.168.50.15
    send

- rndc is also available to manage the servers
    rndc -c ~/rndc.conf reload

###############################
### Enjoy! ####################
###############################
Last login: Sat Aug 29 17:39:22 2026 from 10.0.2.2
```

Попытка добавить зону:
```
[vagrant@client ~]$ nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add www.ddns.lab. 60 A 192.168.50.15
> send
update failed: SERVFAIL
```

Диагностика на клиенте через просмотр логов SELinux:
```
[vagrant@client ~]$ sudo -i
[root@client ~]# cat /var/log/audit/audit.log | audit2why
type=AVC msg=audit(1788025106.803:562): avc:  denied  { dac_read_search } for  pid=4407 comm="20-chrony-dhcp" capability=2  scontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0 tcontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0 tclass=capability permissive=0
type=AVC msg=audit(1788025106.803:562): avc:  denied  { dac_override } for  pid=4407 comm="20-chrony-dhcp" capability=1  scontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0 tcontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0 tclass=capability permissive=0
type=AVC msg=audit(1788025107.127:569): avc:  denied  { dac_read_search } for  pid=4465 comm="11-dhclient" capability=2  scontext=system_u:system_r:NetworkManager_dispatcher_dhclient_t:s0 tcontext=system_u:system_r:NetworkManager_dispatcher_dhclient_t:s0 tclass=capability permissive=0
type=AVC msg=audit(1788025107.127:569): avc:  denied  { dac_override } for  pid=4465 comm="11-dhclient" capability=1  scontext=system_u:system_r:NetworkManager_dispatcher_dhclient_t:s0 tcontext=system_u:system_r:NetworkManager_dispatcher_dhclient_t:s0 tclass=capability permissive=0
type=AVC msg=audit(1788025107.131:570): avc:  denied  { dac_read_search } for  pid=4466 comm="20-chrony-dhcp" capability=2  scontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0tcontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0 tclass=capability permissive=0
type=AVC msg=audit(1788025107.131:570): avc:  denied  { dac_override } for  pid=4466 comm="20-chrony-dhcp" capability=1  scontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0tcontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0 tclass=capability permissive=0
```
На клиенте не оказалось каких-то конкретных ошибок, нужно смотреть на сервере.

Подключение к ns01:
```
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant ssh ns01
Last login: Sat Aug 29 17:36:35 2026 from 10.0.2.2
```

Анализ логов SELinux:
```
[vagrant@ns01 ~]$ sudo -i
[root@ns01 ~]# cat /var/log/audit/audit.log | audit2why
type=AVC msg=audit(1788025445.447:1451): avc:  denied  { write } for  pid=9203 comm="isc-net-0001" name="dynamic" dev="sda4" ino=332117 scontext=system_u:system_r:named_t:s0 tcontext=unconfined_u:object_r:named_conf_t:s0 tclass=dir permissive=0
```
Вывод указал на запрет записи для `named_t` в каталог с типом `named_conf_t`

Проверка контекста:
```
[root@ns01 ~]# ls -laZ /etc/named
total 28
drw-rwx---.  3 root named system_u:object_r:named_conf_t:s0      121 Aug 29 17:36 .
drwxr-xr-x. 89 root root  system_u:object_r:etc_t:s0            8192 Aug 29 17:36 ..
drw-rwx---.  2 root named unconfined_u:object_r:named_conf_t:s0   56 Aug 29 17:36 dynamic
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      784 Aug 29 17:36 named.50.168.192.rev
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      610 Aug 29 17:36 named.dns.lab
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      609 Aug 29 17:36 named.dns.lab.view1
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      657 Aug 29 17:36 named.newdns.lab
[root@ns01 ~]# ls -laZ /var/named/named.localhost
-rw-r-----. 1 root named system_u:object_r:named_zone_t:s0 152 Aug 13 11:27 /var/named/named.localhost
```
Тип у файлов в `/etc/named` - `named_conf_t`, а в `/var/named/named.localhost` - `named_zone_t`

Исправление контекста и проверка:
```
[root@ns01 ~]# chcon -R -t named_zone_t /etc/named
[root@ns01 ~]# ls -laZ /etc/named
total 28
drw-rwx---.  3 root named system_u:object_r:named_zone_t:s0      121 Aug 29 17:36 .
drwxr-xr-x. 89 root root  system_u:object_r:etc_t:s0            8192 Aug 29 17:36 ..
drw-rwx---.  2 root named unconfined_u:object_r:named_zone_t:s0   56 Aug 29 17:36 dynamic
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      784 Aug 29 17:36 named.50.168.192.rev
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      610 Aug 29 17:36 named.dns.lab
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      609 Aug 29 17:36 named.dns.lab.view1
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      657 Aug 29 17:36 named.newdns.lab
```

Проверка обновления зоны:
```
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant ssh client
[vagrant@client ~]$ nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add www.ddns.lab. 60 A 192.168.50.15
> send
> quit
[vagrant@client ~]$ dig www.ddns.lab
;; QUESTION SECTION:
;www.ddns.lab.                  IN      A

;; ANSWER SECTION:
www.ddns.lab.           60      IN      A       192.168.50.15
```
`Send` прошел без ошибок.

Перезагрузка хостов:
```
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant reload ns01
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant reload client
```

Повторная проверка записи:
```
zenhert@linpro:~/vagrant_selinux_dns_problems$ vagrant ssh client
[vagrant@client ~]$ dig @192.168.50.10 www.ddns.lab
;; QUESTION SECTION:
;www.ddns.lab.                  IN      A

;; ANSWER SECTION:
www.ddns.lab.           60      IN      A       192.168.50.15
```
`Send` также прошел.

Опционально, можно добавить fcontext-правило, чтобы после `restorecon` контекст не сбросился:
```
[root@ns01 ~]# semanage fcontext -a -t named_zone_t "/etc/named(/.*)?"
[root@ns01 ~]# restorecon -Rv /etc/named
[root@ns01 ~]# ls -laZ /etc/named
total 28
drw-rwx---.  3 root named system_u:object_r:named_zone_t:s0      121 Aug 29 17:36 .
drwxr-xr-x. 89 root root  system_u:object_r:etc_t:s0            8192 Aug 29 18:11 ..
drw-rwx---.  2 root named unconfined_u:object_r:named_zone_t:s0   88 Aug 29 17:57 dynamic
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      784 Aug 29 17:36 named.50.168.192.rev
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      610 Aug 29 17:36 named.dns.lab
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      609 Aug 29 17:36 named.dns.lab.view1
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      657 Aug 29 17:36 named.newdns.lab
```
