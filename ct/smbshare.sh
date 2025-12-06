#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2025 Florian Raichle
# Author: Florian Raichle
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.samba.org/

APP="smbshare"
var_tags="file-server;storage"
var_cpu="2"
var_ram="1024"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
base_settings
echo_default

variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /etc/samba/smb.conf ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    msg_info "Updating ${APP}"
    apt-get update
    apt-get install -y samba samba-common-bin tdb-tools wsdd
    systemctl restart smbd nmbd wsdd
    msg_ok "Updated ${APP}"

    msg_info "Cleaning Up"
    apt-get -y autoremove
    apt-get -y autoclean
    msg_ok "Cleaned"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access SMB share information with:${CL}"
echo -e "     ${GN}cat /root/smbshare.creds${CL}"
