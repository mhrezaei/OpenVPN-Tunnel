# ==============================================
# OpenVPN Main Setup Script
# Version: 1.2.0
# Author: mhrezaei (special edit for full Iran <-> Foreign Tunnel)
# ==============================================

#!/bin/bash

set -e

SCRIPT_NAME="OpenVPN Tunnel Setup"
SCRIPT_VERSION="1.2.0"

# ================= Utility Functions ====================
function get_ip4() {
  ip -4 addr | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n1
}

function get_ip6() {
  ip -6 addr | grep inet6 | grep -v '::1' | grep -v fe80 | awk '{print $2}' | cut -d/ -f1 | head -n1
}

function print_header() {
  echo "======================================"
  echo "$SCRIPT_NAME v$SCRIPT_VERSION"
  echo "IPv4: $(get_ip4)"
  echo "IPv6: $(get_ip6)"
  echo "======================================"
}

function handle_error() {
  echo "[ERROR] $1"
  exit 1
}

function ask_confirm() {
  local prompt="$1"
  read -rp "$prompt (Y/n): " confirm
  [[ "$confirm" =~ ^[Yy]$|^$ ]] && return 0 || return 1
}

# ================= Main Flow =====================

print_header

# Check Root
if [[ $EUID -ne 0 ]]; then
   handle_error "This script must be run as root."
fi

# Choose Role
echo "Choose server role to configure:"
echo "1) Foreign Server (Exit Gateway)"
echo "2) Iran Server (VPN Entry + Tunnel)"
echo "3) Manage Users (Foreign Server Only)"
read -rp "Enter your choice [1/2/3]: " choice

case $choice in
  1)
    echo "[INFO] Running Foreign Server Setup..."
    bash <(curl -fsSL https://raw.githubusercontent.com/mhrezaei/OpenVPN-Tunnel/main/foreign-server.sh)
    ;;
  2)
    echo "[INFO] Running Iran Server Setup..."
    bash <(curl -fsSL https://raw.githubusercontent.com/mhrezaei/OpenVPN-Tunnel/main/iran-server.sh)
    ;;
  3)
    echo "[INFO] Managing OpenVPN Clients (Foreign Server Only)..."
    if [[ ! -f /etc/openvpn/server.conf ]]; then
      handle_error "OpenVPN server.conf not found. Please run Foreign Server setup first."
    fi
    bash <(curl -fsSL https://raw.githubusercontent.com/mhrezaei/OpenVPN-Tunnel/main/manage-client.sh)
    ;;
  *)
    handle_error "Invalid choice. Please enter 1, 2 or 3."
    ;;
esac

exit 0