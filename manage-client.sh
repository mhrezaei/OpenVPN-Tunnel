#!/bin/bash

# ==================================
# OpenVPN Client Management Script
# Version: 1.2.0
# Author: mhrezaei
# ==================================

set -e

SCRIPT_NAME="OpenVPN Client Manager"
SCRIPT_VERSION="1.2.0"

# === Paths ===
CONFIG_FILE="/etc/openvpn/client-config.conf"
OUTPUT_DIR="/root/client-configs"
EASYRSA_DIR="/etc/openvpn/easy-rsa"
KEYS_DIR="$EASYRSA_DIR/pki"
TA_KEY="/etc/openvpn/ta.key"

# === Utility Functions ===
function log() {
  echo -e "[INFO] $1"
}

function error_exit() {
  echo "[ERROR] $1"
  exit 1
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
    log "Loaded saved configuration from $CONFIG_FILE"
  fi

  SERVER_IP=$(ask_value "Enter Foreign VPN Server IP" "${SERVER_IP:-}")
  VPN_PORT=$(ask_value "Enter VPN Server Port" "${VPN_PORT:-443}")
  VPN_PROTO=$(ask_value "Enter VPN Protocol (tcp/udp)" "${VPN_PROTO:-tcp}")

  mkdir -p "$(dirname "$CONFIG_FILE")"

  cat > $CONFIG_FILE <<EOF
SERVER_IP="$SERVER_IP"
VPN_PORT="$VPN_PORT"
VPN_PROTO="$VPN_PROTO"
EOF
}

function create_client() {
  read -rp "Enter new client name: " CLIENT
  if [[ -z "$CLIENT" ]]; then
    error_exit "Client name cannot be empty."
  fi

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
$(cat "$KEYS_DIR/ca.crt")
</ca>
<cert>
$(cat "$KEYS_DIR/issued/$CLIENT.crt")
</cert>
<key>
$(cat "$KEYS_DIR/private/$CLIENT.key")
</key>
<tls-crypt>
$(cat "$TA_KEY")
</tls-crypt>
EOF

  log "Client '$CLIENT' created successfully."
  log "Generated config: $OUTPUT_DIR/$CLIENT.ovpn"
}

function revoke_client() {
  read -rp "Enter client name to revoke: " CLIENT
  if [[ -z "$CLIENT" ]]; then
    error_exit "Client name cannot be empty."
  fi

  cd $EASYRSA_DIR
  ./easyrsa revoke "$CLIENT"
  ./easyrsa gen-crl
  rm -f "$KEYS_DIR/issued/$CLIENT.crt" "$KEYS_DIR/private/$CLIENT.key" "$OUTPUT_DIR/$CLIENT.ovpn"

  cp "$KEYS_DIR/crl.pem" /etc/openvpn/crl.pem
  chmod 644 /etc/openvpn/crl.pem

  log "Client '$CLIENT' revoked and removed."
}

# === Main ===
echo "======================================"
echo "$SCRIPT_NAME v$SCRIPT_VERSION"
echo "======================================"

if [[ ! -d "$EASYRSA_DIR" || ! -f "/etc/openvpn/server.conf" ]]; then
  error_exit "OpenVPN server is not properly set up. Please configure the foreign server first."
fi

load_or_prompt_config

echo ""
echo "Choose an action:"
echo "1) Create new client"
echo "2) Revoke existing client"
echo "3) Exit"
read -rp "Enter your choice [1-3]: " ACTION

case "$ACTION" in
  1)
    create_client
    ;;
  2)
    revoke_client
    ;;
  *)
    echo "Goodbye."
    exit 0
    ;;
esac
