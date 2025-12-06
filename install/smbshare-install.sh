#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: [YourUserName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: [SOURCE_URL]

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

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

msg_info "Configuring Samba"
SHARE_NAME="shared"
SHARE_PATH="/mnt/shared"
SMB_USER="smbuser"
SMB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

CONTAINER_IP=$(hostname -I | awk '{print $1}')
CONTAINER_HOSTNAME=$(hostname)

# Create shared directory
mkdir -p "$SHARE_PATH"

# Create Samba group
groupadd -f smbgroup

# Create system user for SMB with home directory
useradd -m -s /bin/bash -G smbgroup "$SMB_USER" 2>/dev/null || usermod -aG smbgroup "$SMB_USER"

# Set Linux user password (for console/SSH login)
echo "$SMB_USER:$SMB_PASS" | chpasswd

# Set SMB password and enable user
(echo "$SMB_PASS"; echo "$SMB_PASS") | smbpasswd -a -s "$SMB_USER"
smbpasswd -e "$SMB_USER"

# Set ownership and permissions
chown -R "$SMB_USER":smbgroup "$SHARE_PATH"
chmod 2775 "$SHARE_PATH"

# Backup original samba config
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

# Create Samba share configuration
cat <<EOF >>/etc/samba/smb.conf

[$SHARE_NAME]
   comment = Proxmox Shared Storage
   path = $SHARE_PATH
   valid users = @smbgroup
   read only = no
   browseable = yes
   writable = yes
   create mask = 0664
   directory mask = 0775
   force group = smbgroup
EOF

# Verify Samba configuration
if ! testparm -s >/dev/null 2>&1; then
    msg_error "Samba configuration error"
    exit 1
fi

# Store credentials
cat <<EOF >/root/smbshare.creds
==========================================
  Samba Share Credentials & Access Info
==========================================

Share Name: $SHARE_NAME
Share Path: $SHARE_PATH
SMB User: $SMB_USER
SMB Password: $SMB_PASS

==========================================
  Container Login
==========================================

Console/SSH Username: $SMB_USER
Console/SSH Password: $SMB_PASS

(Or use 'pct enter $HOSTNAME' from Proxmox host for root access)

==========================================
  Network Access
==========================================

Hostname: $CONTAINER_HOSTNAME
IP Address: $CONTAINER_IP
UNC Path: \\\\$CONTAINER_IP\\$SHARE_NAME
UNC Path (Hostname): \\\\$CONTAINER_HOSTNAME\\$SHARE_NAME

==========================================
  Windows Access Instructions
==========================================

Method 1: Network Discovery (Easiest)
  1. Open File Explorer
  2. Click 'Network' in the left sidebar
  3. Look for '$CONTAINER_HOSTNAME' (WSDD enabled)
  4. Double-click to browse shares
  5. Enter credentials when prompted:
     Username: $SMB_USER
     Password: $SMB_PASS

Method 2: File Explorer - Map Network Drive
  1. Press Win + E to open File Explorer
  2. Click 'This PC' in the left sidebar
  3. Click 'Map network drive' in the ribbon
  4. Enter: \\\\$CONTAINER_HOSTNAME\\$SHARE_NAME
  5. Check 'Connect using different credentials'
  6. Username: $SMB_USER
  7. Password: $SMB_PASS

Method 3: Command Prompt (Run as Administrator)
  net use Z: \\\\$CONTAINER_HOSTNAME\\$SHARE_NAME /user:$SMB_USER $SMB_PASS /persistent:yes

==========================================
EOF

msg_ok "Configured Samba"

msg_info "Starting Services"
systemctl enable --now smbd nmbd wsdd
msg_ok "Started Services"

# Verify services are running
sleep 2
if systemctl is-active --quiet smbd && systemctl is-active --quiet nmbd && systemctl is-active --quiet wsdd; then
    msg_ok "All services verified and running"
else
    msg_error "One or more services failed to start"
    systemctl status smbd nmbd wsdd --no-pager
    exit 1
fi

motd_ssh

# Ensure auto-login is configured (customize() might not if PASSWORD is set)
if [[ ! -f /etc/systemd/system/container-getty@1.service.d/override.conf ]]; then
    msg_info "Configuring Console Auto-Login"
    GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
    mkdir -p $(dirname $GETTY_OVERRIDE)
    cat <<EOF >$GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
    systemctl daemon-reload
    systemctl restart container-getty@1.service
    msg_ok "Configured Console Auto-Login"
fi

customize

msg_info "Cleaning Up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
