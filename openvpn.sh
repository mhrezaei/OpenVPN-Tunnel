#!/bin/bash

# =============================
# OpenVPN Auto Setup Script
# Version: 1.0.0
# Supported OS: Ubuntu 22.04 / 24.04
# Author: ChatGPT (based on user's detailed plan)
# =============================

set -e

# Global variables
SCRIPT_NAME="OpenVPN Auto Setup"
SCRIPT_VERSION="1.0.0"
DEBIAN_FRONTEND=noninteractive

# ========== Utility Functions ==========

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

function ask_confirm() {
  local prompt="$1"
  read -rp "$prompt (Y/n): " confirm
  [[ "$confirm" =~ ^[Yy]$|^$ ]] && return 0 || return 1
}

function ask_value() {
  local prompt="$1"
  local default="$2"
  read -rp "$prompt [$default]: " value
  echo "${value:-$default}"
}

function check_requirements() {
  echo "[INFO] Updating package lists..."
  apt update -y
  echo "[INFO] Installing required packages..."
  apt install -y openvpn easy-rsa iptables curl net-tools gnupg lsb-release screen iproute2
}

function handle_error() {
  echo "[ERROR] $1"
  exit 1
}

# ========== Main Setup Flow ==========

print_header

echo "Choose server role to configure:"
echo "1) Foreign Server (exit gateway)"
echo "2) Iran Server (VPN provider + tunnel)"
read -rp "Enter your choice [1/2]: " choice

case $choice in
  1)
    echo "[INFO] Configuring foreign server (Exit Node)..."
    bash <(curl -fsSL https://raw.githubusercontent.com/mhrezaei/OpenVPN-Tunnel/main/foreign-server.sh)
    ;;
  2)
    echo "[INFO] Configuring Iran server (VPN endpoint)..."
    bash <(curl -fsSL https://raw.githubusercontent.com/mhrezaei/OpenVPN-Tunnel/main/iran-server.sh)
    ;;
  *)
    handle_error "Invalid choice. Please enter 1 or 2."
    ;;
esac

exit 0
