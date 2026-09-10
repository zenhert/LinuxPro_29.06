# Отчёт по домашнему заданию по практике с Docker (02.09)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 09.09.2026
- **Задание:** 
  - Установите Docker на хост машину;
    - https://docs.docker.com/engine/install/ubuntu/
  - Установите Docker Compose - как плагин, или как отдельное приложение;
  - Создайте свой кастомный образ nginx на базе alpine. После запуска nginx должен отдавать кастомную страницу (достаточно изменить дефолтную страницу nginx);
  - Определите разницу между контейнером и образом;
  - Вывод опишите в домашнем задании;
  - Ответьте на вопрос: Можно ли в контейнере собрать ядро?

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS

---

## Ход работы

### 1. Установка Docker и Docker Compose
Добавление официального GPG-ключа Docker:
```
zenhert@linpro:~$ sudo mkdir -p /etc/apt/keyrings
zenhert@linpro:~$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

Добавление репозитория Docker:
```
zenhert@linpro:~$ echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Установка Docker и Docker Compose:
```
zenhert@linpro:~$ sudo apt update
zenhert@linpro:~$ sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
Setting up docker-buildx-plugin (0.37.0-1~ubuntu.24.04~noble) ...
Setting up containerd.io (2.3.5-1~ubuntu.24.04~noble) ...
Created symlink /etc/systemd/system/multi-user.target.wants/containerd.service → /usr/lib/systemd/system/containerd.service.
Setting up docker-compose-plugin (5.5.1-1~ubuntu.24.04~noble) ...
Setting up docker-ce-cli (5:29.8.0-1~ubuntu.24.04~noble) ...
Setting up pigz (2.8-1) ...
Setting up docker-ce-rootless-extras (5:29.8.0-1~ubuntu.24.04~noble) ...
Setting up docker-ce (5:29.8.0-1~ubuntu.24.04~noble) ...
Created symlink /etc/systemd/system/multi-user.target.wants/docker.service → /usr/lib/systemd/system/docker.service.
Created symlink /etc/systemd/system/sockets.target.wants/docker.socket → /usr/lib/systemd/system/docker.socket.
```

Проверка установки:
```
zenhert@linpro:~$ docker --version
Docker version 29.8.0, build 88096ef
zenhert@linpro:~$ docker compose version
Docker Compose version v5.5.1
```

Чтобы не использовать `sudo` для каждой docker-команды, нужно добавить пользователя в группу `docker`:
```
zenhert@linpro:~$ sudo usermod -aG docker $USER
zenhert@linpro:~$ newgrp docker
```

### 2. Создание кастомного образа nginx на базе Alpine
Создание кастомной страницы `index.html`:
```
zenhert@linpro:~$ mkdir ~/docker-nginx-custom
zenhert@linpro:~$ cd ~/docker-nginx-custom
zenhert@linpro:~/docker-nginx-custom$ echo "<html><body><h1>Hello from custom nginx on Alpine</h1></body></html>" > index.html
```

Создание `Dockerfile`:
```
zenhert@linpro:~/docker-nginx-custom$ nano Dockerfile
zenhert@linpro:~/docker-nginx-custom$ cat Dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```











