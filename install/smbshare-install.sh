#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: [YourUserName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: [SOURCE_URL]

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies with the 3 core dependencies (curl;sudo;mc)
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  samba \
  samba-common-bin \
  tdb-tools \
  wsdd
msg_ok "Installed Dependencies"

# Setup Samba Configuration
msg_info "Configuring Samba"
SHARE_NAME=shared
SHARE_PATH=/mnt/shared
SHARE_USER=smbuser
SHARE_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

# Get container IP address
CONTAINER_IP=$(hostname -I | awk '{print $1}')
CONTAINER_HOSTNAME=$(hostname)

# Create shared directory
mkdir -p $SHARE_PATH
chmod 775 $SHARE_PATH

# Create system user for SMB (without login shell)
useradd -M -s /usr/sbin/nologin $SHARE_USER 2>/dev/null || true

# Set SMB password
echo -e "$SHARE_PASS\n$SHARE_PASS" | smbpasswd -a -s $SHARE_USER

# Backup original samba config
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

# Create Samba share configuration
cat <<EOF >>/etc/samba/smb.conf

[$SHARE_NAME]
   comment = Proxmox Shared Storage
   path = $SHARE_PATH
   valid users = $SHARE_USER
   read only = no
   browseable = yes
   writable = yes
   create mask = 0775
   directory mask = 0775
   guest ok = no
EOF

# Verify Samba configuration
testparm -s >/dev/null 2>&1 || (msg_error "Samba configuration error"; exit 1)

# Store credentials
{
  echo "=========================================="
  echo "  Samba Share Credentials & Access Info"
  echo "=========================================="
  echo ""
  echo "Share Name: $SHARE_NAME"
  echo "Share Path: $SHARE_PATH"
  echo "SMB User: $SHARE_USER"
  echo "SMB Password: $SHARE_PASS"
  echo ""
  echo "=========================================="
  echo "  Network Access"
  echo "=========================================="
  echo ""
  echo "Hostname: $CONTAINER_HOSTNAME"
  echo "IP Address: $CONTAINER_IP"
  echo "UNC Path: \\\\$CONTAINER_IP\\$SHARE_NAME"
  echo "UNC Path (Hostname): \\\\$CONTAINER_HOSTNAME\\$SHARE_NAME"
  echo ""
  echo "=========================================="
  echo "  Windows Access Instructions"
  echo "=========================================="
  echo ""
  echo "Method 1: Network Discovery (Easiest)"
  echo "  1. Open File Explorer"
  echo "  2. Click 'Network' in the left sidebar"
  echo "  3. Look for '$CONTAINER_HOSTNAME' (WSDD enabled)"
  echo "  4. Double-click to browse shares"
  echo "  5. Enter credentials when prompted"
  echo "     Username: $SHARE_USER"
  echo "     Password: $SHARE_PASS"
  echo ""
  echo "Method 2: File Explorer - Map Network Drive"
  echo "  1. Press Win + E to open File Explorer"
  echo "  2. Click 'This PC' in the left sidebar"
  echo "  3. Click 'Map network drive' in the ribbon"
  echo "  4. Enter: \\\\$CONTAINER_HOSTNAME\\$SHARE_NAME"
  echo "  5. Check 'Connect using different credentials'"
  echo "  6. Username: $SHARE_USER"
  echo "  7. Password: $SHARE_PASS"
  echo ""
  echo "Method 3: Command Prompt (Run as Administrator)"
  echo "  net use Z: \\\\$CONTAINER_HOSTNAME\\$SHARE_NAME /user:$SHARE_USER $SHARE_PASS /persistent:yes"
  echo ""
  echo "=========================================="
} | tee ~/smbshare.creds

msg_ok "Configured Samba"

# Enable and Start Samba Service
msg_info "Starting Samba Service"
systemctl enable -q smbd nmbd
systemctl restart -q smbd nmbd
msg_ok "Started Samba Service"

# Enable and Start WSDD Service
msg_info "Starting WSDD Service"
systemctl enable -q wsdd
systemctl restart -q wsdd
msg_ok "Started WSDD Service"

# Verify services are running
sleep 2
if systemctl is-active --quiet smbd && systemctl is-active --quiet nmbd && systemctl is-active --quiet wsdd; then
    msg_ok "Samba and WSDD services verified and running"
else
    msg_error "Services failed to start"
    exit 1
fi

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

# Display final summary
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo "Hostname: $CONTAINER_HOSTNAME"
echo "IP Address: $CONTAINER_IP"
echo ""
echo "WSDD (Network Discovery) is enabled!"
echo "The share will appear in Windows Network Discovery."
echo ""
echo "Credentials and access instructions saved to: ~/smbshare.creds"
echo "Use 'cat ~/smbshare.creds' to view access details"
echo "=========================================="
