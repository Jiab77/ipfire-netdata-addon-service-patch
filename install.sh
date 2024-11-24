#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2015

# Basic Netdata install/update/remove script for IPFire
# Made by Jiab77 / 2023 - 2024
#
# Based on the work made by siosios
#
# Version 0.3.0

# Options
[[ -r $HOME/.debug ]] && set -o xtrace || set +o xtrace

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
FIX_PERMS_DURING_INSTALL=false

# Internals
NO_HEADER=false
RESET_MODE=false
REMOVE_MODE=false
UPDATE_MODE=false
UPDATE_SCRIPT=false
FIX_MODE=false
DO_INSTALLER_UPDATE=false
BASE_DIR=$(dirname "$0")
PAKFIRE_INSTALL_PATH="/opt/pakfire/tmp"
NETDATA_INSTALL_PATH="/opt/netdata"
NETDATA_BACKUP_PATH="/root/netdata-config-files"
GITHUB_PATH="https://github.com/siosios/Netdata-on-Ipfire/raw/refs/heads/main/core"
IPFIRE_VERSION=$(awk '{ print $2 }' 2>/dev/null </etc/system-release)
IPFIRE_PLATFORM=$(awk '{ print $3 }' 2>/dev/null </etc/system-release | sed -e 's/(//' -e 's/)//')
IPFIRE_PATCH=$(awk '{ print $5 }' 2>/dev/null </etc/system-release | sed -e 's/core//')
CURRENT_NETDATA_VERSION=$("$NETDATA_INSTALL_PATH"/usr/sbin/netdatacli version 2>/dev/null | awk '{ print $2 }' | sed -e 's/v//i')
LATEST_NETDATA_VERSION="$(curl -sSL https://raw.githubusercontent.com/Jiab77/ipfire-netdata-addon-service-patch/refs/heads/main/latest.json | jq -r .version 2>/dev/null)"
LATEST_NETDATA_VERSION_TRIMMED="${LATEST_NETDATA_VERSION//-1/}"

