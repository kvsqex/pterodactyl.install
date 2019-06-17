# Установщик

PTEROQ.install - авто-установщик панели Pterodactyl.io

Ссылка на ручную установку [тык](https://pterodactyl.io/project/introduction.html).

# Список поддерживаемых систем

### Панель

|      Система      | Версия  | Поддержка nginx    | Поддержка Apache |
| ----------------- | ------- | ------------------ | ---------------- |
| CentOS            | 7       | :red_circle:       | :red_circle:     |
| Ubuntu            | 14.04   | :red_circle:       | :red_circle:     |
|                   | 16.04   | :white_check_mark: | :red_circle:     |
|                   | 18.04   | :white_check_mark: | :red_circle:     |
| Debian            | 8       | :white_check_mark: | :red_circle:     |
|                   | 9       | :white_check_mark: | :red_circle:     |

### Daemon

|      Система      | Версия  | Поддержка          |
| ----------------- | ------- | ------------------ |
| CentOS            | 6       | :red_circle:       |
|                   | 7       | :white_check_mark: |
| Ubuntu            | 14.04   | :red_circle:       |
|                   | 16.04   | :white_check_mark: |
|                   | 18.04   | :white_check_mark: |
| Debian            | 8       | :red_circle:       |
|                   | 9       | :white_check_mark: |

# Инструкция

Запуск установки панели:

`bash <(curl -s https://raw.githubusercontent.com/kvsqex/pterodactyl.install/master/install-panel.sh)`

Запуск установки daemon:

`bash <(curl -s https://raw.githubusercontent.com/kvsqex/pterodactyl.install/master/install-daemon.sh)`

*[ ! ] Для запуска скрипта нужно иметь root доступ.*
