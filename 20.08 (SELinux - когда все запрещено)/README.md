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

---

## Ход работы

### 1. Запустить Nginx на нестандартном порту 3-мя разными способами
Проверка SELinux:
```
[zenhert@localhost ~]$ getenforce
Enforcing
```

В виду EOL CentOS 7, его официальные зеркала больше не работают, но репозитории по-прежнему доступны, нужно перенеастроить `yum` на использование `vault`:
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
