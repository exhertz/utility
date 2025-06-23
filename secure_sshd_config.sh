#!/bin/bash

# Скрипт автоматизирует смену параметров конфига SSH:
# - PubkeyAuthentication yes
# - PermitRootLogin no
# - PasswordAuthentication no
#
# Делает резервную копию, изменяет файл, 
# перезапускает службу SSH,
# проверяет примененные настройки через 'sshd -T'.
# В случае неудачи указывает на конфликтующие файлы.
#
# НЕ ЗАБУДЬТЕ УБЕДИТЬСЯ, ЧТО У ВАС ЕСТЬ АВТОРИЗАЦИЯ ПО КЛЮЧАМ ДЛЯ ОБЫЧНОГО ПОЛЬЗОВАТЕЛЯ
# ПЕРЕД ТЕМ, КАК ЗАПУСКАТЬ ЭТОТ СКРИПТ, ИНАЧЕ ВЫ МОЖЕТЕ ПОТЕРЯТЬ ДОСТУП К СЕРВЕРУ!
#
# Использование: sudo ./secure_sshd_config.sh

echo "- - - - - ATTENTION! - - - - -"
echo "This script disables SSH password authorization, which can lead to the loss of access,"
echo "if you do not have correctly configured SSH keys for login."
echo ""
echo "You've already set up and validated the SSH key for the current user ($USER)?"
read -rp "Type 'y' to continue or 'n' to exit:" user_response

user_response_lower=$(echo "$user_response" | tr '[:upper:]' '[:lower:]')

if [[ "$user_response_lower" == "y" ]]; then
    echo "Good, continue..."
elif [[ "$user_response_lower" == "n" ]]; then
    echo "Exit."
    exit 0
else
    echo "Incorrect input, exit."
    exit 1
fi

echo "------------------------------------"

SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP="${SSHD_CONFIG_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
SSHD_CONFIG_D_DIR="/etc/ssh/sshd_config.d"

declare -A TARGET_SETTINGS
TARGET_SETTINGS=(
    ["PubkeyAuthentication"]="yes"
    ["PermitRootLogin"]="no"
    ["PasswordAuthentication"]="no"
)

log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

set_config_param() {
    local param_name="$1"
    local new_value="$2"
    local config_file="$3"

    local escaped_param_name=$(printf '%s\n' "$param_name" | sed -e 's/[\/&]/\\&/g')
    local escaped_new_value=$(printf '%s\n' "$new_value" | sed -e 's/[\/&]/\\&/g')

    if grep -qE "^\s*#?\s*${escaped_param_name}\s+" "$config_file"; then
        log_message "  Replace '${param_name}' -> '${new_value}' in ${config_file}..."
        sudo sed -i -E "s/^\s*#?(${escaped_param_name})\s+.*$/\1 ${escaped_new_value}/" "$config_file"
    else
        log_message "  Add '${param_name} ${new_value}' in ${config_file}..."
        echo "${param_name} ${new_value}" | sudo tee -a "$config_file" > /dev/null
    fi
}

check_current_settings() {
    log_message "Check the current settings (sshd -T)..."
    local config_output=$(sudo sshd -T 2>&1)
    local all_applied=true

    for param_name in "${!TARGET_SETTINGS[@]}"; do
        local target_value="${TARGET_SETTINGS[$param_name]}"
        local current_value=$(echo "$config_output" | grep -Ei "^${param_name}\s+" | awk '{print $NF}')

        if [[ "$current_value" == "$target_value" ]]; then
            log_message "  [ОК] ${param_name} is '${target_value}'."
        else
            log_message "  [WARN] ${param_name} - expected '${target_value}', current '${current_value:-not found}'."
            all_applied=false
        fi
    done

    if $all_applied; then
        return 0
    else
        return 1
    fi
}

if [[ "$EUID" -ne 0 ]]; then
    log_message "Error: Script must be run with root privileges."
    log_message "Usage: sudo ./secure_sshd_config.sh"
    exit 1
fi

log_message "Starting the setup '$SSHD_CONFIG_FILE'"

if [[ ! -f "$SSHD_CONFIG_FILE" ]]; then
    log_message "Error: File '$SSHD_CONFIG_FILE' not found."
    log_message "Exit."
    exit 1
fi

log_message "Create bak file '$SSHD_CONFIG_FILE' in '$SSHD_CONFIG_BACKUP'."
sudo cp "$SSHD_CONFIG_FILE" "$SSHD_CONFIG_BACKUP"
if [[ $? -ne 0 ]]; then
    log_message "Error: A backup could not be created."
    exit 1
fi

for param_name in "${!TARGET_SETTINGS[@]}"; do
    set_config_param "$param_name" "${TARGET_SETTINGS[$param_name]}" "$SSHD_CONFIG_FILE"
done

log_message "Restart SSH service (sshd)..."
if command -v systemctl &>/dev/null; then
    sudo systemctl restart sshd
    RESTART_STATUS=$?
else # для старых систем без systemd
    sudo service sshd restart
    RESTART_STATUS=$?
fi

if [[ $RESTART_STATUS -ne 0 ]]; then
    log_message "Error: The SSH service could not be restarted. Check the logs."
    exit $RESTART_STATUS
fi
log_message "GOOD!"

sleep 2 # немного времени для полного старта
if check_current_settings; then
    log_message "All SSH target settings have been successfully applied."
    log_message "The SSH setup is complete."
else
    log_message "WARNING: Not all settings were successfully applied."
    log_message "Probably overrides in other configuration files, syntax errors."

    if [[ -d "$SSHD_CONFIG_D_DIR" ]]; then
        log_message "Dir '$SSHD_CONFIG_D_DIR':"
        find "$SSHD_CONFIG_D_DIR" -type f -name "*.conf" 2>/dev/null | while read -r f; do
            log_message "  - $f"
        done
        if ! find "$SSHD_CONFIG_D_DIR" -type f -name "*.conf" -print -quit | grep -q .; then
             log_message "  (The directory exists, but does not contain any files .conf)"
        fi
    else
        log_message "Dir '$SSHD_CONFIG_D_DIR' not found!"
    fi

    log_message "It is recommended to check the '$SSHD_CONFIG_FILE' file manually and all files in '$SSHD_CONFIG_D_DIR'."
    log_message "Use 'sudo sshd -t' to check the syntax of the '$SSHD_CONFIG_FILE' file."
fi

log_message "The script has completed"
