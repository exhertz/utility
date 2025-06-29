#!/bin/bash

# WireGuard Server Setup Script (FIXED VERSION)
# Author: Assistant
# Description: Sets up a VPN server with proper UFW configuration

set -e

LOG_FILE="/var/log/wireguard-server.log"

# Configuration
WG_PORT=30000
WG_INTERFACE="wg0"
WG_NET="10.0.0.0/24"
WG_SERVER_IP="10.0.0.1"
WG_CLIENT_IP="10.0.0.2"

# SSH Forwarding configuration
SSH_FORWARD_IP1="192.168.10.100"
SSH_FORWARD_IP2="192.168.10.200"
SSH_FORWARD_PORT1="22100"
SSH_FORWARD_PORT2="22200"

MONITOR_NAME="wg-server-monitor.sh"
MONITOR_PATH="/usr/local/bin/$MONITOR_NAME"
MONITOR_SOURCE_URL="https://exhertz.github.io/utility/wg/wg-server-monitor.sh"
CONTROL_NAME="wg-server-control.sh"
CONTROL_PATH="/usr/local/bin/$CONTROL_NAME"
CONTROL_SOURCE_URL="https://exhertz.github.io/utility/wg/wg-server-control.sh"

log() {
  local message="$1"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $1"
    exit 1
}

warn() {
    echo "[WARNING] $1"
}

if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root."
fi

log "Starting WireGuard server setup..."

# Update system and install packages
log "Updating system and installing necessary packages..."
apt update
apt install -y wireguard wireguard-tools ufw cron curl

# КРИТИЧНО: Сначала настроим UFW правильно, чтобы не потерять SSH
log "Configuring UFW with safe defaults..."

# Сбросить UFW к дефолтным настройкам
ufw --force reset

# Установить базовые правила
ufw default deny incoming
ufw default allow outgoing
ufw default allow routed

# ОБЯЗАТЕЛЬНО разрешить SSH ПЕРВЫМ делом
ufw allow 22/tcp comment 'SSH access'

# Разрешить WireGuard порт
ufw allow $WG_PORT/udp comment 'WireGuard'

# Разрешить дополнительные SSH порты для перенаправления
ufw allow $SSH_FORWARD_PORT1/tcp comment 'SSH redirect VM100'
ufw allow $SSH_FORWARD_PORT2/tcp comment 'SSH redirect VM200'

# Включить UFW только после настройки всех правил
ufw --force enable

log "UFW configured safely with SSH access preserved"

# Enable and start cron service
systemctl enable cron
systemctl start cron

# Determine external IP
log "Determining external IP address..."
EXTERNAL_IP=$(curl -4 -s ifconfig.me || curl -4 -s ipecho.net/plain || curl -4 -s icanhazip.com || ip -4 route get 8.8.8.8 | grep -oP 'src \K\S+')
if [[ -z "$EXTERNAL_IP" ]]; then
    error "Failed to determine external IP address."
fi
log "External IP: $EXTERNAL_IP"

# Determine main network interface
log "Determining main network interface..."
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [[ -z "$MAIN_INTERFACE" ]]; then
    error "Failed to determine main network interface."
fi
log "Main interface: $MAIN_INTERFACE"

# Enable IP forwarding
log "Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1

# Create directory for configurations
mkdir -p /etc/wireguard

# Generate server keys
log "Generating server keys..."
cd /etc/wireguard
wg genkey | tee server_private.key | wg pubkey > server_public.key
SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# Generate client keys
log "Generating client keys..."
wg genkey | tee client_private.key | wg pubkey > client_public.key
CLIENT_PRIVATE_KEY=$(cat client_private.key)
CLIENT_PUBLIC_KEY=$(cat client_public.key)

# Create server configuration
# PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
# PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
log "Creating server configuration..."
cat > /etc/wireguard/$WG_INTERFACE.conf << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
SaveConfig = false

PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE; iptables -t nat -A PREROUTING -i $MAIN_INTERFACE -p tcp --dport 22100 -j DNAT --to-destination 192.168.10.100:22; iptables -t nat -A PREROUTING -i $MAIN_INTERFACE -p tcp --dport 22200 -j DNAT --to-destination 192.168.10.200:22
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE; iptables -t nat -D PREROUTING -i $MAIN_INTERFACE -p tcp --dport 22100 -j DNAT --to-destination 192.168.10.100:22; iptables -t nat -D PREROUTING -i $MAIN_INTERFACE -p tcp --dport 22200 -j DNAT --to-destination 192.168.10.200:22

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $WG_CLIENT_IP/32, 192.168.10.0/24
EOF

