#!/usr/bin/env bash
# shellcheck disable=SC2034

# Basic Netdata install/update/remove script for IPFire
# Made by Jiab77 - 2023
#
# Based on the work made by siosios
#
# TODO:
# - Implement script update...
# - Implement better service page code
#
# Version 0.2.2

# Options
set +o xtrace

# Colors
NC="\033[0m"
NL="\n"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
WHITE="\033[1;37m"
PURPLE="\033[1;35m"

# Config
DEBUG_MODE=false
NO_HEADER=false
RESET_MODE=false
REMOVE_MODE=false
UPDATE_MODE=false
SERVICE_MODE=false
FIX_MODE=false
FIX_PERMS_DURING_INSTALL=true
DO_INSTALLER_UPDATE=false
BIN_GIT=$(which git 2>/dev/null)
BASE_DIR=$(dirname "$0")
PAKFIRE_INSTALL_PATH="/opt/pakfire/tmp"
NETDATA_INSTALL_PATH="/opt/netdata"
NETDATA_BACKUP_PATH="/root/netdata-config-files"
GITHUB_PATH="https://github.com/siosios/Netdata-on-Ipfire/raw/main/core%20"
IPFIRE_VERSION=$(awk '{ print $2 }' 2>/dev/null </etc/system-release)
IPFIRE_PLATFORM=$(awk '{ print $3 }' 2>/dev/null </etc/system-release | sed -e 's/(//' -e 's/)//')
IPFIRE_PATCH=$(awk '{ print $5 }' 2>/dev/null </etc/system-release | sed -e 's/core//')
CURRENT_NETDATA_VERSION=$("$NETDATA_INSTALL_PATH"/usr/sbin/netdatacli version 2>/dev/null | awk '{ print $2 }' | sed -e 's/v//i')
LATEST_NETDATA_VERSION="1.40.0-1"
LATEST_NETDATA_VERSION_TRIMMED="${LATEST_NETDATA_VERSION//-1/}"

