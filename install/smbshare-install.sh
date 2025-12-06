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
  tdb-tools
msg_ok "Installed Dependencies"

# Setup Samba Configuration
msg_info "Configuring Samba"
SHARE_NAME=shared
SHARE_PATH=/mnt/shared
SHARE_USER=smbuser
SHARE_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

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
EOF

# Verify Samba configuration
testparm -s >/dev/null 2>&1 || (msg_error "Samba configuration error"; exit 1)

# Store credentials
{
  echo "Samba Share Credentials"
  echo "Share Name: $SHARE_NAME"
  echo "Share Path: $SHARE_PATH"
  echo "SMB User: $SHARE_USER"
  echo "SMB Password: $SHARE_PASS"
  echo "Access: \\\\$(hostname -I | awk '{print $1}')\\$SHARE_NAME"
} >>~/smbshare.creds
msg_ok "Configured Samba"

# Enable and Start Samba Service
msg_info "Starting Samba Service"
systemctl enable -q smbd nmbd
systemctl restart -q smbd nmbd
msg_ok "Started Samba Service"

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
