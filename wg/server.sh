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
SSH_PORT=22

EXTERNAL_IP=""
MAIN_INTERFACE=""

CONF_DIR="/etc/wireguard"
SERVER_CONF="$CONF_DIR/$WG_INTERFACE.conf"
CLIENT_CONF="$CONF_DIR/client.conf"
SERVER_PRIVATE_KEY_FILE="$CONF_DIR/server_private.key"
SERVER_PUBLIC_KEY_FILE="$CONF_DIR/server_public.key"
CLIENT_PRIVATE_KEY_FILE="$CONF_DIR/client_private.key"
CLIENT_PUBLIC_KEY_FILE="$CONF_DIR/client_public.key"

# port forwarding

# place after conntrack
# iptables -A FORWARD -i $MAIN_INTERFACE -o $WG_INTERFACE -p tcp --dport $EXTERNAL_SSH_PORT -d $WG_CLIENT_IP -j ACCEPT
# place before masquerade
# iptables -t nat -A PREROUTING -i $MAIN_INTERFACE -p tcp --dport $EXTERNAL_SSH_PORT -j DNAT --to-destination $WG_CLIENT_IP:$EXTERNAL_SSH_PORT


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

wg_enable() {
  log "Enabling WireGuard client..."
  systemctl enable "wg-quick@$WG_INTERFACE"
}

wg_start() {
  log "Starting WireGuard client..."
  systemctl start "wg-quick@$WG_INTERFACE"
}

wg_stop() {
  log "Stopping WireGuard client..."
  systemctl stop "wg-quick@$WG_INTERFACE"
}

wg_restart() {
  log "Restarting WireGuard client..."
  systemctl restart "wg-quick@$WG_INTERFACE"
}

wg_status() {
  systemctl status "wg-quick@$WG_INTERFACE" --no-pager
  echo ""
  echo "WireGuard Status:"
  wg show
  echo ""
}

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root."
fi

if [ "$#" -lt 1 ]; then
  log "Usage: $0 <setup|remove|start|stop|restart|status>"
  log "To create rule port forwarding: $0 port-forward <port>"
  exit 1
fi

# Determine main network interface
log "Determining main network interface..."
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [[ -z "$MAIN_INTERFACE" ]]; then
    error "Failed to determine main network interface."
fi
log "Main interface: $MAIN_INTERFACE"

if [ "$1" = "setup" ]; then
  log "Updating system and installing necessary packages..."
  apt update
  apt install -y wireguard wireguard-tools
  apt install -y curl
  apt install -y iptables-persistent

  # Determine external IP
  log "Determinig external IPv4 address..."
  EXTERNAL_IP=$(curl -4 -s ifconfig.me || curl -4 -s ipecho.net/plain || curl -4 -s icanhazip.com || ip -4 route get 8.8.8.8 | grep -oP 'src \K\S+')
  if [[ -z "$EXTERNAL_IP" ]]; then
    error "Failed to determine external IP address."
  fi
  log "External IP: $EXTERNAL_IP"

  # Enable IP forwarding
  log "Enabling IP forwarding..."
  IP_FORWARD_CONF="/etc/sysctl.d/99-wireguard-forward.conf"
  echo 'net.ipv4.ip_forward=1' | tee "$IP_FORWARD_CONF"
  sysctl -p "$IP_FORWARD_CONF"

  # -  -  -  -  -  -  [  iptables section  ]  -  -  -  -  -  -

  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT

  # Allow all incoming & outgoing traffic on the loopback interface
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT

  # Allow ESTABLISHED,RELATED
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Allow all incoming & outgoing traffic on the WireGuard interface
  # NAT router (client) -> tunnel -> This (server).
  iptables -A INPUT -i $WG_INTERFACE -j ACCEPT
  # This (server) -> tunnel -> NAT router (client)
  iptables -A OUTPUT -o $WG_INTERFACE -j ACCEPT

  # Allow all new connections to be forwarded through the WireGuard tunnel.
  # tunnel (wg0) -> This server
  # iptables -A FORWARD -i wg0 -j ACCEPT

  # A more specific rule, where traffic from wg0 should only go out through eth0
  # More reliable!
  # tunnel (wg0) -> This server (eth0) -> Internet
  iptables -A FORWARD -i $WG_INTERFACE -o $MAIN_INTERFACE -j ACCEPT
  # Internet -> This server (eth0) -> tunnel (wg0)
  iptables -A FORWARD -i $MAIN_INTERFACE -o $WG_INTERFACE -j ACCEPT

  # NAT (Masquerading) for clients on the WG tunnel to access the internet via the server's public IP.
  iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE

  # Allow SSH
  iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

  # Allow Wireguard
  iptables -A INPUT -i $MAIN_INTERFACE -p udp --dport $WG_PORT -j ACCEPT

  # Save iptables rules
  netfilter-persistent save

  # -  -  -  -  -  -  [  wireguard section  ]  -  -  -  -  -  -

  # Create directory for configurations
  mkdir -p $CONF_DIR

  # Generate server keys
  log "Generating server keys..."
  SERVER_PRIVATE_KEY=$(wg genkey | tee "$SERVER_PRIVATE_KEY_FILE")
  wg pubkey < "$SERVER_PRIVATE_KEY_FILE" > "$SERVER_PUBLIC_KEY_FILE"
  SERVER_PUBLIC_KEY=$(cat "$SERVER_PUBLIC_KEY_FILE")
  if [[ -z "$SERVER_PRIVATE_KEY" || -z "$SERVER_PUBLIC_KEY" ]]; then
    error "Failed to generate server WireGuard keys."
  fi

  # Generate client keys
  CLIENT_PRIVATE_KEY=$(wg genkey | tee "$CLIENT_PRIVATE_KEY_FILE")
  wg pubkey < "$CLIENT_PRIVATE_KEY_FILE" > "$CLIENT_PUBLIC_KEY_FILE"
  CLIENT_PUBLIC_KEY=$(cat "$CLIENT_PUBLIC_KEY_FILE")
  if [[ -z "$CLIENT_PRIVATE_KEY" || -z "$CLIENT_PUBLIC_KEY" ]]; then
    error "Failed to generate client WireGuard keys."
  fi

  # Create server configuration
  log "Creating server configuration..."
  cat > $SERVER_CONF << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