# Functions
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function get_installer_version() {
    echo -en "${WHITE}Gathering local patch installer version...${NC}"
    CURRENT_INSTALLER_VERSION=$(grep -i 'version' "$0" | awk '{ print $3 }' | head -n1)
    if [[ -n $CURRENT_INSTALLER_VERSION ]]; then
        echo -e " ${GREEN}${CURRENT_INSTALLER_VERSION}${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
}
function get_change_log() {
    # Detect if git is installed
    [[ -z $BIN_GIT ]] && echo -e "${RED}Error: ${YELLOW}You must have 'git' installed to run this script.${NC}${NL}" && exit 1

    # Display latest changes
    echo -e "${WHITE}Loading changes summary...${NC}${NL}"
    git log -n5
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
}
function sanity_check() {
    echo -en "${WHITE}Running sanity check...${NC}"
    if [[ -z $LINE_TO_PATCH_POS ]]; then
        echo -e "${NL}${NL}${RED}Error: ${YELLOW}Unable to find corresponding line. Leaving...${NC}${NL}"
        exit 1
    else
        echo -e " ${GREEN}passed${NC}${NL}"
    fi
}
function fix_perms() {
    local FILES_WITH_WRONG_OWNERSHIP

    echo -e "${YELLOW}Fixing ${PURPLE}Netdata${YELLOW} permissions...${NC}${NL}"

    FILES_WITH_WRONG_OWNERSHIP=$(find "$NETDATA_INSTALL_PATH" -group 999 2>/dev/null | wc -l)

    # Stop Netdata
    echo -e "${WHITE}Stopping ${PURPLE}Netdata${WHITE} service...${NC}${NL}"
    /etc/init.d/netdata stop
    sleep 1

    # Lookup for files with wrong ownership
    echo -en "${NL}${WHITE}Searching for ${PURPLE}Netdata${WHITE} files with wrong ownership...${NC}"
    if [[ $FILES_WITH_WRONG_OWNERSHIP -eq 0 ]]; then
        echo -e " ${GREEN}${FILES_WITH_WRONG_OWNERSHIP}${NC}${NL}"
    else
        echo -e " ${RED}${FILES_WITH_WRONG_OWNERSHIP}${WHITE} impacted files found.${NC}${NL}"

        # Fix impacted files
        echo -en "${WHITE}Fixing impacted ${PURPLE}Netdata${WHITE} files...${NC}"
        find "$NETDATA_INSTALL_PATH" -group 999 -exec chown root:netdata {} \; 2>/dev/null
        RET_CODE_FIX_FILES=$?
        if [[ $RET_CODE_FIX_FILES -eq 0 ]]; then
            echo -e " ${GREEN}done${NC}${NL}"
        else
            echo -e " ${RED}failed${NC}${NL}"
            exit 1
        fi

        # Fix impacted config files
        echo -en "${WHITE}Fixing impacted ${PURPLE}Netdata${WHITE} config files...${NC}"
        chown root:netdata "$NETDATA_INSTALL_PATH"/etc/netdata/*.conf && \
        chmod 644 "$NETDATA_INSTALL_PATH"/etc/netdata/*.conf
        RET_CODE_FIX_CONFIG=$?
        if [[ $RET_CODE_FIX_CONFIG -eq 0 ]]; then
            echo -e " ${GREEN}done${NC}${NL}"
        else
            echo -e " ${RED}failed${NC}${NL}"
            exit 1
        fi

        # Start Netdata
        echo -e "${WHITE}Starting ${PURPLE}Netdata${WHITE} service...${NC}${NL}"
        /etc/init.d/netdata start
        sleep 1

        # Show Netdata service status
        echo -e "${NL}${WHITE}Starting ${PURPLE}Netdata${WHITE} service...${NC}${NL}"
        /etc/init.d/netdata status

        echo -e "${NL}${WHITE}Done.${NC}${NL}"
    fi
}
function backup_existing_config() {
    local NETDATA_CONFIG_FILES

    echo -e "${YELLOW}Backup ${PURPLE}Netdata${YELLOW} config files...${NC}${NL}"

    NETDATA_CONFIG_FILES=$(find "$NETDATA_INSTALL_PATH"/etc/netdata -maxdepth 1 -type f -iname "*.conf" 2>/dev/null | wc -l)

    # Lookup for netdata config files
    echo -en "${WHITE}Searching for ${PURPLE}Netdata${WHITE} config files to backup...${NC}"
    if [[ $NETDATA_CONFIG_FILES -eq 0 ]]; then
        echo -e " ${BLUE}nothing${NC}${NL}"
    else
        echo -e " ${YELLOW}${NETDATA_CONFIG_FILES}${WHITE} files found.${NC}${NL}"

        # Copy found netdata config files
        echo -en "${WHITE}Copying found ${PURPLE}Netdata${WHITE} config files...${NC}"
        mkdir -p "$NETDATA_BACKUP_PATH" && cp -a "$NETDATA_INSTALL_PATH"/etc/netdata/*.conf "$NETDATA_BACKUP_PATH"/
        RET_CODE_BACKUP=$?
        if [[ $RET_CODE_BACKUP -eq 0 ]]; then
            echo -e " ${GREEN}done${NC}${NL}"
        else
            echo -e " ${RED}failed${NC}${NL}"
            exit 1
        fi

        # Show backuped config files
        echo -e "${WHITE}Showing backuped ${PURPLE}Netdata${WHITE} config files...${NC}${NL}"
        find "$NETDATA_BACKUP_PATH" -maxdepth 1 -type f -iname "*.conf" -ls 2>/dev/null
        echo -e "${NL}${WHITE}Done.${NC}${NL}"
    fi
}
function restore_existing_config() {
    local NETDATA_CONFIG_FILES

    echo -e "${YELLOW}Restore ${PURPLE}Netdata${YELLOW} config files...${NC}${NL}"

    NETDATA_CONFIG_FILES=$(find "$NETDATA_BACKUP_PATH" -maxdepth 1 -type f -iname "*.conf" 2>/dev/null | wc -l)

    # Lookup for netdata config files
    echo -en "${WHITE}Searching for ${PURPLE}Netdata${WHITE} config files to restore...${NC}"
    if [[ $NETDATA_CONFIG_FILES -eq 0 ]]; then
        echo -e " ${BLUE}nothing${NC}${NL}"
    else
        echo -e " ${YELLOW}${NETDATA_CONFIG_FILES}${WHITE} files found.${NC}${NL}"

        # Restore found netdata config files
        echo -en "${WHITE}Restoring found ${PURPLE}Netdata${WHITE} config files...${NC}"
        cp -a "$NETDATA_BACKUP_PATH"/*.conf "$NETDATA_INSTALL_PATH"/etc/netdata/
        RET_CODE_RESTORE=$?
        if [[ $RET_CODE_RESTORE -eq 0 ]]; then
            echo -e " ${GREEN}done${NC}${NL}"
        else
            echo -e " ${RED}failed${NC}${NL}"
            exit 1
        fi

        # Show restored config files
        echo -e "${WHITE}Showing restored ${PURPLE}Netdata${WHITE} config files...${NC}${NL}"
        find "$NETDATA_INSTALL_PATH"/etc/netdata/ -maxdepth 1 -type f -iname "*.conf" -ls 2>/dev/null
        echo -e "${NL}${WHITE}Done.${NC}${NL}"
    fi
}
function install_elfutils() {
    local ELFUTILS_VERSION

    echo -e "${WHITE}Installing required ${PURPLE}elfutils${WHITE} add-on...${NC}${NL}"
    pakfire install elfutils

    echo -en "${WHITE}Verifying ${PURPLE}elfutils${WHITE} add-on installation...${NC}"
    if [[ $(pakfire list installed --no-colors | grep -ci elf) -eq 0 ]]; then
        echo -e " ${RED}not installed${NC}${NL}"
        echo -e "${RED}Error: ${YELLOW}Installation failed.${NC}${NL}"
        exit 1
    else
        echo -e " ${GREEN}installed${NC}${NL}"

        ELFUTILS_VERSION=$(pakfire list installed --no-colors | grep -i elf -A1 | grep ProgVersion | awk '{ print $2 }')
        echo -e "${WHITE}Detected version: ${BLUE}${ELFUTILS_VERSION}${NC}${NL}"
    fi
}
function detect_elfutils() {
    local ELFUTILS_VERSION

    ELFUTILS_VERSION=$(pakfire list installed --no-colors | grep -i elf -A1 | grep ProgVersion | awk '{ print $2 }')

    echo -en "${WHITE}Detecting ${PURPLE}elfutils${WHITE} add-on...${NC}"
    if [[ $(pakfire list installed --no-colors | grep -ci elf) -eq 0 ]]; then
        echo -e " ${RED}not installed${NC}${NL}"
        install_elfutils
    else
        echo -e " ${GREEN}installed${NC}${NL}"
        echo -e "${WHITE}Detected version: ${BLUE}${ELFUTILS_VERSION}${NC}${NL}"
    fi
}
function detect_addon() {
    echo -en "${WHITE}Detecting ${PURPLE}Netdata${WHITE} add-on...${NC}"
    if [[ -z $CURRENT_NETDATA_VERSION ]]; then
        if [[ $REMOVE_MODE == true || $UPDATE_MODE == true || $SERVICE_MODE == true ]]; then
            echo -e " ${RED}not installed${NC}${NL}"
            echo -e "${YELLOW}Please run ${WHITE}'${BASE_DIR}/$(basename "$0")'${YELLOW} without any arguments instead.${NC}${NL}"
            exit 1
        else
            echo -e " ${BLUE}not installed${NC}${NL}"
        fi
    else
        echo -e " ${GREEN}installed${NC}${NL}"
        echo -e "${WHITE}Detected version: ${BLUE}${CURRENT_NETDATA_VERSION}${NC}${NL}"
    fi
}
function download_addon() {
    echo -en "${WHITE}Downloading ${PURPLE}Netdata${WHITE} add-on...${NC}"
    cd "$PAKFIRE_INSTALL_PATH" || (echo -e " ${RED}failed${NC}${NL}" && exit 1)
    wget "${GITHUB_PATH}${IPFIRE_PATCH}/netdata-${LATEST_NETDATA_VERSION}.ipfire" &>/dev/null
    RET_CODE_DL=$?
    if [[ $RET_CODE_DL -eq 0 ]]; then
        echo -e " ${GREEN}done${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
}
function test_addon() {
    echo -en "${WHITE}Testing downloaded ${PURPLE}Netdata${WHITE} add-on...${NC}"
    tar tf "netdata-${LATEST_NETDATA_VERSION}.ipfire" &>/dev/null
    RET_CODE_TEST=$?
    if [[ $RET_CODE_TEST -eq 0 ]]; then
        echo -e " ${GREEN}done${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
}
function unpack_addon() {
    echo -en "${WHITE}Unpacking ${PURPLE}Netdata${WHITE} add-on...${NC}"
    tar xf "netdata-${LATEST_NETDATA_VERSION}.ipfire" &>/dev/null
    RET_CODE_UNPACK=$?
    if [[ $RET_CODE_UNPACK -eq 0 ]]; then
        echo -e " ${GREEN}done${NC}${NL}"
        rm -f "netdata-${LATEST_NETDATA_VERSION}.ipfire" &>/dev/null
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
}
function bootstrap() {
    detect_addon
    download_addon
    test_addon
    unpack_addon
}
function install_addon() {
    bootstrap
    detect_elfutils

    if [[ -n $("$NETDATA_INSTALL_PATH"/usr/sbin/netdatacli version 2>/dev/null) ]]; then
        echo -e "${RED}Error: ${YELLOW}Netdata is already installed. Leaving...${NC}${NL}"
        exit 1
    fi

    echo -e "${WHITE}Installing ${PURPLE}Netdata${WHITE} add-on...${NC}${NL}"
    cd "$PAKFIRE_INSTALL_PATH" && ./install.sh
    echo -e "${NL}${WHITE}Done.${NC}${NL}"

    # Restore existing config before fixing permissions
    restore_existing_config

    # Run permissions fix
    [[ $FIX_PERMS_DURING_INSTALL == true ]] && fix_perms
}
function remove_addon() {
    bootstrap

    # Backup existing config before removing the add-on
    backup_existing_config

    echo -e "${WHITE}Removing ${PURPLE}Netdata${WHITE} add-on...${NC}${NL}"
    cd "$PAKFIRE_INSTALL_PATH" && ./uninstall.sh
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
}
function update_addon() {
    bootstrap

    echo -e "${WHITE}Updating ${PURPLE}Netdata${WHITE} add-on...${NC}${NL}"
    cd "$PAKFIRE_INSTALL_PATH" && ./update.sh
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
}
function clean_addon() {
    echo -en "${WHITE}Removing everything left behind the ${PURPLE}Netdata${WHITE} add-on...${NC}"
    rm -rf "$NETDATA_INSTALL_PATH"
    RET_CODE_CLEAN=$?
    if [[ $RET_CODE_CLEAN -eq 0 ]]; then
        echo -e " ${GREEN}done${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
}
function reset_addon() {
    echo -e "${YELLOW}Reinstalling ${PURPLE}Netdata${YELLOW} add-on...${NC}${NL}"
    remove_addon
    sleep 1
    clean_addon
    sleep 1
    install_addon
}
function update_script() {
    local CURRENT_INSTALLER_VERSION
    local LATEST_INSTALLER_VERSION

    # Get current installer version
    get_installer_version

    # Fetch latest version
    echo -en "${WHITE}Fetching latest version...${NC}"
    git fetch &>/dev/null && git pull &>/dev/null
    RET_CODE_FETCH=$?
    if [[ $RET_CODE_FETCH -eq 0 ]]; then
        echo -e " ${GREEN}done${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi

    # Check fetched version
    echo -en "${WHITE}Gathering fetched versions...${NC}"
    LATEST_INSTALLER_VERSION=$(grep -i 'version' "$0" | awk '{ print $3 }' | head -n1)
    if [[ -n $LATEST_INSTALLER_VERSION && ! "$CURRENT_INSTALLER_VERSION" == "$LATEST_INSTALLER_VERSION" ]]; then
        DO_INSTALLER_UPDATE=true
        echo -e " ${YELLOW}update available${NC}${NL}"
    else
        echo -e " ${BLUE}nothing to update${NC}${NL}"
    fi

    # Run the update process if necessary
    if [[ $DO_INSTALLER_UPDATE == true ]]; then
        if [[ -n $LATEST_INSTALLER_VERSION && ! "$CURRENT_INSTALLER_VERSION" == "$LATEST_INSTALLER_VERSION" ]]; then
            echo -e "${WHITE} - New installer version: ${YELLOW}${LATEST_INSTALLER_VERSION}${NC}"
        fi

        # Display latest changes
        get_change_log
    fi
}
function manage_service() {
    detect_addon

    local LINE_TO_PATCH_POS
    local PATCH_CONTENT
    local FILE_TO_PATCH="/srv/web/ipfire/cgi-bin/services.cgi"
    local LINE_TO_PATCH='print "</table></div>\n";'

    LINE_TO_PATCH_POS=$(grep -n "$LINE_TO_PATCH" "$FILE_TO_PATCH" 2>/dev/null | awk '{ print $1 }' | sed -e 's/://')

    # New line start
    PATCH_CONTENT="\n\t"
    PATCH_CONTENT+='<tr>'
    PATCH_CONTENT+='<td style="text-align: left; background-color: black; color: white; width: 31%;">'
    PATCH_CONTENT+='<a href="http://'$(hostname -f)':19999">netdata</a>'
    PATCH_CONTENT+='</td>'
    PATCH_CONTENT+='<td style="text-align: center; background-color: black; color: white;">'
    PATCH_CONTENT+='<input type="checkbox" checked="checked" disabled>'
    PATCH_CONTENT+='</td>'

    # TODO: Make this part dynamic
    PATCH_CONTENT+='<td style="text-align: center; background-color: black; color: white; width: 8%;">'
    PATCH_CONTENT+='<img alt="Stop" title="Stop" src="/images/go-down.png" border="0">'
    PATCH_CONTENT+='</td>'
    PATCH_CONTENT+='<td style="text-align: center; background-color: black; color: white; width: 8%;">'
    PATCH_CONTENT+='<img alt="Restart" title="Restart" src="/images/reload.gif" border="0">'
    PATCH_CONTENT+='</td>'
    PATCH_CONTENT+='<td style="text-align: center; background-color: #339933; color: white;">'
    PATCH_CONTENT+='<strong>RUNNING</strong>'
    PATCH_CONTENT+='</td>'
    PATCH_CONTENT+='<td style="text-align: center; background-color: black; color: white;">'
    PATCH_CONTENT+='PID'
    PATCH_CONTENT+='</td>'
    PATCH_CONTENT+='<td style="text-align: center; background-color: black; color: white;">'
    PATCH_CONTENT+='MEMSIZE'
    PATCH_CONTENT+='</td>'
    # END TODO

    # New line end
    PATCH_CONTENT+='</tr>'
    PATCH_CONTENT+="\n\t${LINE_TO_PATCH}"

    echo -en "${WHITE}Detecting Netdata add-on service operation...${NC}"
    if [[ -z $SERVICE_OP ]]; then
        echo -e " ${RED}failed${NC}${NL}"
        echo -e "${YELLOW}Supported service operations: 'test' or 'add' or 'remove' only.${NC}${NL}"
        exit 1
    else
        echo -e " ${WHITE}[${YELLOW}${SERVICE_OP}${WHITE}]${NC}${NL}"
    fi

    # Define service operation code
    case $SERVICE_OP in
        test)
            echo -en "${WHITE}Testing ${PURPLE}Netdata${WHITE} service...${NC}"
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "${PURPLE}[DEBUG] ${WHITE}Running: ${NC}'$NETDATA_INSTALL_PATH/usr/sbin/netdatacli ping'${NL}"
                exit 1
            else
                if [[ $("$NETDATA_INSTALL_PATH"/usr/sbin/netdatacli ping 2>/dev/null) == "pong" ]]; then
                    echo -e " ${GREEN}running${NC}${NL}"
                else
                    echo -e " ${RED}stopped${NC}${NL}"
                fi
            fi
            echo -e "${WHITE}Done.${NC}${NL}"
        ;;
        add)
            # Run sanity check prior making any changes
            sanity_check

            echo -en "${WHITE}Installing ${PURPLE}services${WHITE} patch...${NC}"
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "${PURPLE}[DEBUG] ${WHITE}Running: ${NC}'sed -e 's|'\"$LINE_TO_PATCH\"'|'\"$PATCH_CONTENT\"'|' -i \"$FILE_TO_PATCH\"'${NL}"
                exit 1
            else
                cp -a "$FILE_TO_PATCH" "${FILE_TO_PATCH}.before-patch"
                sed -e 's|'"$LINE_TO_PATCH"'|'"$PATCH_CONTENT"'|' -i "$FILE_TO_PATCH"
                RET_CODE_PATCH=$?
                if [[ $RET_CODE_PATCH -eq 0 ]]; then
                    echo -e " ${GREEN}done${NC}${NL}"
                else
                    echo -e " ${RED}failed${NC}${NL}"
                fi
            fi
        ;;
        remove)
            echo -en "${WHITE}Removing ${PURPLE}services${WHITE} patch...${NC}"
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "${PURPLE}[DEBUG] ${WHITE}Running: ${NC}'mv \"$FILE_TO_PATCH.before-patch\" \"$FILE_TO_PATCH\"'${NL}"
                exit 1
            else
                if [[ -f "$FILE_TO_PATCH.before-patch" ]]; then
                    cp -a "$FILE_TO_PATCH" "$FILE_TO_PATCH.restore-patch"
                    mv "$FILE_TO_PATCH.before-patch" "$FILE_TO_PATCH"
                    RET_CODE_REMOVE=$?
                    if [[ $RET_CODE_REMOVE -eq 0 ]]; then
                        echo -e " ${GREEN}done${NC}${NL}"
                    else
                        echo -e " ${RED}failed${NC}${NL}"
                    fi
                fi
            fi
        ;;
        *)
            echo -e "${RED}Error: ${YELLOW}Invalid service operations given. Please specify 'test' or 'add' or 'remove' only.${NC}${NL}"
            exit 1
        ;;
    esac
}

# Header
[[ $1 == "--no-header" || $2 == "--no-header" ]] && NO_HEADER=true
if [[ ! $NO_HEADER == true ]]; then
    echo -e "${NL}${BLUE}Basic Netdata ${PURPLE}install/update/remove${BLUE} script for IPFire - ${GREEN}v$(get_version)${NC}${NL}"
fi

# Usage
[[ $1 == "-h" || $1 == "--help" ]] && echo -e "${NL}Usage: $(basename "$0") [-r|--remove, -R|--reset, -u|--update, -s|--service, -v|--version, -c|--changelog, -f|--fix-perms]${NL}" && exit 1

# Arguments
[[ $1 == "-R" || $1 == "--reset" ]] && RESET_MODE=true
[[ $1 == "-r" || $1 == "--remove" ]] && REMOVE_MODE=true
[[ $1 == "-u" || $1 == "--update" ]] && UPDATE_MODE=true
[[ $1 == "-s" || $1 == "--service" ]] && SERVICE_MODE=true
[[ $1 == "-f" || $1 == "--fix-perms" ]] && FIX_MODE=true
[[ $2 == "--no-fix" ]] && FIX_PERMS_DURING_INSTALL=false
[[ $1 == "-v" || $1 == "--version" ]] && get_installer_version && exit 1
[[ $1 == "-c" || $1 == "--changelog" ]] && get_change_log && exit 1

# Checks
[[ $(id -u) -ne 0 ]] && echo -e "${RED}Error: ${YELLOW}You must run this script as 'root' or with 'sudo'.${NC}${NL}" && exit 1
[[ $# -eq 1 && $SERVICE_MODE == true ]] && echo -e "${RED}Error: ${YELLOW}Missing argument. Please specify 'test' or 'add' or 'remove' operation.${NC}${NL}" && exit 1
[[ $# -gt 2 ]] && echo -e "${RED}Error: ${YELLOW}Too many arguments.${NC}${NL}" && exit 1

# Main
if [[ $REMOVE_MODE == true ]]; then
    remove_addon
elif [[ $UPDATE_MODE == true ]]; then
    update_addon
elif [[ $RESET_MODE == true ]]; then
    reset_addon
elif [[ $SERVICE_MODE == true ]]; then
    [[ $2 == "add" ]] && SERVICE_OP="add"
    [[ $2 == "rm" || $2 == "remove" ]] && SERVICE_OP="remove"
    [[ $2 == "test" ]] && SERVICE_OP="test"
    manage_service
elif [[ $FIX_MODE == true ]]; then
    fix_perms
else
    install_addon
fi
