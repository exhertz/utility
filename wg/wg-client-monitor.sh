#!/bin/bash

WG_INTERFACE="wg0"
LOG_FILE="/var/log/wireguard-client.log"
TEST_IP="8.8.8.8"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# Ensure log file exists
touch $LOG_FILE

# Check interface status
if ! ip link show $WG_INTERFACE &> /dev/null; then
    log_message "WARNING: WireGuard interface $WG_INTERFACE not found, attempting restart..."
    systemctl restart wg-quick@$WG_INTERFACE
    sleep 5
    if ip link show $WG_INTERFACE &> /dev/null; then
        log_message "INFO: WireGuard restarted successfully"
    else
        log_message "ERROR: Failed to restart WireGuard"
        exit 1
    fi
fi

# Check WireGuard connection
if wg show $WG_INTERFACE | grep -q "latest handshake"; then
    log_message "INFO: WireGuard tunnel is active"
else
    log_message "WARNING: No recent handshake detected"
fi

# Test connectivity through tunnel
if ping -I $WG_INTERFACE -c 1 -W 5 $TEST_IP &> /dev/null; then
    log_message "INFO: Connectivity through VPN tunnel is working"
else
    log_message "WARNING: No connectivity through VPN tunnel"
fi