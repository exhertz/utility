#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: Script must be run with root privileges."
    echo "Usage: sudo $0"
    exit 1
fi

WG_PORT=3000
WG_NET="10.0.0.1/24"
SERVER_IP=$(curl -4 ifconfig.co 2>/dev/null || hostname -I | awk '{print $1}')
CLIENT_IP="10.0.0.2"
CLIENT_NAME="proxmox-vm"
CLIENT_CONFIG_DIR="/root/wireguard-clients"
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

echo "Install wireguard..."
apt update && apt install -y wireguard qrencode

echo "Key generation..."
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

echo "Create server configuration"
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $WG_NET
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE
EOF

echo "Enable IP forwarding..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "Creating firewall rules"
ufw allow $WG_PORT/udp
ufw allow proto tcp from $WG_NET to any port 22
echo "net.ipv4.ip_forward=1" >> /etc/ufw/sysctl.conf
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw reload

echo "Start WireGuard..."
systemctl enable --now wg-quick@wg0

echo "Generate client config ($CLIENT_NAME)..."
mkdir -p $CLIENT_CONFIG_DIR
CLIENT_PRIVKEY=$(wg genkey)
CLIENT_PUBKEY=$(echo $CLIENT_PRIVKEY | wg pubkey)

cat > $CLIENT_CONFIG_DIR/$CLIENT_NAME.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVKEY
Address = $CLIENT_IP/24
DNS = 8.8.8.8

[Peer]
PublicKey = $(cat /etc/wireguard/publickey)
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

wg set wg0 peer $CLIENT_PUBKEY allowed-ips $CLIENT_IP/32,192.168.100.0/24
wg-quick save wg0

echo "Gen QR"
qrencode -t ansiutf8 < $CLIENT_CONFIG_DIR/$CLIENT_NAME.conf

echo -e "\n✅ Настройка завершена!"
echo "----------------------------------------"
echo "Сервер: $SERVER_IP:$WG_PORT"
echo "Клиентский конфиг: $CLIENT_CONFIG_DIR/$CLIENT_NAME.conf"
echo "Локальная сеть клиента: 192.168.100.0/24"
echo "----------------------------------------"
wg show