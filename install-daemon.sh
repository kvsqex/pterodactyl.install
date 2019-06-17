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
VERSION="$(get_latest_release "pterodactyl/daemon")"

DL_URL="https://github.com/pterodactyl/daemon/releases/download/$VERSION/daemon.tar.gz"
CONFIGS_URL="https://raw.githubusercontent.com/kvsqex/pterodactyl.install/master/configs"

OS="debian"

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
    if [ "$OS_VERSION" == "9" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "centos" ]; then
    if [ "$OS_VERSION" == "7" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  else
    SUPPORTED=false
  fi

  # exit if not supported
  if [ "$SUPPORTED" == true ]; then
    echo "* $OS $OS_VERSION поддерживается."
  else
    echo "* $OS $OS_VERSION не поддерживается"
    print_error "Неподдерживаемая система"
    exit 1
  fi
}

############################
##    Установка функций   ##
############################
function yum_update {
  yum update -y
}

function apt_update {
  apt update -y
  apt upgrade -y
}

function install_dep {
  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    apt_update

    apt -y install tar unzip make gcc g++ python
  elif [ "$OS" == "centos" ]; then
    yum_update

    yum -y install tar unzip make gcc
    yum -y install gcc-c++
  else
    print_error "Неправильная система."
    exit 1
  fi
}
function install_docker {
  echo "* Установка docker .."
  if [ "$OS" == "debian" ]; then
    apt-get update
    apt-get -y install \
     apt-transport-https \
     ca-certificates \
     curl \
     gnupg2 \
     software-properties-common

    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -

    apt-key fingerprint 0EBFCD88

    sudo add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/debian \
      $(lsb_release -cs) \
      stable"

    apt-get update
    apt-get -y install docker-ce

    systemctl start docker
    systemctl enable docker

  elif [ "$OS" == "ubuntu" ]; then
    apt-get update
    apt-get -y install \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    apt-key fingerprint 0EBFCD88

    sudo add-apt-repository \
     "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
     $(lsb_release -cs) \
     stable"

    apt-get update
    apt-get -y install docker-ce

    systemctl start docker
    systemctl enable docker

  elif [ "$OS" == "centos" ]; then
    yum install -y yum-utils \
      device-mapper-persistent-data \
      lvm2

    yum-config-manager \
      --add-repo \
      https://download.docker.com/linux/centos/docker-ce.repo

    yum install -y docker-ce

    systemctl start docker
    systemctl enable docker
  fi

  echo "* Docker успешно установлен!"
}

function install_nodejs {
  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
    apt -y install nodejs
  elif [ "$OS" == "centos" ]; then
    curl --silent --location https://rpm.nodesource.com/setup_8.x | sudo bash -
    yum -y install nodejs
  fi
}

function ptdl_dl {
  echo "* Установка daemon .. "
  mkdir -p /srv/daemon /srv/daemon-data
  cd /srv/daemon

  curl -L $DL_URL | tar --strip-components=1 -xzv
  npm install --only=production

  echo "* Успешно."
}

function systemd_file {
  echo "* Установка systemd сервисов.."
  curl -o /etc/systemd/system/wings.service $CONFIGS_URL/wings.service
  systemctl daemon-reload
  systemctl enable wings
  echo "* Установка systemd успешно завершена!"
}

####################
##ГЛАВНЫЕ ФУНКЦИИ ##
####################
function perform_install {
  echo "* Установка daemon.."
  install_dep
  install_docker
  install_nodejs
  ptdl_dl
  systemd_file
}

function main {
  print_brake 42
  echo "* Установочный скрипт Pterodactyl.io"
  echo "* Обнаружение операционной системы."
  OS=$(detect_distro);
  OS_VERSION=$(detect_os_version);
  echo "* Запуск $OS версии $OS_VERSION."
  print_brake 42

  check_os_comp

  echo "* Установщик установит Docker и все необходимые зависимости для daemon"
  echo "* а также сам daemon."
  echo "* Больше информации здесь:"
  echo "* https://pterodactyl.io/daemon/installing.html#configure-daemon"
  print_brake 42
  echo -n "* Продолжить установку? (y/n): "

  read CONFIRM

  if [ "$CONFIRM" == "y" ]; then
    perform_install
  elif [ "$CONFIRM" == "n" ]; then
    exit 0
  else
    print_error "Неправильный ответ"
    exit 1
  fi
}

function goodbye {
  echo ""
  print_brake 70
  echo "* Установка завершена."
  echo ""
  echo "* Убедитесь, что вы создали узел внутри панели, а затем "
  echo "* скопируйте конфиг в узле. Затем вы можете запустить daemon, используя команду: "
  echo "* systemctl start wings"
  echo "* [ ! ] Рекомендуется также включить swap."
  print_brake 70
  echo ""
}

main
goodbye