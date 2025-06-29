#!/bin/bash

WG_INTERFACE="wg0"

case "$1" in
    start)
        echo "Starting WireGuard server..."
        systemctl start wg-quick@$WG_INTERFACE
        ;;
    stop)
        echo "Stopping WireGuard server..."
        systemctl stop wg-quick@$WG_INTERFACE
        ;;
    restart)
        echo "Restarting WireGuard server..."
        systemctl restart wg-quick@$WG_INTERFACE
        ;;
    status)
        systemctl status wg-quick@$WG_INTERFACE --no-pager
        echo ""
        echo "WireGuard Status:"
        wg show
        echo ""
        echo "UFW Status:"
        ufw status
        ;;
    logs)
        if [ -f /var/log/wireguard-monitor.log ]; then
            tail -f /var/log/wireguard-monitor.log
        else
            echo "Log file not found"
        fi
        ;;
    show-config)
        echo "Client Configuration:"
        echo "========================"
        cat /etc/wireguard/client.conf
        ;;
    monitor)
        echo "Running one-time monitor check..."
        /usr/local/bin/wg-monitor.sh
        ;;
    fix-ssh)
        echo "Fixing SSH access..."
        ufw allow 22/tcp
        echo "SSH access restored"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|show-config|monitor|fix-ssh}"
        echo ""
        echo "  start       - Start WireGuard server"
        echo "  stop        - Stop WireGuard server"
        echo "  restart     - Restart WireGuard server"
        echo "  status      - Show status and connections"
        echo "  logs        - Show monitoring logs (Ctrl+C to exit)"
        echo "  show-config - Show client configuration"
        echo "  monitor     - Run a one-time check"
        echo "  fix-ssh     - Fix SSH access if blocked"
        exit 1
        ;;
esac