#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: [YourUserName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: [SOURCE_URL]

# App Default Values
APP="smbshare"
var_tags="${var_tags:-community-script}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    # Check if Samba is installed
    if [[ ! -f /etc/samba/smb.conf ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    # Check for Samba updates
    RELEASE=$(apt-cache policy samba | grep "Candidate:" | awk '{print $2}')
    INSTALLED=$(apt-cache policy samba | grep "Installed:" | awk '{print $2}')
    
    if [[ "${RELEASE}" != "${INSTALLED}" ]] || [[ -z "${INSTALLED}" ]]; then
        # Stopping Samba Services
        msg_info "Stopping $APP"
        systemctl stop smbd nmbd
        msg_ok "Stopped $APP"

        # Creating Backup
        msg_info "Creating Backup"
        tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /etc/samba /mnt/shared ~/smbshare.creds
        msg_ok "Backup Created"

        # Execute Update
        msg_info "Updating $APP to v${RELEASE}"
        apt-get update
        apt-get install -y samba samba-common-bin tdb-tools
        msg_ok "Updated $APP to v${RELEASE}"

        # Starting Samba Services
        msg_info "Starting $APP"
        systemctl start smbd nmbd
        msg_ok "Started $APP"

        # Cleaning up
        msg_info "Cleaning Up"
        apt-get -y autoremove
        apt-get -y autoclean
        msg_ok "Cleanup Completed"

        # Last Action
        echo "${RELEASE}" >/opt/${APP}_version.txt
        msg_ok "Update Successful"
    else
        msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the SMB share using the following address:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}\\\\$(hostname -I | awk '{print $1}')\\shared${CL}"
echo -e "${INFO}${YW} Credentials stored in:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}~/smbshare.creds${CL}"
