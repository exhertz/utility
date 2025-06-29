#!/bin/bash

# WireGuard Client Setup Script
# Author: exhertz
# Description: configures a WireGuard VPN client to act as a gateway, routing all traffic by default

set -e

LOG_FILE="/var/log/wireguard-client.log"

WG_INTERFACE="wg0"
CONFIG_FILE="/etc/wireguard/$WG_INTERFACE.conf"
CURRENT_SSH_PORT=22

MONITOR_NAME="wg-client-monitor.sh"
MONITOR_PATH="/usr/local/bin/$MONITOR_NAME"
MONITOR_SOURCE_URL="https://exhertz.github.io/utility/wg/wg-client-monitor.sh"
CONTROL_NAME="wg-client-control.sh"
CONTROL_PATH="/usr/local/bin/$CONTROL_NAME"
CONTROL_SOURCE_URL="https://exhertz.github.io/utility/wg/wg-client-control.sh"


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


# check root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root."
fi

log "Starting WireGuard client setup..."

# Install WireGuard
log "Installing WireGuard..."
apt update
apt install -y wireguard wireguard-tools resolvconf iptables-persistent

# Prepare WireGuard configuration
mkdir -p /etc/wireguard

if [[ ! -f "$CONFIG_FILE" ]]; then
    log ""
    log "Configuration file not found!"
    log "Create the file $CONFIG_FILE with the following content:"
    log ""
    log "1. Run the script on the server."
    log "2. Copy the client configuration"
    log "3. Save it to the file $CONFIG_FILE"
    log ""
    log "Example file creation:"
    log "nano $CONFIG_FILE"
    log ""
    log "After creating the file, run the script again."
    exit 1
fi

log "Configuration file found: $CONFIG_FILE"

# Basic configuration file correctness check
if ! grep -q "\[Interface\]" "$CONFIG_FILE" || ! grep -q "\[Peer\]" "$CONFIG_FILE"; then
    error "Configuration file does not contain the necessary sections!"
fi

chmod 600 "$CONFIG_FILE"
chown root:root "$CONFIG_FILE"

# Determine the main interface and gateway
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [[ -z "$MAIN_INTERFACE" ]]; then
    error "Failed to determine main network interface"
fi
log "Main network interface: $MAIN_INTERFACE"

ORIGINAL_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
log "Original gateway: $ORIGINAL_GATEWAY"

# Enable IP forwarding
log "Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1

# Start WireGuard
log "Starting WireGuard client..."
systemctl enable "wg-quick@$WG_INTERFACE"
systemctl start "wg-quick@$WG_INTERFACE"

# Check interface
sleep 2
if ! ip link show "$WG_INTERFACE" &> /dev/null; then
    error "WireGuard interface failed to start!"
fi

log "WireGuard interface is up"

# Exclude SSH from VPN (IMPORTANT)
log "Adding rule to allow SSH..."
iptables -t nat -I POSTROUTING 1 -o "$MAIN_INTERFACE" -p tcp --dport "$CURRENT_SSH_PORT" -j ACCEPT
log "SSH traffic excluded from VPN."

# Setup iptables for NAT (ALL Traffic)
log "Configuring iptables for ALL traffic NAT..."
iptables -t nat -F POSTROUTING
iptables -t nat -A POSTROUTING -o "$WG_INTERFACE" -j MASQUERADE
iptables -F FORWARD

# Add forwarding rules
iptables -A FORWARD -i "$WG_INTERFACE" -j ACCEPT
iptables -A FORWARD -o "$WG_INTERFACE" -j ACCEPT
iptables -A FORWARD -j ACCEPT # Allow all forward traffic
log "NAT and forwarding rules configured."

# Save iptables rules
log "Saving iptables rules..."
iptables-save > /etc/iptables/rules.v4

# Add a consistent check for the /usr/local/bin directory
if [ ! -d /usr/local/bin ]; then
  log "Creating /usr/local/bin directory..."
  mkdir -p /usr/local/bin
  if [ $? -ne 0 ]; then
    error "Failed to create /usr/local/bin.  Check permissions."
  fi
fi

# Install client monitoring script
log "Installing client monitoring script..."
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

# Install client control script
log "Installing client control script..."
curl -sSL "$CONTROL_SOURCE_URL" -o "$CONTROL_PATH"

if [ $? -ne 0 ]; then
   error "Failed to download and write the control script. Check the URL and your internet connection."
fi
chmod +x "$CONTROL_PATH"
log "Control script deployed to $CONTROL_PATH"

# Display status
log "Checking connection status..."
sleep 3
systemctl status "wg-quick@$WG_INTERFACE" --no-pager || true
wg show || true
log "WireGuard status checks completed."

# Test external IP
log "Testing connectivity..."
EXTERNAL_IP=$(timeout 10 curl -s ifconfig.me || echo "Unable to determine")

log ""
log "Client setup completed successfully!"
log ""
log "- - - - - - - - - - - - - - - - - - - - -"
log "CONNECTION INFORMATION:"
log "- - - - - - - - - - - - - - - - - - - - -"
log "Current external IP: $EXTERNAL_IP"
log "VPN Status: $(systemctl is-active wg-quick@$WG_INTERFACE)"
log "WireGuard mode: Full-VPN (0.0.0.0/0)"
log ""
log "Commands to manage:"
log "  wg-client-control.sh status       - Show detailed status"
log "  wg-client-control.sh restart      - Restart WireGuard"
log "  wg-client-control.sh restore-config - Restore original config to (0.0.0.0/0) - FULL VPN"
log "  wg-client-control.sh logs         - Show monitoring logs"
log ""
log "IMPORTANT NOTES:"
log "- SSH access is preserved (traffic not routed through VPN)"
log "- ALL traffic is routed through VPN unless explicitly excluded"
log "- Configure your VMs to use this server ($(hostname -I | awk '{print $1}')) as gateway (only applies if you want VMs to ALSO use THE VPN connection)"
log ""
log "Client logs: $LOG_FILE"
log "Configuration: $CONFIG_FILE"

# Run initial monitoring check
log "Running initial monitoring check..."
"$MONITOR_PATH"

log "All done! SSH connection should remain stable."
