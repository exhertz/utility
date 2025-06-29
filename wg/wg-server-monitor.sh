#!/bin/bash

WG_INTERFACE="wg0"
LOG_FILE="/var/log/wireguard-monitor.log"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Create log file if it doesn't exist
touch $LOG_FILE

# Check interface status
if ! ip link show $WG_INTERFACE &> /dev/null; then
    log_message "WARNING: WireGuard interface $WG_INTERFACE not found, attempting restart..."
    systemctl restart wg-quick@$WG_INTERFACE
    if [ $? -eq 0 ]; then
        log_message "INFO: WireGuard restarted successfully"
    else
        log_message "ERROR: Failed to restart WireGuard"
    fi
else
    # Check connected clients
    CLIENTS=$(wg show $WG_INTERFACE peers 2>/dev/null | wc -l)
    log_message "INFO: WireGuard is running, connected clients: $CLIENTS"
fi