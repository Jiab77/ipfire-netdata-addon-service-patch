#!/usr/bin/env bash
# shellcheck disable=SC2034

# Basic Netdata install/update/remove script for IPFire
# Made by Jiab77 - 2023
#
# Based on the work made by siosios
#
# Version 0.1.0

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
REMOVE_MODE=false
UPDATE_MODE=false
SERVICE_MODE=false
DO_INSTALLER_UPDATE=false
BIN_GIT=$(which git 2>/dev/null)
BASE_DIR=$(dirname "$0")
INSTALL_PATH="/opt/pakfire/tmp"
GITHUB_PATH="https://github.com/siosios/Netdata-on-Ipfire/raw/main/core%20"
IPFIRE_VERSION=$(awk '{ print $2 }' 2>/dev/null </etc/system-release)
IPFIRE_PLATFORM=$(awk '{ print $3 }' 2>/dev/null </etc/system-release | sed -e 's/(//' -e 's/)//')
IPFIRE_PATCH=$(awk '{ print $5 }' 2>/dev/null </etc/system-release | sed -e 's/core//')
CURRENT_NETDATA_VERSION=$(/opt/netdata/usr/sbin/netdatacli version 2>/dev/null | awk '{ print $2 }' | sed -e 's/v//i')
LATEST_NETDATA_VERSION="1.38.1-1"
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
    cd "$INSTALL_PATH" || (echo -e " ${RED}failed${NC}${NL}" && exit 1)
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

    if [[ -n $(/opt/netdata/usr/sbin/netdatacli version 2>/dev/null) ]]; then
        echo -e "${RED}Error: ${YELLOW}Netdata is already installed. Leaving...${NC}${NL}"
        exit 1
    fi

    echo -e "${WHITE}Installing ${PURPLE}Netdata${WHITE} add-on...${NC}${NL}"
    cd "$INSTALL_PATH" && ./install.sh
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
}
function remove_addon() {
    bootstrap

    echo -e "${WHITE}Removing ${PURPLE}Netdata${WHITE} add-on...${NC}${NL}"
    cd "$INSTALL_PATH" && ./uninstall.sh
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
}
function update_addon() {
    bootstrap

    echo -e "${WHITE}Updating ${PURPLE}Netdata${WHITE} add-on...${NC}${NL}"
    cd "$INSTALL_PATH" && ./update.sh
    echo -e "${NL}${WHITE}Done.${NC}${NL}"
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
    PATCH_CONTENT+="<tr>"
    PATCH_CONTENT+="<td style=\"text-align: left; background-color: black; color: white; width: 31%;\">"
    PATCH_CONTENT+="<a href=\"http://$(hostname -f):19999\">netdata</a>"
    PATCH_CONTENT+="</td>"
    PATCH_CONTENT+="<td style=\"text-align: center; background-color: black; color: white;\">"
    PATCH_CONTENT+="<input type=\"checkbox\" checked=\"checked\" disabled>"
    PATCH_CONTENT+="</td>"

    # TODO: Make this part dynamic
    PATCH_CONTENT+="<td style=\"text-align: center; background-color: black; color: white; width: 8%;\">"
    PATCH_CONTENT+="<img alt=\"Stop\" title=\"Stop\" src=\"/images/go-down.png\" border=\"0\">"
    PATCH_CONTENT+="</td>"
    PATCH_CONTENT+="<td style=\"text-align: center; background-color: black; color: white; width: 8%;\">"
    PATCH_CONTENT+="<img alt=\"Restart\" title=\"Restart\" src=\"/images/reload.gif\" border=\"0\">"
    PATCH_CONTENT+="</td>"
    PATCH_CONTENT+="<td style=\"text-align: center; background-color: #339933; color: white;\">"
    PATCH_CONTENT+="<strong>RUNNING</strong>"
    PATCH_CONTENT+="</td>"
    PATCH_CONTENT+="<td style=\"text-align: center; background-color: black; color: white;\">"
    PATCH_CONTENT+="PID"
    PATCH_CONTENT+="</td>"
    PATCH_CONTENT+="<td style=\"text-align: center; background-color: black; color: white;\">"
    PATCH_CONTENT+="MEMSIZE"
    PATCH_CONTENT+="</td>"
    # END TODO

    # New line end
    PATCH_CONTENT+="</tr>"
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
                echo -e "${PURPLE}[DEBUG] ${WHITE}Running: ${NC}'/opt/netdata/usr/sbin/netdatacli ping'${NL}"
                exit 1
            else
                if [[ $(/opt/netdata/usr/sbin/netdatacli ping 2>/dev/null) == "pong" ]]; then
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
[[ $1 == "-h" || $1 == "--help" ]] && echo -e "${NL}Usage: $(basename "$0") [-r|--remove, -u|--update, -s|--service, -v|--version, -c|--changelog]${NL}" && exit 1

# Arguments
[[ $1 == "-r" || $1 == "--remove" ]] && REMOVE_MODE=true
[[ $1 == "-u" || $1 == "--update" ]] && UPDATE_MODE=true
[[ $1 == "-s" || $1 == "--service" ]] && SERVICE_MODE=true
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
elif [[ $SERVICE_MODE == true ]]; then
    [[ $2 == "add" ]] && SERVICE_OP="add"
    [[ $2 == "rm" || $2 == "remove" ]] && SERVICE_OP="remove"
    [[ $2 == "test" ]] && SERVICE_OP="test"
    manage_service
else
    install_addon
fi
