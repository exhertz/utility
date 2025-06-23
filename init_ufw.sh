#!/bin/bash

# Скрипт автоматизирует установку и базовую настройку UFW.
# Интерактивно запрашивает у пользователя порты
#
# Использование: sudo ./init_ufw.sh

DEFAULT_SSH_PORT="22"
DEFAULT_HTTP_PORT="80"
DEFAULT_HTTPS_PORT="443"

log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# получения ввода с /dev/tty
# $1: сообщениеподсказка
# $2: значение по умолчанию (если пусто, то нет значения по умолчанию)
# $3 (опционально): тип ожидаемого ввода (port для проверки числа)
get_user_input() {
    local prompt_msg="$1"
    local default_val="$2"
    local input_type="$3"
    local user_input=""

    while true; do
        if [[ -n "$default_val" ]]; then
            read -rp "$prompt_msg (default: $default_val): " user_input < /dev/tty || { log_message "Error read input."; exit 1; }
        else
            read -rp "$prompt_msg: " user_input < /dev/tty || { log_message "Error read input."; exit 1; }
        fi

        user_input=$(echo "$user_input" | tr -d '[:space:]')
        if [[ -z "$user_input" && -n "$default_val" ]]; then
            echo "$default_val"
            break
        elif [[ -z "$user_input" && -z "$default_val" ]]; then
            log_message "  The input cannot be empty. Please enter value."
        elif [[ "$input_type" == "port" ]]; then
            if [[ "$user_input" =~ ^[0-9]+$ ]] && (( user_input >= 1 && user_input <= 65535 )); then
                echo "$user_input"
                break
            else
                log_message "  Incorrect port. Enter 1 - 65535."
            fi
        else
            echo "$user_input"
            break
        fi
    done
}

if [[ "$EUID" -ne 0 ]]; then
    log_message "Error: Script must be run with root privileges."
    log_message "Usage: sudo $0"
    exit 1
fi

log_message "Starting UFW setup..."

if ! command -v ufw &>/dev/null; then
    log_message "UFW not installed. Install..."
    sudo apt update
    sudo apt install -y ufw
    if [[ $? -ne 0 ]]; then
        log_message "Error: It was possible to install UFW. Check your internet connection or repositories."
        exit 1
    fi
    log_message "UFW installed."
else
    log_message "UFW already installed."
fi

log_message ""
SSH_PORT=$(get_user_input "Enter SSH port:" "$DEFAULT_SSH_PORT" "port")
log_message "ufw allow tcp to: $SSH_PORT"

log_message ""
HTTPS_CHOICE=$(get_user_input "Open HTTPS port (443)? (y/n/your_port_number)" "n")
HTTPS_PORT=""
if [[ $(echo "$HTTPS_CHOICE" | tr '[:upper:]' '[:lower:]') == "y" ]]; then
    HTTPS_PORT="$DEFAULT_HTTPS_PORT"
    log_message "ufw allow to HTTPS (443)"
elif [[ "$HTTPS_CHOICE" =~ ^[0-9]+$ ]] && (( HTTPS_CHOICE >= 1 && HTTPS_CHOICE <= 65535 )); then
    HTTPS_PORT="$HTTPS_CHOICE"
    log_message "ufw allow to HTTPS: $HTTPS_PORT."
else
    log_message "The HTTPS port will not be opened."
fi

log_message ""
HTTP_CHOICE=$(get_user_input "Open HTTP port (80)? (y/n/your_port_number)" "n")
HTTP_PORT=""
if [[ $(echo "$HTTP_CHOICE" | tr '[:upper:]' '[:lower:]') == "y" ]]; then
    HTTP_PORT="$DEFAULT_HTTP_PORT"
    log_message "ufw allow to HTTP (80)."
elif [[ "$HTTP_CHOICE" =~ ^[0-9]+$ ]] && (( HTTP_CHOICE >= 1 && HTTP_CHOICE <= 65535 )); then
    HTTP_PORT="$HTTP_CHOICE"
    log_message "ufw allow to HTTP: $HTTP_PORT."
else
    log_message "The HTTP port will not be opened."
fi

log_message ""
sudo ufw default deny incoming
log_message "Default policy: Deny inbound connections."
sudo ufw default allow outgoing
log_message "Default policy: Allow outbound connections."

sudo ufw allow "$SSH_PORT"/tcp

if [[ -n "$HTTPS_PORT" ]]; then
    sudo ufw allow "$HTTPS_PORT"/tcp
fi

if [[ -n "$HTTP_PORT" ]]; then
    sudo ufw allow "$HTTP_PORT"/tcp
fi

log_message ""
if [[ "$(sudo ufw status | grep Status)" =~ "inactive" ]]; then
    log_message "UFW is inactive. Activate UFW. This may interrupt your connection temporarily."
    log_message "Press 'y' to confirm activation, or 'n' to cancel."
    read -rp "Continue? (y/n): " confirm_activate < /dev/tty || { log_message "Error read input."; exit 1; }
    if [[ $(echo "$confirm_activate" | tr '[:upper:]' '[:lower:]') == "y" ]]; then
        sudo ufw enable
        if [[ $? -ne 0 ]]; then
            log_message "Error: UFW could not be activated. Check the logs."
            exit 1
        fi
        log_message "UFW activated."
    else
        log_message "UFW activation canceled. The rules are saved, but the firewall is not active."
    fi
else
    log_message "UFW is already active. The rules have been applied."
fi

log_message ""
log_message "- - -  UFW status - - -"
sudo ufw status verbose

log_message ""
log_message "The UFW setup is complete."
