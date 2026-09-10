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
Ссылка на репозиторий с образом: https://hub.docker.com/r/zenhert/nginx-custom

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

Сборка образа и проверка:
```
zenhert@linpro:~/docker-nginx-custom$ docker build -t nginx-custom:1.0 .
[+] Building 14.9s (7/7) FINISHED  
 => => naming to docker.io/library/nginx-custom:1.0
 => => unpacking to docker.io/library/nginx-custom:1.0

zenhert@linpro:~/docker-nginx-custom$ docker images
IMAGE              ID             DISK USAGE   CONTENT SIZE   EXTRA
nginx-custom:1.0   1508505bd74a        102MB         28.8MB
```

Запуск контейнера и проверка страницы:
```
zenhert@linpro:~/docker-nginx-custom$ docker run -d -p 8080:80 --name my-nginx nginx-custom:1.0
bf6c3b85a1f10269391630eac726cad882f78e60072995bfb4edcd4a824d73f5
zenhert@linpro:~/docker-nginx-custom$ curl http://localhost:8080
<html><body><h1>Hello from custom nginx on Alpine</h1></body></html>
```

### 3. Определить разницу между контейнером и образом
Образ (image) — это неизменяемый шаблон, содержащий файловую систему и инструкции для запуска приложения. Это как класс в программировании.

Контейнер (container) — это запущенный экземпляр образа. Он имеет собственный слой для записи, процессы, сеть и состояние. При остановке контейнер можно удалить, а образ останется.

### 4. Можно ли в контейнере собрать ядро?
Технически возможно, но для этого нужен контейнер с установленными инструментами сборки (`gcc`, `make`, заголовки ядра) и доступом к исходникам. Также следует учесть:
  - Контейнер разделяет ядро хостовой системы, поэтому собранное ядро будет работать только на хосте или виртуальной машине, а не внутри контейнера;
  - Обычно сборка ядра в контейнере используется для воспроизводимых сборок или CI/CD.

### 5. Пуш образа в Docker Hub
Для того чтобы образ был доступен другим, необходимо пересобрать его с тэгом, содержащим логин Docker Hub, и запушить в реестр:
```
zenhert@linpro:~/docker-nginx-custom$ docker build -t zenhert/nginx-custom:1.0 .
[+] Building 14.9s (7/7) FINISHED
 => => naming to docker.io/zenhert/nginx-custom:1.0
 => => unpacking to docker.io/zenhert/nginx-custom:1.0
```

Авторизация в Docker Hub и пуш образа:
```
zenhert@linpro:~/docker-nginx-custom$ docker login -u zenhert
Login Succeeded
zenhert@linpro:~/docker-nginx-custom$ docker push zenhert/nginx-custom:1.0
The push refers to repository [docker.io/zenhert/nginx-custom]
a905c1b29240: Pushed
44136fa355b3: Pushed
850bf2dcecff: Pushed
55afa1ecc21d: Pushed
af7dd138f459: Pushed
58c524ea09ce: Pushed
bc98d7675616: Pushed
51900e10fb9c: Pushed
8f924cf5086c: Pushed
6636b9fc203c: Pushed
315bdb50ac9c: Pushed
1.0: digest: sha256:029138852166e8e7041c075465dd0881c8c7423258dc013eefc668ccdb93441f size: 856
```
Образ запушен успешно.