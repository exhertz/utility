#!/bin/bash

# Скрипт устанавливает публичный SSH-ключ для текущего пользователя
# на сервере. Создает или модифицирует ~/.ssh/authorized_keys.

# Пример использования:
# ./install_ssh_key.sh /path/to/your/key.pub

if [[ -z "$1" ]]; then
    echo "Error: The path to the SSH public key file is not specified."
    echo "Usage: $0 </path/to/your/key.pub>"
    exit 1
fi

PUBLIC_KEY_FILE="$1"

if [[ "$(id -u)" == "0" ]]; then
    echo "Error: Do not run this script as ROOT!!!"
    echo "You are now logged in as root."
    exit 1
fi

TARGET_USER=$(whoami)

echo "--- Start installing public SHH key ---"
echo "User: $TARGET_USER"

HOME_DIR=$(eval echo ~"$TARGET_USER")
SSH_DIR="$HOME_DIR/.ssh"
AUTHORIZED_KEYS_FILE="$SSH_DIR/authorized_keys"

if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
    echo "Error: File '$PUBLIC_KEY_FILE' not found."
    exit 1
fi

PUBLIC_KEY_CONTENT=$(cat "$PUBLIC_KEY_FILE")

if [[ -z "$PUBLIC_KEY_CONTENT" ]]; then
    echo "Error: The public key file is empty."
    exit 1
fi

if [[ ! -d "$SSH_DIR" ]]; then
    echo "Create dir: $SSH_DIR..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    echo "Created dir: $SSH_DIR (chmod 700)"
else
    echo "Dir $SSH_DIR already exist."
fi

if grep -qF "$PUBLIC_KEY_CONTENT" "$AUTHORIZED_KEYS_FILE" 2>/dev/null; then
    echo "The public key already exists in $AUTHORIZED_KEYS_FILE. Skip..."
else
    echo "Adding key to $AUTHORIZED_KEYS_FILE..."
    echo "$PUBLIC_KEY_CONTENT" >> "$AUTHORIZED_KEYS_FILE"
    chmod 600 "$AUTHORIZED_KEYS_FILE"
    echo "SSH key was successfully added. (chmod 600)"
fi

echo "--- Installation complete ---"