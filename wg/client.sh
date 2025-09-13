#!/bin/bash

# WireGuard Client Setup Script
# Version: 2.1
# Author: exhertz
# Description: configures a WireGuard VPN client to act as a gateway, routing all traffic by default

set -e

LOG_FILE="/var/log/wireguard-client.log"

WG_INTERFACE="wg0"
CONFIG_FILE="/etc/wireguard/$WG_INTERFACE.conf"
CURRENT_SSH_PORT=22

VM_SUBNET="192.168.20.0/24"
VM_NET_INTERFACE="eth1"

log() {
  local message="$1"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

error() {
  local message="$1"
  log "[ERROR] $message"
  exit 1
}

warn() {
  local message="$1"
  log "[WARNING] $message"
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
    log "To create rule port forwarding: $0 port-forward <protocol> <external_port> <vm_ip> <vm_port>"
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
  log "Starting WireGuard client setup..."

  log "Installing WireGuard..."
  apt update
  apt install -y wireguard wireguard-tools iptables-persistent

  mkdir -p /etc/wireguard

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Configuration file $CONFIG_FILE not found!"
    log "After creating the file, run the script again."
    exit 1
  fi

  log "Configuration file found: $CONFIG_FILE"

  if ! grep -q "\[Interface\]" "$CONFIG_FILE" || ! grep -q "\[Peer\]" "$CONFIG_FILE"; then
    error "Configuration file does not contain the necessary sections!"
  fi

  chmod 600 "$CONFIG_FILE"
  chown root:root "$CONFIG_FILE"

  # Enable IP forwarding
  log "Enabling IP forwarding..."
  IP_FORWARD_CONF="/etc/sysctl.d/99-wireguard-forward.conf"
  echo 'net.ipv4.ip_forward=1' | tee "$IP_FORWARD_CONF"
  sysctl -p "$IP_FORWARD_CONF"

  wg_enable
  wg_start

  # Check interface
  sleep 2
  if ! ip link show "$WG_INTERFACE" &> /dev/null; then
    error "WireGuard interface failed to start!"
  fi

  log "WireGuard interface is up"

  # -  -  -  -  -  -  [  iptables section  ]  -  -  -  -  -  -

  iptables -P FORWARD DROP

  # Allow all incoming & outgoing traffic on the loopback interface
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT

  # Allow ESTABLISHED,RELATED
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Allow VM -> router
  iptables -A INPUT -i "$VM_NET_INTERFACE" -s "$VM_SUBNET" -j ACCEPT

  # Allow router -> VM
  iptables -A OUTPUT -o "$VM_NET_INTERFACE" -d "$VM_SUBNET" -j ACCEPT

  log "Configuring NAT for VMs via VPN..."
  # iptables -t nat -A POSTROUTING -o "$WG_INTERFACE" -j MASQUERADE
  iptables -t nat -A POSTROUTING -s "$VM_SUBNET" -o "$WG_INTERFACE" -j MASQUERADE

    # Разрешаем исходящие подключения FROM VM TO internet (через WG)
  iptables -A FORWARD -i "$VM_NET_INTERFACE" -o "$WG_INTERFACE" -s "$VM_SUBNET" -j ACCEPT
  # Разрешаем весь трафик FROM internet TO VM
  iptables -A FORWARD -i "$WG_INTERFACE" -o "$VM_NET_INTERFACE" -d "$VM_SUBNET"  -j ACCEPT


  # Save iptables rules
  log "Saving iptables rules..."
  netfilter-persistent save

  wg_status

  # Test external IP
  log "Testing connectivity..."
  EXTERNAL_IP=$(timeout 10 curl -s ifconfig.me || echo "Unable to determine")

  log ""
  log "Client setup completed successfully!"
  log ""
  log "Current external IP: $EXTERNAL_IP"
  log "VPN Status: $(systemctl is-active wg-quick@$WG_INTERFACE)"
  log ""
  log "Client logs: $LOG_FILE"
  log "Configuration: $CONFIG_FILE"
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
  if [ "$#" -ne 5 ]; then
    echo "Usage: $0 port_forward <protocol> <external_port> <vm_ip> <vm_port>"
    exit 1
  fi

  PROTOCOL="$2"
  EXTERNAL_PORT="$3"
  VM_IP="$4"
  VM_PORT="$5"

  iptables -t nat -A PREROUTING -i "$WG_INTERFACE" -p "$PROTOCOL" --dport "$EXTERNAL_PORT" -j DNAT --to-destination "$VM_IP:$VM_PORT"

  CONNTRACK_LINE=$(iptables -L FORWARD --line-numbers | grep "ctstate ESTABLISHED,RELATED" | head -1 | cut -d' ' -f1)
  if [ -n "$CONNTRACK_LINE" ]; then
      INSERT_LINE=$((CONNTRACK_LINE + 1))
      iptables -I FORWARD "$INSERT_LINE" -i "$WG_INTERFACE" -p "$PROTOCOL" --dport "$EXTERNAL_PORT" -d "$VM_IP" -j ACCEPT
  else
      iptables -I FORWARD 1 -i "$WG_INTERFACE" -p "$PROTOCOL" --dport "$EXTERNAL_PORT" -d "$VM_IP" -j ACCEPT
  fi

  echo "added forwarding: $EXTERNAL_PORT -> $VM_IP:$VM_PORT"
fi

error "Invalid argument"

