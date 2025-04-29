#!/bin/bash

# =============================
# OpenVPN Client Management Script
# Role: Create and revoke users, generate .ovpn
# Version: 1.0.0
# =============================

set -e

# === Configuration file path ===
CONFIG_FILE="/etc/openvpn/client-config.conf"
OUTPUT_DIR="/root/client-configs"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
KEYS_DIR="$EASYRSA_DIR/pki"
TA_KEY="/etc/openvpn/ta.key"

# === Utility functions ===
function log() {
  echo -e "[INFO] $1"
}

function ask_value() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " value
  echo "${value:-$default}"
}

function load_or_prompt_config() {
  if [[ -f $CONFIG_FILE ]]; then
    source $CONFIG_FILE
  fi

  SERVER_IP=$(ask_value "Enter Iran VPN Server IP" "${SERVER_IP:-}")
  VPN_PORT=$(ask_value "Enter VPN Port" "${VPN_PORT:-443}")
  VPN_PROTO=$(ask_value "Enter Protocol (tcp/udp)" "${VPN_PROTO:-tcp}")

  cat > $CONFIG_FILE <<EOF
SERVER_IP="$SERVER_IP"
VPN_PORT="$VPN_PORT"
VPN_PROTO="$VPN_PROTO"
EOF
}

function create_client() {
  read -rp "Enter client name to create: " CLIENT
  cd $EASYRSA_DIR
  ./easyrsa build-client-full "$CLIENT" nopass

  mkdir -p "$OUTPUT_DIR"
  cat > "$OUTPUT_DIR/$CLIENT.ovpn" <<EOF
client
dev tun
proto $VPN_PROTO
remote $SERVER_IP $VPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3

<ca>
$(cat $KEYS_DIR/ca.crt)
</ca>
<cert>
$(cat $KEYS_DIR/issued/$CLIENT.crt)
</cert>
<key>
$(cat $KEYS_DIR/private/$CLIENT.key)
</key>
<tls-auth>
$(cat $TA_KEY)
</tls-auth>
EOF

  log "Client $CLIENT created at $OUTPUT_DIR/$CLIENT.ovpn"
}

function revoke_client() {
  read -rp "Enter client name to revoke: " CLIENT
  cd $EASYRSA_DIR
  ./easyrsa revoke "$CLIENT"
  ./easyrsa gen-crl
  rm -f "$KEYS_DIR/issued/$CLIENT.crt" "$KEYS_DIR/private/$CLIENT.key" "$OUTPUT_DIR/$CLIENT.ovpn"
  log "Client $CLIENT revoked and files removed."
}

# === Main menu ===
echo "==============================="
echo "OpenVPN Client Management"
echo "==============================="
echo "1) Create new client"
echo "2) Revoke existing client"
echo "3) Exit"
read -rp "Choose an option [1-3]: " ACTION

load_or_prompt_config

case $ACTION in
  1)
    create_client
    ;;
  2)
    revoke_client
    ;;
  *)
    echo "Exiting."
    exit 0
    ;;
esac
