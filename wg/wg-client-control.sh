#!/bin/bash

WG_INTERFACE="wg0"
CONFIG_FILE="/etc/wireguard/$WG_INTERFACE.conf"

case "$1" in
    start)
        echo "Starting WireGuard..."
        systemctl start wg-quick@$WG_INTERFACE
        ;;
    stop)
        echo "Stopping WireGuard..."
        systemctl stop wg-quick@$WG_INTERFACE
        ;;
    restart)
        echo "Restarting WireGuard..."
        systemctl restart wg-quick@$WG_INTERFACE
        ;;
    status)
        systemctl status wg-quick@$WG_INTERFACE --no-pager
        echo ""
        echo "WireGuard Status:"
        wg show
        echo ""
        echo "Routes:"
        ip route | grep -E "(wg0|192.168.10)"
        echo ""
        echo "Current external IP:"
        timeout 10 curl -s ifconfig.me || echo "Unable to determine"
        echo ""
        ;;
    logs)
        if [ -f /var/log/wireguard-client.log ]; then
            tail -f /var/log/wireguard-client.log
        else
            echo "Log file not found"
        fi
        ;;
    test-vm-route)
        echo "Testing VM routing..."
        echo "Route for 192.168.10.0/24:"
        ip route get 192.168.10.1 || echo "No route found" #This may fail
        echo ""
        echo "WireGuard peers:"
        wg show
        ;;
    restore-config)
        echo "Restoring original WireGuard config..."
        if [ -f $CONFIG_FILE.backup ]; then
            cp $CONFIG_FILE.backup $CONFIG_FILE
            echo "Config restored. You may need to restart WireGuard."
        else
            echo "No backup found"
        fi
        ;;
    full-vpn)
        echo "Switching to full VPN mode (routes all traffic)..."
        if [ -f $CONFIG_FILE.backup ]; then
            cp $CONFIG_FILE.backup $CONFIG_FILE
            systemctl restart wg-quick@$WG_INTERFACE
            echo "Full VPN mode enabled. ALL traffic now goes through VPN."
        else
            echo "No backup config found"
        fi
        ;;
    vm-only)
        echo "Switching to VM-only mode..."
        sed -i 's/AllowedIPs = 0.0.0.0\/0/AllowedIPs = 192.168.10.0\/24/' $CONFIG_FILE
        systemctl restart wg-quick@$WG_INTERFACE
        echo "VM-only mode enabled. Only VM traffic goes through VPN."
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|test-vm-route|restore-config|full-vpn|vm-only}"
        echo ""
        echo "  start          - Start WireGuard"
        echo "  stop           - Stop WireGuard"
        echo "  restart        - Restart WireGuard"
        echo "  status         - Show detailed status"
        echo "  logs           - Show monitoring logs"
        echo "  test-vm-route  - Test VM routing"
        echo "  restore-config - Restore original config"
        echo "  full-vpn       - Route ALL traffic through VPN"
        echo "  vm-only        - Route only VM traffic through VPN (safer)"
        exit 1
        ;;
esac