SaveConfig = true

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $WG_CLIENT_IP/32
EOF

  # Create client configuration
  log "Creating client configuration..."
  cat > $CLIENT_CONF << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $WG_CLIENT_IP/24
Table = off
PostUp = ip route add default via 10.0.0.1 dev %i table 200
PostUp = ip rule add from 192.168.20.0/24 table 200 priority 300
PreDown = ip route del default via 10.0.0.1 dev %i table 200 || true
PreDown = ip rule del from 192.168.20.0/24 table 200 priority 300 || true

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $EXTERNAL_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  # Set permissions
  chmod 600 /etc/wireguard/*.conf
  chmod 600 /etc/wireguard/*.key

  wg_enable
  wg_start
  wg_status

  echo ""
  log "Server setup complete!"
  echo ""
  echo "Copy the configuration above and save it to a file on the client."
  echo "Client config file path: $CLIENT_CONF"

  exit 0
fi

if [ "$1" = "remove" ]; then
  log "Starting WireGuard server removal..."

  log "Stopping and disabling WireGuard service..."
  if systemctl is-active --quiet "wg-quick@$WG_INTERFACE"; then
    systemctl stop "wg-quick@$WG_INTERFACE"
    log "Stopped wg-quick@$WG_INTERFACE."
  fi
  if systemctl is-enabled --quiet "wg-quick@$WG_INTERFACE"; then
    systemctl disable "wg-quick@$WG_INTERFACE"
    log "Disabled wg-quick@$WG_INTERFACE."
  fi

  log "Removing configuration files and keys..."
  rm -f "$SERVER_CONF" "$CLIENT_CONF" "$SERVER_PRIVATE_KEY_FILE" "$SERVER_PUBLIC_KEY_FILE" "$CLIENT_PRIVATE_KEY_FILE" "$CLIENT_PUBLIC_KEY_FILE"
  if [ -d "/etc/wireguard" ]; then
    rm -f "$CONF_DIR/$WG_INTERFACE.conf"
    rm -f "$CONF_DIR"/*.key 2>/dev/null || true
  fi
  log "Configuration files and keys removed."

  log "Restoring original iptables rules (or flushing specific rules)..."

  log "Flushing all iptables chains to remove WireGuard rules."
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  iptables -t mangle -F
  iptables -t mangle -X

  log "Saving iptables rules after flushing..."
  netfilter-persistent save

  log "Removing WireGuard packages..."
  apt -y autoremove wireguard wireguard-tools
  log "WireGuard packages removed."

  log "Disabling IP forwarding if it was enabled solely for WireGuard..."
  if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
    log "Removed 'net.ipv4.ip_forward=1' from /etc/sysctl.conf."
    sysctl -p >/dev/null 2>&1
  fi

  log "WireGuard server removal complete."
  exit 0
fi

if [ "$1" = "start" ]; then
  wg_start
  exit 0
fi

if [ "$1" = "stop" ]; then
  wg_stop
  exit 0
fi

if [ "$1" = "restart" ]; then
  wg_restart
  exit 0
fi

if [ "$1" = "status" ]; then
  wg_status
  exit 0
fi

if [ "$1" = "port-forward" ]; then
 
  if [ "$#" -ne 3 ]; then
    echo "Usage: $0 port_forward <protocol> <port>"
    exit 1
  fi

  PROTOCOL="$2"
  EXTERNAL_PORT="$3"
  # place after conntrack
  # iptables -A FORWARD -i $MAIN_INTERFACE -o $WG_INTERFACE -p tcp --dport $EXTERNAL_SSH_PORT -d $WG_CLIENT_IP -j ACCEPT
  # place before masquerade
  # iptables -t nat -A PREROUTING -i $MAIN_INTERFACE -p tcp --dport $EXTERNAL_SSH_PORT -j DNAT --to-destination $WG_CLIENT_IP:$EXTERNAL_SSH_PORT

  iptables -t nat -A PREROUTING -i "$MAIN_INTERFACE" -p "$PROTOCOL" --dport "$EXTERNAL_PORT" -j DNAT --to-destination "$WG_CLIENT_IP:$EXTERNAL_PORT"

  # Для FORWARD правил - важно вставить после conntrack правил
  CONNTRACK_LINE=$(iptables -L FORWARD --line-numbers | grep "ctstate ESTABLISHED,RELATED" | head -1 | cut -d' ' -f1)
  if [ -n "$CONNTRACK_LINE" ]; then
    INSERT_LINE=$((CONNTRACK_LINE + 1))
    iptables -I FORWARD "$INSERT_LINE" -i "$MAIN_INTERFACE" -o "$WG_INTERFACE" -p "$PROTOCOL" --dport "$EXTERNAL_PORT" -d "$WG_CLIENT_IP" -j ACCEPT
  else
    iptables -I FORWARD 1 -i "$MAIN_INTERFACE" -o "$WG_INTERFACE" -p "$PROTOCOL" --dport "$EXTERNAL_PORT" -d "$WG_CLIENT_IP" -j ACCEPT
  fi

  echo "added forwarding: ($PROTOCOL) $EXTERNAL_PORT -> $WG_CLIENT_IP:$EXTERNAL_PORT"
fi

error "Invalid argument"