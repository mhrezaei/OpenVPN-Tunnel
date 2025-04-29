#!/bin/bash

# =============================
# OpenVPN Iran Server Setup Script
# Role: VPN Provider + Tunnel to Foreign Server
# Version: 1.1.0
# =============================

set -e

# Utility Functions
function log() {
  echo -e "[INFO] $1"
}

function ask_value() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " value
  echo "${value:-$default}"
}

function get_ip4() {
  ip -4 addr show | awk '/inet/ && $2 !~ /^127\./ {print $2; exit}' | cut -d/ -f1
}

function get_ip6() {
  ip -6 addr show scope global | awk '/inet6/ {print $2; exit}' | cut -d/ -f1
}

# === Step 0: Show IP info ===
echo "======================================"
echo "Iran VPN Server Setup Script v1.1"
echo "IPv4: $(get_ip4)"
echo "IPv6: $(get_ip6)"
echo "======================================"

# === Step 1: Check for required key files before anything ===
REQUIRED_FILES=(ca.crt server-ir.crt server-ir.key ta.key)
MISSING=false
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "/etc/openvpn/keys/$file" ]]; then
    log "Missing required file: /etc/openvpn/keys/$file"
    MISSING=true
  fi
done
if [[ "$MISSING" == true ]]; then
  log "Please copy all required certificate/key files before running this script."
  exit 1
fi

# === Step 2: Detect previous installation ===
if [[ -f /etc/openvpn/server.conf && -f /etc/openvpn/iran-to-foreign.conf ]]; then
  log "VPN configuration already exists. Skipping setup."
  echo "---------------------------"
  echo "[STATUS] OpenVPN Server:"
  systemctl status openvpn@server --no-pager || true
  echo "---------------------------"
  echo "[STATUS] Tunnel to Foreign Server (via screen):"
  screen -ls | grep tunnel || echo "[INFO] No tunnel screen session found."
  exit 0
fi

# === Step 3: Ask for config values ===
VPN_PORT=$(ask_value "Enter OpenVPN listening port" "443")
VPN_PROTO=$(ask_value "Choose protocol for local VPN (tcp/udp)" "tcp")
FOREIGN_SERVER_IP=$(ask_value "Enter Foreign server IP address" "1.2.3.4")
FOREIGN_SERVER_PORT=$(ask_value "Enter port of foreign OpenVPN server" "1194")
FOREIGN_PROTO=$(ask_value "Enter protocol to connect to foreign server" "udp")

# === Step 4: Install Required Packages ===
log "Installing OpenVPN, iptables, and screen..."
apt update -y
apt install -y openvpn iptables-persistent curl screen

# === Step 5: Create OpenVPN server config for clients ===
log "Generating OpenVPN server config..."
cat > /etc/openvpn/server.conf <<EOF
port $VPN_PORT
proto $VPN_PROTO
dev tun
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server-ir.crt
key /etc/openvpn/keys/server-ir.key
dh none
ecdh-curve prime256v1
tls-auth /etc/openvpn/keys/ta.key 0
server 10.7.0.0 255.255.255.0
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup
cipher AES-256-GCM
auth SHA256
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
status /var/log/openvpn-status.log
log /var/log/openvpn.log
verb 3
EOF

# === Step 6: Enable IP forwarding ===
log "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

# === Step 7: Prepare OpenVPN client config to connect to foreign server ===
log "Generating OpenVPN client config for tunnel to foreign server..."
cat > /etc/openvpn/iran-to-foreign.conf <<EOF
client
dev tun1
proto $FOREIGN_PROTO
remote $FOREIGN_SERVER_IP $FOREIGN_SERVER_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/server-ir.crt
key /etc/openvpn/keys/server-ir.key
tls-auth /etc/openvpn/keys/ta.key 1
cipher AES-256-GCM
auth SHA256
remote-cert-tls server
route-nopull
EOF

# === Step 8: Configure NAT and policy routing ===
log "Configuring iptables for NAT and policy routing..."
iptables -t nat -A POSTROUTING -s 10.7.0.0/24 -o tun1 -j MASQUERADE
EXT_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
iptables -A FORWARD -s 10.7.0.0/24 -o tun1 -j ACCEPT
iptables -A FORWARD -d 10.7.0.0/24 -i tun1 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "120 vpnout" | grep -q 'vpnout' /etc/iproute2/rt_tables || echo "120 vpnout" >> /etc/iproute2/rt_tables
ip rule add from 10.7.0.0/24 table vpnout || true
ip route add default dev tun1 via 10.8.0.1 table vpnout || true

netfilter-persistent save

# === Step 9: Start services ===
log "Starting OpenVPN client (tunnel to foreign)..."
screen -dmS tunnel openvpn --config /etc/openvpn/iran-to-foreign.conf
sleep 3
screen -ls | grep tunnel && log "Tunnel client is running in screen session."

log "Starting OpenVPN server for clients..."
systemctl enable openvpn@server
systemctl start openvpn@server
systemctl status openvpn@server --no-pager || true

log "Iran server setup completed. VPN is ready and persistent across reboots."
