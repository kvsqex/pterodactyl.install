#!/bin/bash
###########################################################
# https://github.com/kvsqex/pterodactyl.install
###########################################################

if [[ $EUID -ne 0 ]]; then
  echo "* Этот скрипт должен быть выполнен с правами суперпользователя (sudo)." 1>&2
  exit 1
fi

CURLPATH="$(which curl)"
if [ -z "$CURLPATH" ]; then
    echo "* установите curl."
    echo "* установите apt на Debian/Ubuntu и yum на CentOS"
    exit 1
fi

PYTHONPATH="$(which python)"
if [ -z "$PYTHONPATH" ]; then
    echo "* Для работы скрипта требуется python."
    echo "* установите apt на Debian/Ubuntu и yum на CentOS"
    exit 1
fi

get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | 
    grep '"tag_name":' |                                            
    sed -E 's/.*"([^"]+)".*/\1/'                                    
}

echo "* Получение информации о версиях.."
VERSION="$(get_latest_release "pterodactyl/panel")"

WEBSERVER="nginx"
OS="debian" # can
FQDN="pterodactyl.panel"

MYSQL_DB="pterodactyl"
MYSQL_USER="pterodactyl"
MYSQL_PASSWORD="somePassword"

ASSUME_SSL=false

PANEL_URL="https://github.com/pterodactyl/panel/releases/download/$VERSION/panel.tar.gz"
CONFIGS_URL="https://raw.githubusercontent.com/kvsqex/pterodactyl.install/master/configs"

SOURCES_PATH="/etc/apt/sources.list"

function print_error {
  COLOR_RED='\033[0;31m'
  COLOR_NC='\033[0m'

  echo ""
  echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
  echo ""
}

function print_brake {
  for ((n=0;n<$1;n++));
    do
      echo -n "#"
    done
    echo ""
}

function detect_distro {
  echo "$(python -c 'import platform ; print platform.dist()[0]')" | awk '{print tolower($0)}'
}

function detect_os_version {
  echo "$(python -c 'import platform ; print platform.dist()[1].split(".")[0]')"
}

function check_os_comp {
  if [ "$OS" == "ubuntu" ]; then
    if [ "$OS_VERSION" == "16" ]; then
      SUPPORTED=true
    elif [ "$OS_VERSION" == "18" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "debian" ]; then
    if [ "$OS_VERSION" == "8" ]; then
      SUPPORTED=true
    elif [ "$OS_VERSION" == "9" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "centos" ]; then
    if [ "$OS_VERSION" == "7" ]; then
      SUPPORTED=false
    else
      SUPPORTED=false
    fi
  else
    SUPPORTED=true
  fi

  if [ "$SUPPORTED" == true ]; then
    echo "* $OS $OS_VERSION поддерживается."
  else
    echo "* $OS $OS_VERSION не поддерживается"
    print_error "Неподдерживаемая система"
    exit 1
  fi
}

#################################
##    установочные функции     ##
#################################

function install_composer {
  echo "* Установка composer.."
  curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
  echo "* Composer установлен!"
}

function ptdl_dl {
  echo "* Скачивание файлов панели .. "
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl

  curl -Lo panel.tar.gz $PANEL_URL
  tar --strip-components=1 -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env
  composer install --no-dev --optimize-autoloader

  php artisan key:generate --force
  echo "* Установка панели и запуск composer завершено!"
}

function configure {
  print_brake 88
  echo "* Пожалуйста, следуйте инструкциям ниже. Установщик спросит вас о деталях конфигурации."
  print_brake 88
  echo ""
  php artisan p:environment:setup

  print_brake 67
  echo "* Теперь установщик запросит учетные данные базы данных MySQL."
  print_brake 67
  echo ""
  php artisan p:environment:database

  print_brake 70
  echo "* Теперь установщик запросит у вас настройки почты / учетные данные."
  print_brake 70
  echo ""
  php artisan p:environment:mail

  php artisan migrate --seed

  echo "* Теперь установщик попросит вас создать начальную учетную запись администратора."
  php artisan p:user:make

  set_folder_permissions
}

function set_folder_permissions {
  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    chown -R www-data:www-data *
  elif [ "$OS" == "centos" ] && [ "$WEBSERVER" == "nginx" ]; then
    chown -R nginx:nginx *
  elif [ "$OS" == "centos" ] && [ "$WEBSERVER" == "apache" ]; then
    chown -R apache:apache *
  else
    print_error "Неправильная настройка системы."
    exit 1
  fi
}

