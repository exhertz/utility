#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
    log_message "Error: Script must be run with root privileges."
    log_message "Usage: sudo $0"
    exit 1
fi

echo "Install fail2ban..."
apt update && apt install -y fail2ban

echo "Setup jail.local..."
cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
backend = systemd
maxretry = 3
findtime = 1h
bantime = 7d
EOF

echo "Restart fail2ban..."
systemctl restart fail2ban

echo "Check status fail2ban..."
systemctl status fail2ban --no-pager

echo "Current bans:"
fail2ban-client status sshd

echo "- - - - Setup fail2ban complete! - - - -"