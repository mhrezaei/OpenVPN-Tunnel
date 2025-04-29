#!/bin/bash

# =============================
# OpenVPN Foreign Server Setup Script
# Role: Exit Gateway (Outside Iran)
# Version: 1.0.0
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

# === Step 1: Detect previous installation ===
if [[ -f /etc/openvpn/server.conf && -d /etc/openvpn/easy-rsa ]]; then
  log "VPN configuration already exists. Skipping setup."
  echo "---------------------------"
  echo "[STATUS] OpenVPN Server:"
  systemctl status openvpn@server --no-pager || true
  echo "---------------------------"
  exit 0
fi

# === Step 2: Ask for configuration values ===
VPN_PORT=$(ask_value "Enter VPN port" "1194")
VPN_PROTO=$(ask_value "Choose protocol (tcp/udp)" "udp")

# === Step 3: Install Required Packages ===
log "Installing OpenVPN, Easy-RSA, and iptables-persistent..."
apt update -y
apt install -y openvpn easy-rsa iptables-persistent curl

# === Step 4: Setup Easy-RSA ===
EASYRSA_DIR=/etc/openvpn/easy-rsa
mkdir -p $EASYRSA_DIR
cp -r /usr/share/easy-rsa/* $EASYRSA_DIR
cd $EASYRSA_DIR

log "Initializing PKI..."
./easyrsa init-pki

log "Building Certificate Authority (CA)..."
EASYRSA_BATCH=1 ./easyrsa build-ca nopass

log "Generating server certificate (foreign-server)..."
EASYRSA_BATCH=1 ./easyrsa build-server-full foreign-server nopass

log "Generating client certificate for Iran server (iran-server)..."
EASYRSA_BATCH=1 ./easyrsa build-client-full iran-server nopass

log "Generating TLS auth key..."
openvpn --genkey --secret /etc/openvpn/ta.key

# === Step 5: Configure OpenVPN Server ===
log "Creating OpenVPN server config file..."
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

# === Step 6: Set static IP and routing for Iran server ===
cat > /etc/openvpn/ccd/iran-server <<EOF
ifconfig-push 10.8.0.2 10.8.0.1
iroute 10.7.0.0 255.255.255.0
EOF

# === Step 7: Enable IP forwarding and NAT ===
log "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

log "Configuring NAT..."
EXT_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $EXT_IFACE -j MASQUERADE
netfilter-persistent save

# === Step 8: Start and enable OpenVPN service ===
log "Starting OpenVPN service..."
systemctl enable openvpn@server
systemctl restart openvpn@server
systemctl status openvpn@server --no-pager || true

# === Step 9: Provide instructions for transferring files to Iran server ===
log "Please copy the following files to your Iran server:"
echo "--------------------------------------------------"
echo "Remote: /etc/openvpn/easy-rsa/pki/ca.crt -> Iran: /etc/openvpn/keys/ca.crt"
echo "Remote: /etc/openvpn/easy-rsa/pki/issued/iran-server.crt -> Iran: /etc/openvpn/keys/server-ir.crt"
echo "Remote: /etc/openvpn/easy-rsa/pki/private/iran-server.key -> Iran: /etc/openvpn/keys/server-ir.key"
echo "Remote: /etc/openvpn/ta.key -> Iran: /etc/openvpn/keys/ta.key"
echo "--------------------------------------------------"
echo "Use scp or rsync to transfer. Example:"
echo "scp /etc/openvpn/easy-rsa/pki/ca.crt root@IRAN_SERVER_IP:/etc/openvpn/keys/"
echo "(Repeat for all files)"
log "Foreign server setup completed. VPN is ready and persistent across reboots."