# Create client configuration
log "Creating client configuration..."
cat > /etc/wireguard/client.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $WG_CLIENT_IP/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $EXTERNAL_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Set file permissions
chmod 600 /etc/wireguard/*.conf
chmod 600 /etc/wireguard/*.key

# Configure UFW for WireGuard traffic forwarding (ПОСЛЕ основных правил)
log "Configuring UFW forwarding rules..."

# Добавить правила форвардинга в UFW конфиг
UFW_BEFORE_RULES="/etc/ufw/before.rules"

# Создать бэкап
cp $UFW_BEFORE_RULES $UFW_BEFORE_RULES.backup

# Добавить NAT правила для SSH и WireGuard в начало файла, но ОСТОРОЖНО
if ! grep -q "NAT rules for SSH port forwarding" $UFW_BEFORE_RULES; then
    sed -i '10i\
# NAT rules for SSH port forwarding\
*nat\
:PREROUTING ACCEPT [0:0]\
-A PREROUTING -i '$MAIN_INTERFACE' -p tcp --dport '$SSH_FORWARD_PORT1' -j DNAT --to-destination '$SSH_FORWARD_IP1':22\
-A PREROUTING -i '$MAIN_INTERFACE' -p tcp --dport '$SSH_FORWARD_PORT2' -j DNAT --to-destination '$SSH_FORWARD_IP2':22\
COMMIT\
\
# NAT rules for WireGuard\
*nat\
:POSTROUTING ACCEPT [0:0]\
-A POSTROUTING -s '$WG_NET' -o '$MAIN_INTERFACE' -j MASQUERADE\
COMMIT\
' $UFW_BEFORE_RULES

    log "NAT rules added to UFW configuration"
else
    log "NAT rules already exist in UFW configuration"
fi

# Перезагрузить UFW
ufw reload

# Enable and start WireGuard
log "Starting WireGuard server..."
systemctl enable wg-quick@$WG_INTERFACE
systemctl start wg-quick@$WG_INTERFACE

# Create monitoring script

# Install server monitoring script
log "Installing server monitoring script..."
curl -sSL "$MONITOR_SOURCE_URL" -o "$MONITOR_PATH"

if [ $? -ne 0 ]; then
    error "Failed to download and write the monitoring script. Check the URL and your internet connection."
fi

chmod +x "$MONITOR_PATH"
log "Monitoring script deployed to $MONITOR_PATH"

# Add to cron
if ! crontab -l 2>/dev/null | grep -q "$MONITOR_NAME"; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * $MONITOR_PATH") | crontab -
    log "Monitoring cron job added"
fi
log "Cron monitoring job every 5 mins"

# Create server control script
log "Installing server control script..."
curl -sSL "$CONTROL_SOURCE_URL" -o "$CONTROL_PATH"

if [ $? -ne 0 ]; then
   error "Failed to download and write the control script. Check the URL and your internet connection."
fi
chmod +x "$CONTROL_PATH"
log "Control script deployed to $CONTROL_PATH"

# Display status and complete message
log "Displaying WireGuard status..."
sleep 3
systemctl status wg-quick@$WG_INTERFACE --no-pager || true
echo ""
wg show || true

echo ""
log "Server setup complete!"
echo ""
echo "========================================"
echo "CLIENT CONFIGURATION:"
echo "========================================"
cat /etc/wireguard/client.conf
echo "========================================"
echo ""
echo "Copy the configuration above and save it to a file on the client."
echo "Server config file path: /etc/wireguard/client.conf"
echo ""
echo "Server management commands:"
echo "  wg-server-control.sh status      - Show status"
echo "  wg-server-control.sh show-config - Show client configuration"
echo "  wg-server-control.sh restart     - Restart server"
echo "  wg-server-control.sh logs        - Show monitoring logs"
echo "  wg-server-control.sh fix-ssh     - Fix SSH access if needed"
echo ""
echo "Current UFW status:"
ufw status

log "Setup completed successfully!"
