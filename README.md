# OpenVPN Tunnel Setup

**Version:** 1.0.0  
**Author:** mhrezaei  

## 📋 Overview
Automated scripts to install and configure a **secure OpenVPN tunnel** between:
- **Iran Server (Entry Point)**
- **Foreign Server (Exit Gateway)**

Works with **Ubuntu 22.04** and **Ubuntu 24.04**.  
Designed for **stable**, **persistent** tunnels bypassing censorship.

---

## 🛠 Repository
GitHub: [OpenVPN-Tunnel](https://github.com/mhrezaei/OpenVPN-Tunnel)

Main script:  
```bash
openvpn.sh
```
➔ Single script handles **both** Iran and Foreign server setups.

---

## 🚀 Quick Start

### 1. Download & Run Setup

SSH into your server (Iran **or** Foreign based on your role) and run:

```bash
curl -O https://raw.githubusercontent.com/mhrezaei/OpenVPN-Tunnel/main/openvpn.sh
chmod +x openvpn.sh
./openvpn.sh
```

The script will:
- Detect server type (Iran/Foreign)
- Install required packages
- Configure OpenVPN
- Handle EasyRSA PKI setup
- Enable IP forwarding and NAT
- Auto-start services
- Handle reconnection and persistence

---

## 🔄 Files Transfer (Only Once)

After setting up the **foreign server**, transfer the following to **Iran server**:

| Source Path (Foreign) | Destination Path (Iran) |
|:---|:---|
| `/etc/openvpn/easy-rsa/pki/ca.crt` | `/etc/openvpn/keys/ca.crt` |
| `/etc/openvpn/easy-rsa/pki/issued/iran-server.crt` | `/etc/openvpn/keys/iran-server.crt` |
| `/etc/openvpn/easy-rsa/pki/private/iran-server.key` | `/etc/openvpn/keys/iran-server.key` |
| `/etc/openvpn/ta.key` | `/etc/openvpn/keys/ta.key` |

Example:

```bash
scp /etc/openvpn/easy-rsa/pki/ca.crt root@iran-server-ip:/etc/openvpn/keys/
```

---

## 👥 Managing VPN Clients

The script also includes client management:

- **Create New Client**: Generates `.ovpn` ready-to-import
- **Revoke Existing Client**: Cleanly removes certificates

Just re-run:

```bash
./openvpn.sh
```
➔ Choose "Manage Clients" from the menu.

---

## ⚡ Highlights

- Full Auto-Setup (Iran and Foreign roles)
- NAT, IPv6 support, TLS 1.3 encryption
- Persistent tunnels across reboots
- Fast, stable, lightweight
- Minimal manual steps

---

## ✅ Final Flow

Iran Users ➔ Iran Server ➔ **Encrypted Tunnel** ➔ Foreign Server ➔ Internet

Traffic is completely routed through the **foreign server**, **no direct exposure**.

---

## 📚 References
- [OpenVPN Community](https://openvpn.net/community-resources/)
- [EasyRSA GitHub](https://github.com/OpenVPN/easy-rsa)

---

# ✨
*Ready to run a fully private, stable VPN tunnel.*
