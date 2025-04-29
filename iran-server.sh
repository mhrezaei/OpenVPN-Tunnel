# ==============================================
# Iran Server Setup Script (OpenVPN Entry Point)
# Version: 1.3.0 (Enhanced)
# Author: mhrezaei
# ==============================================

#!/bin/bash

set -e

SCRIPT_NAME="Iran Server Setup"
SCRIPT_VERSION="1.3.0"

# === Utility Functions ===
function log() {
  echo -e "[INFO] $1"
}

function handle_error() {
  echo "[ERROR] $1"
  exit 1
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
echo "$SCRIPT_NAME v$SCRIPT_VERSION"
echo "IPv4: $(get_ip4)"
echo "IPv6: $(get_ip6)"
echo "======================================"

# === Step 1: Check Previous Installation ===
if [[ -f /etc/openvpn/server.conf && -d /etc/openvpn/easy-rsa ]]; then
  log "VPN configuration already exists. Skipping setup."
  echo "---------------------------"
  echo "[STATUS] OpenVPN Server:"
  systemctl status openvpn@server --no-pager || true
  echo "---------------------------"
  exit 0
fi

# === Step 2: Get Configurations ===
VPN_PORT=$(ask_value "Enter VPN server port" "1194")
VPN_PROTO=$(ask_value "Choose server protocol (tcp/udp)" "tcp")

# === Step 3: Install Packages ===
log "Updating and installing required packages..."
apt update -y
apt install -y openvpn easy-rsa net-tools iptables-persistent curl screen

# === Step 4: Setup Easy-RSA PKI ===
log "Setting up Easy-RSA..."
mkdir -p /etc/openvpn/easy-rsa
cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa
./easyrsa init-pki

# === Step 5: Generate Certificates ===
log "Generating server and client certificates..."
EASYRSA_BATCH=1 ./easyrsa build-server-full iran-server nopass
EASYRSA_BATCH=1 ./easyrsa build-client-full iran-client nopass

# === Step 6: Generate TLS Key ===
log "Generating TLS key..."
openvpn --genkey --secret /etc/openvpn/ta.key

# === Step 7: Prepare Keys Directory ===
log "Preparing /etc/openvpn/keys directory..."
mkdir -p /etc/openvpn/keys
cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/keys/
cp /etc/openvpn/easy-rsa/pki/issued/iran-server.crt /etc/openvpn/keys/
cp /etc/openvpn/easy-rsa/pki/private/iran-server.key /etc/openvpn/keys/
cp /etc/openvpn/easy-rsa/pki/issued/iran-client.crt /etc/openvpn/keys/
cp /etc/openvpn/easy-rsa/pki/private/iran-client.key /etc/openvpn/keys/

# === Step 8: Configure OpenVPN Server ===
log "Creating OpenVPN server configuration..."
cat > /etc/openvpn/server.conf <<EOF
port $VPN_PORT
proto $VPN_PROTO
dev tun
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/iran-server.crt
key /etc/openvpn/keys/iran-server.key
dh none
ecdh-curve prime256v1
tls-crypt /etc/openvpn/ta.key
server 10.7.0.0 255.255.255.0
keepalive 10 120
persist-key
persist-tun
cipher AES-256-GCM
auth SHA256
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
user nobody
group nogroup
status /var/log/openvpn-status.log
log /var/log/openvpn.log
verb 3
EOF

# === Step 9: Configure Tunnel to Foreign Server ===
log "Configuring Tunnel from Iran to Foreign Server..."
FOREIGN_IP=$(ask_value "Enter Foreign Server Public IP" "1.2.3.4")
FOREIGN_PORT=$(ask_value "Enter Foreign Server Port" "443")
FOREIGN_PROTO=$(ask_value "Enter Protocol (tcp/udp)" "tcp")

cat > /etc/openvpn/iran-to-foreign.conf <<EOF
client
dev tun
proto $FOREIGN_PROTO
remote $FOREIGN_IP $FOREIGN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
ca /etc/openvpn/keys/ca.crt
cert /etc/openvpn/keys/iran-client.crt
key /etc/openvpn/keys/iran-client.key
tls-crypt /etc/openvpn/ta.key
verb 3
EOF

# === Step 10: Enable IP Forwarding ===
log "Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# === Step 11: Save iptables Rules ===
log "Saving iptables rules..."
netfilter-persistent save

# === Step 12: Start Services ===
log "Starting OpenVPN server and tunnel..."
systemctl enable openvpn@server
systemctl restart openvpn@server
screen -dmS tunnel openvpn --config /etc/openvpn/iran-to-foreign.conf
sleep 2
screen -ls || true

log "Iran Server Setup Completed Successfully!"