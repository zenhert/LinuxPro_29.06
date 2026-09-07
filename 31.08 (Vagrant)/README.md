# Отчёт по домашнему заданию по практике с Vagrant (31.08)

- **Автор:** Павлов Сергей
- **Дата выполнения:** 07.09.2026
- **Задание:** 
  - Подготовка окружения:
    - Убедитесть, что установлен VirtualBox и Vagrant;
    - Создайте директорию для проекта.
  - Создать базовую виртуальную машину:
    - Использовать можно любой образ;
    - Настройте память ВМ: 1024 МБ.
  - Добавление дисков:
    - Добавьте пару виртуальных дисков размером 1 ГБ каждый.
  - Настройка сети:
    - Настройте проброс 80 порта с гостевой системы на порт 8080 хостовой системы.
  - Провижининг - напишите провижининг, который:
    - Форматирует добавленные диски в файловую систему ext4;
    - Создает точки монтирования /mnt/disk1 и /mnt/disk2;
    - Монтирует диски в указанные директории;
    - Добавляет записи в /etc/fstab для автоматического монтирования при загрузке.

---

## Исходное состояние

- VMWare ESXI
- Хостовая ОС: Ubuntu 24.04.1 LTS 
- ВМ с Vagrant на Ubuntu 24.04.1 LTS

---

## Ход работы

### 1. Подготовка окружения
Проверка наличия необходимого ПО:
```
zenhert@linpro:~$ vagrant --version
Vagrant 2.4.9
zenhert@linpro:~$ VBoxManage --version
7.0.16_Ubuntur162802
```

Создание директории проекта:
```
zenhert@linpro:~$ mkdir ~/vagrant_disks_network
zenhert@linpro:~$ cd ~/vagrant_disks_network/
```

### 2. Создать базовую ВМ

Создание `Vagrantfile`:
```
nano Vagrantfile
```
```
Vagrant.configure("2") do |config|
  # Ubuntu 2204
  config.vm.box = "generic/ubuntu2204"
  config.vm.hostname = "disknet"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
    vb.cpus = 1

    # Добавление пары дисков по 1 ГБ
    vb.customize ["createhd", "--filename", "disk1.vdi", "--size", 1024]
    vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 1, "--device", 0, "--type", "hdd", "--medium", "disk1.vdi"]

    vb.customize ["createhd", "--filename", "disk2.vdi", "--size", 1024]
    vb.customize ["storageattach", :id, "--storagectl", "SATA Controller", "--port", 2, "--device", 0, "--type", "hdd", "--medium", "disk2.vdi"]
  end

  # Проброс порта HTTP на localhost:8080
  config.vm.network "forwarded_port",
                     guest: 80,
                     host: 8080

  # Провижининг
  config.vm.provision "shell", inline: <<-SHELL
    # Создание точки монтирования
    mkdir -p /mnt/disk1 /mnt/disk2

    # Форматирование дисков, если ещё не отформатированы
    if ! blkid /dev/sdb; then
      mkfs.ext4 /dev/sdb
    fi
    if ! blkid /dev/sdc; then
      mkfs.ext4 /dev/sdc
    fi

    # Монтирование
    mount /dev/sdb /mnt/disk1
    mount /dev/sdc /mnt/disk2

    # Добавление в fstab
    echo '/dev/sdb /mnt/disk1 ext4 defaults 0 0' >> /etc/fstab
    echo '/dev/sdc /mnt/disk2 ext4 defaults 0 0' >> /etc/fstab

    # Установка nginx для проверки проброса порта
    apt-get update
    apt-get install -y nginx

    # Запуск nginx
    systemctl enable nginx
    systemctl start nginx
  SHELL
end
```

Запуск ВМ и проверка:
```
zenhert@linpro:~/vagrant_disks_network$ vagrant up
zenhert@linpro:~/vagrant_disks_network$ vagrant status
Current machine states:

default                   running (virtualbox)

The VM is running.
```

### 3. Добавление дисков
Проверка монтирования дисков:
```
zenhert@linpro:~/vagrant_disks_network$ vagrant ssh
vagrant@disknet:~$ df -h
Filesystem                         Size  Used Avail Use% Mounted on
tmpfs                               96M  952K   95M   1% /run
/dev/mapper/ubuntu--vg-ubuntu--lv   62G  5.2G   54G   9% /
tmpfs                              479M     0  479M   0% /dev/shm
tmpfs                              5.0M     0  5.0M   0% /run/lock
/dev/sda2                          2.0G  234M  1.6G  13% /boot
/dev/sdb                           974M   24K  907M   1% /mnt/disk1
/dev/sdc                           974M   24K  907M   1% /mnt/disk2
tmpfs                               96M  4.0K   96M   1% /run/user/1000
```
Диски примонтированы успешно: `/dev/sdb` и `/dev/sdc`

### 4. Настройка сети
Проверка проброса порта:
```
zenhert@linpro:~/vagrant_disks_network$ netstat -tulpn | grep 8080
(Not all processes could be identified, non-owned process info
 will not be shown, you would have to be root to see it all.)
tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      -
```
Порт слушается, также открывается страничка `nginx`:
```
zenhert@linpro:~/vagrant_disks_network$ curl http://localhost:8080
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```