function insert_cronjob {
  echo "* Установка cronjob.. "

  crontab -l | { cat; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"; } | crontab -

  echo "* Cronjob установлен!"
}

function install_pteroq {
  echo "* Установка pteroq сервисов.."

  curl -o /etc/systemd/system/pteroq.service $CONFIGS_URL/pteroq.service
  systemctl enable pteroq.service
  systemctl start pteroq

  echo "* Pteroq установлен!"
}

function create_database {
  if [ "$OS" == "centos" ]; then
    mysql_secure_installation
  fi

  echo "* Создание MySQL базы и пользователя.."
  echo "* Сценарий должен был попросить вас установить корневой пароль MySQL ранее (не путать с паролем пользователя базы данных птеродактиля)"
  echo "* MySQL теперь попросит вас вводить пароль перед каждой командой."

  echo "* Выполнение запросов MySQL.."

  echo "* Create MySQL user."
  mysql -u root -p -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"

  echo "* Create database."
  mysql -u root -p -e "CREATE DATABASE ${MYSQL_DB};"

  echo "* Grant privileges."
  mysql -u root -p -e "GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"

  echo "* Flush privileges."
  mysql -u root -p -e "FLUSH PRIVILEGES;"

  echo "* MySQL база создана и настроена!"
}

##################################
#Специальные функции для системы##
##################################

function apt_update {
  apt update -y && apt upgrade -y
}

function ubuntu18_dep {
  echo "* Установка зависимостей для Ubuntu 18.."

  apt -y install software-properties-common

  add-apt-repository -y ppa:chris-lea/redis-server
  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  apt update

  apt -y install php7.2 php7.2-cli php7.2-gd php7.2-mysql php7.2-pdo php7.2-mbstring php7.2-tokenizer php7.2-bcmath php7.2-xml php7.2-fpm php7.2-curl php7.2-zip mariadb-server nginx curl tar unzip git redis-server

  echo "* Зависимости для Ubuntu установлены!"
}

function ubuntu16_dep {
  echo "* Установка зависимостей для Ubuntu 16.."

  apt -y install software-properties-common

  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
  add-apt-repository -y ppa:chris-lea/redis-server
  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  apt update

  apt -y install php7.2 php7.2-cli php7.2-gd php7.2-mysql php7.2-pdo php7.2-mbstring php7.2-tokenizer php7.2-bcmath php7.2-xml php7.2-fpm php7.2-curl php7.2-zip mariadb-server nginx curl tar unzip git redis-server

  echo "* Зависимости для Ubuntu установлены!"
}

function debian_dep {
  echo "* Установка зависимостей для Debian.."

  apt -y install dirmngr
 
  apt install ca-certificates apt-transport-https lsb-release -y
  sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list

  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  apt update

  apt -y install php7.2 php7.2-cli php7.2-gd php7.2-mysql php7.2-pdo php7.2-mbstring php7.2-tokenizer php7.2-bcmath php7.2-xml php7.2-fpm php7.2-curl php7.2-zip mariadb-server nginx curl tar unzip git redis-server

  echo "* Зависимости для Debian установлены!"
}

function centos_dep {
  echo "* Установка зависимостей для CentOS.."

  yum update -y

  yum install -y epel-release https://centos7.iuscommunity.org/ius-release.rpm
  yum -y install yum-utils
  yum update -y

  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  yum -y install install php72u-php php72u-common php72u-fpm php72u-cli php72u-json php72u-mysqlnd php72u-mcrypt php72u-gd php72u-mbstring php72u-pdo php72u-zip php72u-bcmath php72u-dom php72u-opcache mariadb-server nginx curl tar unzip git redis

  systemctl enable mariadb
  systemctl enable redis
  systemctl enable php-fpm.service
  systemctl start mariadb
  systemctl start redis
  systemctl start php-fpm.service


  echo "* Зависимости для CentOS установлены!"
}

#################################
## Другие специальные функции  ##
#################################

function ubuntu_universedep {
  if grep -q universe "$SOURCES_PATH"; then
    add-apt-repository universe
    echo "* Ubuntu universe репозиторий уже существует."
  else
    add-apt-repository universe
  fi
}


#######################################
##         Настройка веб-части       ##
#######################################

function configure_nginx {
  echo "* Настройка nginx .."

  if [ "$ASSUME_SSL" == true ]; then
    DL_FILE="nginx_ssl.conf"
  else
    DL_FILE="nginx.conf"
  fi

  if [ "$OS" == "centos" ]; then

      rm -rf /etc/nginx/conf.d/default

      curl -o /etc/nginx/conf.d/pterodactyl.conf $CONFIGS_URL/$DL_FILE

      sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/conf.d/pterodactyl.conf
  else

      rm -rf /etc/nginx/sites-enabled/default

      curl -o /etc/nginx/sites-available/pterodactyl.conf $CONFIGS_URL/$DL_FILE

      sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf

      sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  fi

  systemctl restart nginx
  echo "* nginx настроен!"
}

function configure_apache {
  echo "скоро .."
}

####################
##ГЛАВНЫЕ ФУНКЦИИ ##
####################

function perform_install {
  echo "* Запуск установки .. это может занять некоторое время!"
  
  if [ "$OS" == "ubuntu" ]; then
    ubuntu_universedep
    apt_update
    
    if [ "$OS_VERSION" == "18" ]; then
      ubuntu18_dep
    elif [ "$OS_VERSION" == "16" ]; then
      ubuntu16_dep
    else
      print_error "Неподдерживаемая версия Ubuntu."
      exit 1
    fi
    install_composer
    ptdl_dl
    create_database
    configure
    insert_cronjob
    install_pteroq
  elif [ "$OS" == "debian" ]; then
    apt_update
    debian_dep
    install_composer
    ptdl_dl
    create_database
    configure
    insert_cronjob
    install_pteroq
  elif [ "$OS" == "centos" ]; then
    centos_dep
    install_composer
    ptdl_dl
    create_database
    configure
    insert_cronjob
    install_pteroq
  else
    # exit
    print_error "Система не поддерживается."
    exit 1
  fi

  if [ "$WEBSERVER" == "nginx" ]; then
    configure_nginx
  elif [ "$WEBSERVER" == "apache" ]; then
    configure_apache
  else
    print_error "Неподдерживаемый сервер."
    exit 1
  fi

}

function main {
  print_brake 40
  echo "* Установочный скрипт Pterodactyl.io"
  echo "* Обнаружение операционной системы."
  OS=$(detect_distro);
  OS_VERSION=$(detect_os_version)
  echo "* Запуск $OS версии $OS_VERSION."
  print_brake 40

  check_os_comp

  echo -n "* Продолжить установку панели? (y/n) "
  read WEBSERVER_INPUT

  if [ "$WEBSERVER_INPUT" == "y" ]; then
    WEBSERVER="nginx"
  else
    # exit
    print_error "Неподдерживаемый сервер."
    main
  fi

  print_brake 72
  echo "* Настройка базы данных."
  echo ""
  echo "* Это будут учетные данные, используемые для связи между MySQL"
  echo "* базами данных и панелью. Вам не нужно создавать базу данных"
  echo "* перед запуском этого скрипта, скрипт сделает это за вас."
  echo ""

  echo -n "* Имя базы (panel): "
  read MYSQL_DB_INPUT

  if [ -z "$MYSQL_DB_INPUT" ]; then
    MYSQL_DB="panel"
  else
    MYSQL_DB=$MYSQL_DB_INPUT
  fi

  echo -n "* Пользователь (pterodactyl): "
  read MYSQL_USER_INPUT

  if [ -z "$MYSQL_USER_INPUT" ]; then
    MYSQL_USER="pterodactyl"
  else
    MYSQL_USER=$MYSQL_USER_INPUT
  fi

  echo -n "* Пароль (используйте сложный): "
  read MYSQL_PASSWORD

  if [ -z "$MYSQL_PASSWORD" ]; then
    print_error "MySQL пароль не может быть пустым"
    exit 1
  fi

  print_brake 72

  echo -n "* Установите полное доменное имя этой панели (имя хоста панели): "
  read FQDN

  echo ""

  echo "* Этот установщик не настраивает Let's Encrypt, но в зависимости от того,"
  echo "* будем использовать SSL или нет, нам нужно знать, какую конфигурацию веб-сервера использовать."
  echo "* Если вы не уверены, используйте (no). "
  echo -n "* Использователь SSL или нет? (yes/no): "
  read ASSUME_SSL_INPUT

  if [ "$ASSUME_SSL_INPUT" == "yes" ]; then
    ASSUME_SSL=true
  elif [ "$ASSUME_SSL_INPUT" == "no" ]; then
    ASSUME_SSL=false
  else
    print_error "Неверный ответ. SSL был отключен."
    ASSUME_SSL=false
  fi

  echo -e -n "\n* Начальная настройка сделана. Вы хотите продолжить установку? (y/n): "
  read CONFIRM
  if [ "$CONFIRM" == "y" ]; then
    perform_install
  elif [ "$CONFIRM" == "n" ]; then
    exit 0
  else
    print_error "Неверное подтверждение. Выходим."
    exit 1
  fi

}

function goodbye {
  print_brake 62
  echo "* Pterodactyl панель успешно установлена @ $FQDN"
  echo ""
  echo "* Установка использует $WEBSERVER на $OS"
  print_brake 62

  exit 0
}

main
goodbye