# Functions
function die() {
    echo -e "${NL}${RED}Error: ${YELLOW}$*${NC}${NL}" >&2
    exit 255
}
function print_usage() {
    echo -e "${NL}Usage: $(basename "$0") [-r|--remove, -R|--reset, -u|--update, -s|--script-update, -v|--version, -c|--changelog, -f|--fix-perms]${NL}"
    exit
}
function check_deps() {
    local BINARIES=(awk git jq sed wget)
    local MISSING=0

    for BIN in "${BINARIES[@]}"; do
        if [[ -z $(which "$BIN" 2>/dev/null) ]]; then
            ((MISSING++))
        fi
    done

    if [[ $MISSING -ne 0 ]]; then
        die "You must have 'awk', 'git', 'jq', 'sed' and 'wget' installed to run this script."
    fi
}
function get_version() {
    grep -i 'version' -m1 "$0" | cut -d" " -f3
}
function get_installer_version() {
    echo -en "${WHITE}Gathering local patch installer version...${NC}"
    CURRENT_INSTALLER_VERSION=$(get_version)
    if [[ -n $CURRENT_INSTALLER_VERSION ]]; then
        echo -e " ${GREEN}${CURRENT_INSTALLER_VERSION}${NC}${NL}"
    else
        echo -e " ${RED}failed${NC}${NL}"
        exit 1
    fi
}
function get_change_log() {
    # Display latest changes
    echo -e "${WHITE}Loading changes summary...${NC}${NL}"
    git log -n5
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
}
function sanity_check() {
    echo -en "${WHITE}Running sanity check...${NC}"
    if [[ -z $LINE_TO_PATCH_POS ]]; then
        echo -e " ${RED}failed${NC}${NL}"
        die "Unable to find corresponding line. Leaving..."
    else
        echo -e " ${GREEN}passed${NC}${NL}"
    fi
}
function create_tmp_dir() {
    if [[ ! -d $PAKFIRE_INSTALL_PATH ]]; then
        echo -en "${YELLOW}Creating missing '${PURPLE}${PAKFIRE_INSTALL_PATH}${YELLOW}' directory...${NC}"
        mkdir -p $PAKFIRE_INSTALL_PATH
        RET_CODE_CREATE=$?
        if [[ $RET_CODE_CREATE -eq 0 ]]; then
            echo -e " ${GREEN}done${NC}${NL}"
        else
            echo -e " ${RED}failed${NC}${NL}"
            exit 1
        fi
    fi
}
function fix_perms() {
    local FILES_WITH_WRONG_OWNERSHIP

    echo -e "${YELLOW}Fixing ${PURPLE}Netdata${YELLOW} permissions...${NC}${NL}"

    FILES_WITH_WRONG_OWNERSHIP=$(find "$NETDATA_INSTALL_PATH" -group 999 2>/dev/null | wc -l)

    # Stop Netdata
    echo -e "${WHITE}Stopping ${PURPLE}Netdata${WHITE} service...${NC}${NL}"
    /etc/init.d/netdata stop
    sleep 5

    # Lookup for files with wrong ownership
    echo -en "${NL}${WHITE}Searching for ${PURPLE}Netdata${WHITE} files with wrong ownership...${NC}"
    if [[ $FILES_WITH_WRONG_OWNERSHIP -eq 0 ]]; then
        echo -e " ${GREEN}${FILES_WITH_WRONG_OWNERSHIP}${NC}${NL}"

        # Start Netdata
        echo -e "${WHITE}Starting ${PURPLE}Netdata${WHITE} service...${NC}${NL}"
        /etc/init.d/netdata start
        sleep 5
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
        sleep 5
    fi

    # End status when the method is ran in standalone way
    if [[ $FIX_MODE == true ]]; then
        # Show service status after install
        echo -e "${NL}${WHITE}Checking ${PURPLE}Netdata${WHITE} service status...${NC}${NL}"
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
    pakfire install -y elfutils
    sleep 1

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
    if [[ ! -r "netdata-${LATEST_NETDATA_VERSION}.ipfire" ]]; then
        wget "${GITHUB_PATH}${IPFIRE_PATCH}/netdata-${LATEST_NETDATA_VERSION}.ipfire" &>/dev/null
        RET_CODE_DL=$?
        if [[ $RET_CODE_DL -eq 0 ]]; then
            echo -e " ${GREEN}done${NC}${NL}"
        else
            echo -e " ${RED}failed${NC}${NL}"
            exit 1
        fi
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
    create_tmp_dir
    detect_addon
    download_addon
    test_addon
    unpack_addon
}
function install_addon() {
    create_tmp_dir
    detect_elfutils
    bootstrap

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

    # Show service status after install
    echo -e "${NL}${WHITE}Checking ${PURPLE}Netdata${WHITE} service status...${NC}${NL}"
    /etc/init.d/netdata status
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
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
    echo -en "${WHITE}Checking fetched version...${NC}"
    LATEST_INSTALLER_VERSION=$(get_version)
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

# Header
[[ $1 == "--no-header" || $2 == "--no-header" ]] && NO_HEADER=true
if [[ ! $NO_HEADER == true ]]; then
    echo -e "${NL}${BLUE}Basic Netdata ${PURPLE}install/update/remove${BLUE} script for IPFire - ${GREEN}v$(get_version)${NC}${NL}"
fi

# Init
check_deps

# Arguments
while [[ $# -ne 0 ]]; do
    case $1 in
        -h|--help) print_usage ;;
        -R|--reset) RESET_MODE=true ; shift ;;
        -r|--remove) REMOVE_MODE=true ; shift ;;
        -u|--update) UPDATE_MODE=true ; shift ;;
        -s|--script-update) UPDATE_SCRIPT=true ; shift ;;
        -f|--fix-perms) FIX_MODE=true ; shift ;;
        --no-fix) FIX_PERMS_DURING_INSTALL=false ; shift ;;
        -v|--version)
            get_installer_version
            exit
        ;;
        -c|--changelog)
            get_change_log
            exit
        ;;
        *) die "Invalid argument given: $1" ;;
    esac
done

# Checks
[[ $(id -u) -ne 0 ]] && die "You must run this script as 'root' or with 'sudo'."

# Main
if [[ $RESET_MODE == true ]]; then
    reset_addon
elif [[ $REMOVE_MODE == true ]]; then
    remove_addon
elif [[ $UPDATE_MODE == true ]]; then
    update_addon
elif [[ $UPDATE_SCRIPT == true ]]; then
    update_script
elif [[ $FIX_MODE == true ]]; then
    fix_perms
else
    install_addon
fi
