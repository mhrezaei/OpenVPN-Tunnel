# ==============================================
# OpenVPN Foreign Server Setup Script
# Role: Exit Gateway (Outside Iran)
# Version: 1.4.0 (Finalized)
# Author: mhrezaei
# ==============================================

#!/bin/bash

set -e

SCRIPT_NAME="Foreign VPN Server Setup"
SCRIPT_VERSION="1.4.0"

# === Utility Functions ===
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

# === Step 0: Show Server Info ===
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

# === Step 2: Get Configuration from User ===
VPN_PORT=$(ask_value "Enter VPN port" "443")
VPN_PROTO=$(ask_value "Choose protocol (tcp/udp)" "tcp")

# === Step 3: Install Required Packages ===
log "Installing OpenVPN, Easy-RSA, and iptables-persistent packages..."
apt update -y
apt install -y openvpn easy-rsa iptables-persistent curl

# === Step 4: Setup Easy-RSA and Certificates ===
EASYRSA_DIR=/etc/openvpn/easy-rsa
mkdir -p "$EASYRSA_DIR"
cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"
cd "$EASYRSA_DIR"

log "Initializing PKI..."
./easyrsa init-pki

log "Building Certificate Authority (CA)..."
EASYRSA_BATCH=1 ./easyrsa build-ca nopass

log "Building Foreign Server Certificate..."
EASYRSA_BATCH=1 ./easyrsa build-server-full foreign-server nopass

log "Building Iran Server Certificate (for tunnel)..."
EASYRSA_BATCH=1 ./easyrsa build-server-full iran-server nopass

log "Generating TLS auth key..."
openvpn --genkey --secret /etc/openvpn/ta.key

# === Step 5: Configure OpenVPN Server ===
log "Configuring OpenVPN Server..."
mkdir -p /etc/openvpn/ccd

cat > /etc/openvpn/server.conf <<EOF
port $VPN_PORT
proto $VPN_PROTO
dev tun
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/foreign-server.crt
key /etc/openvpn/easy-rsa/pki/private/foreign-server.key
dh none
ecdh-curve prime256v1
tls-auth /etc/openvpn/ta.key 0
server 10.8.0.0 255.255.255.0
client-config-dir /etc/openvpn/ccd
route 10.7.0.0 255.255.255.0
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

# === Step 6: Static IP Mapping for Iran Tunnel ===
log "Creating CCD entry for Iran server..."
cat > /etc/openvpn/ccd/iran-server <<EOF
ifconfig-push 10.8.0.2 10.8.0.1
iroute 10.7.0.0 255.255.255.0
EOF

# === Step 7: Enable IP Forwarding and Setup NAT ===
log "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

EXT_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
log "Detected network interface: $EXT_IFACE"

log "Configuring NAT..."
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $EXT_IFACE -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.7.0.0/24 -o $EXT_IFACE -j MASQUERADE
netfilter-persistent save

# === Step 8: Enable and Start OpenVPN ===
log "Starting OpenVPN service..."
systemctl enable openvpn@server
systemctl restart openvpn@server
systemctl status openvpn@server --no-pager || true

# === Step 9: Transfer Instructions for Iran Server ===
log "Please copy the following files to your Iran server:"
echo "--------------------------------------------------"
echo "Remote: /etc/openvpn/easy-rsa/pki/ca.crt -> Iran: /etc/openvpn/keys/ca.crt"
echo "Remote: /etc/openvpn/easy-rsa/pki/issued/iran-server.crt -> Iran: /etc/openvpn/keys/server-ir.crt"
echo "Remote: /etc/openvpn/easy-rsa/pki/private/iran-server.key -> Iran: /etc/openvpn/keys/server-ir.key"
echo "Remote: /etc/openvpn/ta.key -> Iran: /etc/openvpn/keys/ta.key"
echo "--------------------------------------------------"
echo "Use scp to copy files. Example:"
echo "scp /etc/openvpn/easy-rsa/pki/ca.crt root@IRAN_SERVER_IP:/etc/openvpn/keys/"
echo "(Repeat for all files)"

log "Foreign Server Setup completed successfully!"