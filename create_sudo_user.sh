#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
    log_message "Error: Script must be run with root privileges."
    log_message "Usage: sudo $0"
    exit 1
fi

while true; do
    read -p "Enter username: " username
    
    if [[ -z "$username" ]]; then
        echo "Username not be empty!"
        continue
    fi
    
    if id "$username" &>/dev/null; then
        echo "'$username' already exist!"
        continue
    fi
    
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Incorrect username"
        continue
    fi
    
    break
done

while true; do
    read -s -p "Enter password: " userpass
    echo
    
    if [[ -z "$userpass" ]]; then
        echo "Password not be empty!"
        continue
    fi
    
    if [[ ${#userpass} -lt 6 ]]; then
        echo "Min length 6 symbols!"
        continue
    fi
    
    read -s -p "Retype password: " password_confirm
    echo
    
    if [[ "$userpass" != "$password_confirm" ]]; then
        echo "Sorry, passwords do not match"
        continue
    fi
    
    break
done

echo "Creating $username..."
useradd -m -s /bin/bash "$username" && echo "User $username created"

echo "$username:$userpass" | chpasswd && echo "Password for $username installed"

usermod -aG sudo "$username" && echo "$username added to sudo group"

echo
read -p "Allow execution sudo without pass? (y/n): " allow_nopasswd

if [[ "$allow_nopasswd" =~ ^[Yy]$ ]]; then
    echo "Add NOPASSWD to sudo..."
    if grep -q "^%sudo" /etc/sudoers; then
        sed -i 's/^%sudo.*/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
    else
        echo "%sudo ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
    fi
else
    echo "Sudo will require the password as usual"
fi

visudo -c && echo "- - - - User $username created. - - - -" || echo "Error conf sudoers"

su - $username