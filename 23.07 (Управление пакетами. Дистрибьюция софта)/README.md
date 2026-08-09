# Отчёт по домашнему заданию по работе с дистрибьюцией софта (23.07)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 10.08.2026
- **Задание:** 
  - Создать свой RPM-пакет (можно взять свое приложение, либо собрать, например, Apache с определенными опциями).
  - Создать свой репозиторий и разместить там ранее собранный RPM.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы

В виду использования Ubuntu 24.04 задание будет адаптировано, чтобы создать RPM-пакет с тестовым приложением и разместить его в репозитории, отдаваемом через Nginx.

### 1. Создание своего RPM-пакета
В новых версиях Ubuntu утилиты для сборки RPM исключены из репозиториев. Конечно, можно было бы использовать Docker-контейнер с AlmaLinux, но ввиду желания собрать RPM-пакет чисто на Ubuntu, будет создан deb-пакет через `fpm`, а затем конвертирован с RPM через `alien`. 
Установка необходимых пакетов:
```
zenhert@linpro:~$ sudo add-apt-repository universe
zenhert@linpro:~$ sudo apt update && sudo apt upgrade -y
zenhert@linpro:~$ sudo apt install -y ruby ruby-dev rubygems build-essential nginx createrepo-c wget curl
zenhert@linpro:~$ sudo apt install alien -y
```

Создание простого RPM-пакета с помощью `fpm` и `alien` (создание временного каталога, исполняемого файла и RPM-пакета):
```
zenhert@linpro:~$ mkdir -p ~/zen-package/usr/bin
```
```
zenhert@linpro:~$ cat << 'EOF' > ~/zen-package/usr/bin/zen
#!/bin/bash
echo "Zen's RPM on Ubuntu!"
EOF
chmod +x ~/zen-package/usr/bin/zen
```
```
zenhert@linpro:~$ fpm -s dir -t deb -n zen -v 1.0 --architecture amd64 -C ~/zen-package usr/bin/zen
Created package {:path=>"zen_1.0_amd64.deb"}
```

Конвертация deb в RPM:
```
zenhert@linpro:~$ sudo alien -r zen_1.0_amd64.deb
zen-1.0-2.x86_64.rpm generated
```

RPM-пакет создан:
```
zenhert@linpro:~$ ls
zen-1.0-2.x86_64.rpm  zen_1.0_amd64.deb  zen-package
```

### 2. Создание репозитория и размещение RPM-пакета
Копирование RPM в репозиторий:
```
zenhert@linpro:~$ sudo mkdir -p /var/www/html/repo
zenhert@linpro:~$ sudo cp zen-*.rpm /var/www/html/repo/
```

Проверка Nginx:
```
zenhert@linpro:~$ sudo nginx -t && sudo systemctl restart nginx
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Инициализация репозитория:
```
zenhert@linpro:~$ sudo createrepo_c /var/www/html/repo/
Directory walk started
Directory walk done - 1 packages
Temporary output repo path: /var/www/html/repo/.repodata/
Preparing sqlite DBs
Pool started (with 5 workers)
Pool finished
```

Итоговая проверка репозитория:
```
zenhert@linpro:~$ curl http://localhost/repo/
<html>
<head><title>Index of /repo/</title></head>
<body>
<h1>Index of /repo/</h1><hr><pre><a href="../">../</a>
<a href="repodata/">repodata/</a>                                          09-Aug-2026 22:45                   -
<a href="zen-1.0-2.x86_64.rpm">zen-1.0-2.x86_64.rpm</a>                               09-Aug-2026 22:38                6856
</pre><hr></body>
</html>
```

Добавление в репозиторий стороннего пакета и обновление метаданных для демонстрации расширения репозитория:
```
zenhert@linpro:~$ cd /var/www/html/repo
zenhert@linpro:/var/www/html/repo$ sudo wget https://repo.percona.com/yum/percona-release-latest.noarch.rpm
2026-08-09 22:48:14 (363 MB/s) - ‘percona-release-latest.noarch.rpm’ saved [28152/28152]
zenhert@linpro:/var/www/html/repo$ sudo createrepo_c --update /var/www/html/repo/
```

Финальная проверка:
```
zenhert@linpro:/var/www/html/repo$ curl http://localhost/repo/
<html>
<head><title>Index of /repo/</title></head>
<body>
<h1>Index of /repo/</h1><hr><pre><a href="../">../</a>
<a href="repodata/">repodata/</a>                                          09-Aug-2026 22:48                   -
<a href="percona-release-latest.noarch.rpm">percona-release-latest.noarch.rpm</a>                  30-Apr-2026 05:14               28152
<a href="zen-1.0-2.x86_64.rpm">zen-1.0-2.x86_64.rpm</a>                               09-Aug-2026 22:38                6856
</pre><hr></body>
</html>
```
Проверка завершена, в листинге появился percona-release-latest.noarch.rpm
