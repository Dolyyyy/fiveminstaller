#!/bin/bash

# Colors for messages
red="\e[0;91m"
green="\e[0;92m"
blue="\e[0;94m"
yellow="\e[0;93m"
cyan="\e[0;96m"
magenta="\e[0;95m"
bold="\e[1m"
underline="\e[4m"
reset="\e[0m"

# Log configuration
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
LOG_DIR="/var/log/fivem"
LOG_FILE="${LOG_DIR}/fivem_install_${TIMESTAMP}.log"
LATEST_LOG_SYMLINK="${LOG_DIR}/latest.log"

# Global variables
dir=""
default_dir=""
update_artifacts=false
non_interactive=false
artifacts_version=0
kill_txAdmin=0
delete_dir=0
txadmin_deployment=0
install_phpmyadmin=0
crontab_autostart=0
pma_options=()
script_version="1.2.0"

# Global variables for existing database
existing_db_host=""
existing_db_name=""
existing_db_user=""
existing_db_password=""
existing_db_configured=false

# Setup logging directory
setup_logging() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi
    
    # Create log file and set permissions
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # Create or update symlink to latest log
    if [ -L "$LATEST_LOG_SYMLINK" ]; then
        rm "$LATEST_LOG_SYMLINK"
    fi
    ln -s "$LOG_FILE" "$LATEST_LOG_SYMLINK"
    
    # Keep only the last 10 log files
    if [ "$(ls -1 $LOG_DIR/fivem_install_*.log 2>/dev/null | wc -l)" -gt 10 ]; then
        ls -1t $LOG_DIR/fivem_install_*.log | tail -n +11 | xargs -I {} rm {}
    fi
    
    log "INFO" "==============================================================="
    log "INFO" "FiveM Server Installer v${script_version} - Started: $(date)"
    log "INFO" "==============================================================="
}

# Enhanced logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local pid=$$
    local indent=""
    
    # Add indentation based on function depth
    local depth=$(($(caller | wc -l) - 1))
    if [ $depth -gt 0 ]; then
        indent=$(printf '%*s' $((depth*2)) '')
    fi
    
    case $level in
        "INFO") color=$green; prefix="[INFO]    " ;;
        "ERROR") color=$red; prefix="[ERROR]   " ;;
        "WARN") color=$yellow; prefix="[WARNING] " ;;
        "DEBUG") color=$blue; prefix="[DEBUG]   " ;;
        "SUCCESS") color=$cyan; prefix="[SUCCESS] " ;;
        "PROMPT") color=$magenta; prefix="[PROMPT]  " ;;
        *) color=$reset; prefix="[LOG]     " ;;
    esac
    
    # Print to terminal with color
    echo -e "${timestamp} ${color}${prefix}${reset} ${indent}${message}" | tee -a "$LOG_FILE"
    
    # Add extra contextual information to log file only (not to terminal)
    if [ "$level" == "DEBUG" ] || [ "$level" == "ERROR" ]; then
        local function_name=$(caller 0 | awk '{print $2}')
        local line_number=$(caller 0 | awk '{print $1}')
        echo "             Function: ${function_name}(), Line: ${line_number}, PID: ${pid}" >> "$LOG_FILE"
    fi
}

# System information gathering
gather_system_info() {
    log "DEBUG" "Gathering system information"
    
    SYS_OS=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2 || echo "Unknown OS")
    SYS_KERNEL=$(uname -r 2>/dev/null || echo "Unknown kernel")
    SYS_CPU=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -n1 | cut -d':' -f2 | xargs || echo "Unknown CPU")
    SYS_CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "Unknown")
    SYS_MEM_TOTAL=$(free -h 2>/dev/null | grep "Mem:" | awk '{print $2}' || echo "Unknown")
    SYS_MEM_FREE=$(free -h 2>/dev/null | grep "Mem:" | awk '{print $4}' || echo "Unknown")
    SYS_DISK_TOTAL=$(df -h / 2>/dev/null | grep -v "Filesystem" | awk '{print $2}' || echo "Unknown")
    SYS_DISK_FREE=$(df -h / 2>/dev/null | grep -v "Filesystem" | awk '{print $4}' || echo "Unknown")
    SYS_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "Unknown")

    log "INFO" "System Information:"
    log "INFO" "  OS: $SYS_OS"
    log "INFO" "  Kernel: $SYS_KERNEL"
    log "INFO" "  CPU: $SYS_CPU ($SYS_CPU_CORES cores)"
    log "INFO" "  Memory: $SYS_MEM_FREE free of $SYS_MEM_TOTAL total"
    log "INFO" "  Disk space: $SYS_DISK_FREE free of $SYS_DISK_TOTAL total"
    log "INFO" "  IP Address: $SYS_IP"
    
    # Check system requirements
    if [ "$SYS_CPU_CORES" -lt 2 ]; then
        log "WARN" "Less than 2 CPU cores detected. FiveM server might perform poorly."
    fi
    
    # Extract memory in MB for comparison
    SYS_MEM_MB=$(free -m | grep "Mem:" | awk '{print $2}')
    if [ "$SYS_MEM_MB" -lt 4096 ]; then
        log "WARN" "Less than 4GB RAM detected. FiveM server might perform poorly."
        if [ "$SYS_MEM_MB" -lt 2048 ]; then
            log "ERROR" "Less than 2GB RAM detected. FiveM server requires at least 2GB RAM."
            if [ "${non_interactive}" == "false" ]; then
                echo -e "${red}${bold}WARNING:${reset} Your system has less than 2GB RAM, which is below the minimum requirements for a FiveM server."
                read -p "Do you want to continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log "INFO" "Installation aborted by user due to insufficient RAM"
                    exit 1
                fi
            fi
        fi
    fi
    
    # Check disk space
    SYS_DISK_MB=$(df -m / | grep -v "Filesystem" | awk '{print $4}')
    if [ "$SYS_DISK_MB" -lt 4096 ]; then
        log "WARN" "Less than 4GB free disk space. FiveM server requires at least 4GB free space."
        if [ "$SYS_DISK_MB" -lt 2048 ]; then
            log "ERROR" "Less than 2GB free disk space. Installation might fail."
            if [ "${non_interactive}" == "false" ]; then
                echo -e "${red}${bold}WARNING:${reset} Your system has less than 2GB free disk space, which may not be enough for a FiveM server."
                read -p "Do you want to continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log "INFO" "Installation aborted by user due to insufficient disk space"
                    exit 1
                fi
            fi
        fi
    fi
}

# Check that the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${red}${bold}ERROR:${reset} This script must be run as root"
	exit 1
fi

# Initialize logging before doing anything else
setup_logging

status(){
  clear
  echo -e "${cyan}╔════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${cyan}║                                                                            ║${reset}"
  echo -e "${cyan}║${reset}  ${bold}${green} $@ ${reset}${cyan}  ║${reset}"
  echo -e "${cyan}║                                                                            ║${reset}"
  echo -e "${cyan}╚════════════════════════════════════════════════════════════════════════════╝${reset}"
  log "INFO" "$@..."
  sleep 1
}

runCommand(){
    COMMAND=$1
    LOG_MSG=${2:-"Executing command"}
    HIDE_OUTPUT=${3:-0}
    CRITICAL=${4:-0}  # If 1, exit on failure; if 0, just log error and continue

    log "DEBUG" "Command: $COMMAND"
    log "INFO" "$LOG_MSG"

    # Check if the command exists before execution
    if [[ $COMMAND == *" "* ]]; then
        first_word=$(echo "$COMMAND" | cut -d' ' -f1)
        if ! command -v $first_word &> /dev/null && [[ ! -f $first_word ]] && [[ ! -e $first_word ]]; then
            log "ERROR" "Command '$first_word' not found. Please install it first."
            return 1
        fi
    else
        if ! command -v $COMMAND &> /dev/null && [[ ! -f $COMMAND ]] && [[ ! -e $COMMAND ]]; then
            log "ERROR" "Command '$COMMAND' not found. Please install it first."
            return 1
        fi
    fi

    # Execute with appropriate output redirection
    if [ "$HIDE_OUTPUT" -eq 1 ]; then
        eval $COMMAND >> "$LOG_FILE" 2>&1
    else
        eval $COMMAND 2>&1 | tee -a "$LOG_FILE"
    fi

    BASH_CODE=$?
    if [ $BASH_CODE -ne 0 ]; then
        log "ERROR" "Command failed with exit code $BASH_CODE: $COMMAND"
        
        # Record detailed error information in the log
        echo "==================== ERROR DETAILS ====================" >> "$LOG_FILE"
        echo "Command: $COMMAND" >> "$LOG_FILE"
        echo "Exit Code: $BASH_CODE" >> "$LOG_FILE"
        echo "Current Directory: $(pwd)" >> "$LOG_FILE"
        echo "User: $(whoami)" >> "$LOG_FILE"
        echo "Date & Time: $(date)" >> "$LOG_FILE"
        
        if [ "$CRITICAL" -eq 1 ]; then
            log "ERROR" "Critical error occurred. Exiting."
            echo -e "${red}${bold}CRITICAL ERROR:${reset} $LOG_MSG failed."
            echo -e "Check the log file for details: $LOG_FILE"
      exit ${BASH_CODE}
        else
            log "WARN" "Command failed but continuing as error is non-critical."
            return ${BASH_CODE}
        fi
    else
        log "SUCCESS" "$LOG_MSG - Completed successfully"
    fi
    
    return 0
}

# Function to safely exit the script
cleanup_and_exit() {
    local exit_code=$1
    local message=$2
    
    log "INFO" "Cleaning up before exit"
    
    # Kill any background processes spawned by this script
    jobs -p | xargs -r kill &>/dev/null
    
    if [ -n "$message" ]; then
        log "INFO" "$message"
        echo -e "$message"
    fi
    
    log "INFO" "==============================================================="
    log "INFO" "FiveM Server Installer - Finished: $(date)"
    log "INFO" "Exit code: $exit_code"
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "==============================================================="
    
    exit $exit_code
}

# Trap signals to ensure clean exit
trap 'cleanup_and_exit 130 "${red}Process interrupted by user. Exiting...${reset}"' INT TERM

# Function to validate and parse URL
validate_url() {
    local url=$1
    
    if [[ $url != http*://* ]]; then
        log "ERROR" "Invalid URL format: $url"
        return 1
    fi
    
    # Check if URL is reachable
    if ! curl --output /dev/null --silent --head --fail "$url"; then
        log "ERROR" "URL not reachable: $url"
        return 1
    fi
    
    return 0
}

# Determine the default installation path
get_default_dir() {
    # Try multiple methods to get the current user
    local current_user=$(who am i 2>/dev/null | awk '{print $1}')
    
    # If 'who am i' fails, try other methods
    if [ -z "$current_user" ]; then
        current_user=$(whoami 2>/dev/null)
    fi
    
    # If that also fails, try environment variables
    if [ -z "$current_user" ]; then
        current_user=${USER:-${USERNAME:-root}}
    fi
    
    # If we still don't have a user, default to root
    if [ -z "$current_user" ] || [ "$current_user" == "root" ]; then
        # Write directly to log file without console output
        echo "$(date "+%Y-%m-%d %H:%M:%S") [DEBUG]    Running as root or couldn't determine user, setting default directory to /home/FiveM" >> "$LOG_FILE"
        echo "/home/FiveM"
    else
        local home_dir="/home/$current_user/FiveM"
        # Write directly to log file without console output
        echo "$(date "+%Y-%m-%d %H:%M:%S") [DEBUG]    Running as $current_user, setting default directory to $home_dir" >> "$LOG_FILE"
        echo "$home_dir"
    fi
}

# Function to choose the installation path
choose_installation_path() {
    default_dir=$(get_default_dir)
    
    if [[ "${non_interactive}" == "false" ]]; then
        log "PROMPT" "Prompting user for installation path"
        echo -e "${bold}Choose the installation path for FiveM${reset}"
        echo -e "${blue}This is where all server files will be stored${reset}"
        read -p "Installation path [$default_dir]: " input_dir
        dir=${input_dir:-$default_dir}
    else
        dir=$default_dir
        log "INFO" "Non-interactive mode: using default path $dir"
    fi
    
    # Validate directory path
    if [[ "$dir" =~ [[:space:]] ]]; then
        log "ERROR" "Installation path cannot contain spaces: '$dir'"
        if [[ "${non_interactive}" == "false" ]]; then
            echo -e "${red}Error:${reset} Installation path cannot contain spaces."
            choose_installation_path
            return
        else
            cleanup_and_exit 1 "${red}Error:${reset} Installation path cannot contain spaces in non-interactive mode."
        fi
    fi
    
    # Resolve to absolute path if relative
    if [[ ! "$dir" =~ ^/ ]]; then
        dir="$(pwd)/$dir"
        log "INFO" "Converted to absolute path: $dir"
    fi
    
    log "INFO" "FiveM will be installed in: $dir"
    echo -e "${green}FiveM will be installed in:${reset} ${bold}$dir${reset}"
}

function selectVersion(){
    log "INFO" "Retrieving available versions"
    
    # Use the simpler and more reliable method from the old script
    readarray -t VERSIONS <<< $(curl -s https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/ | egrep -m 3 -o '[0-9].*/fx.tar.xz')
    
    # Check if we found any versions
    if [ ${#VERSIONS[@]} -eq 0 ]; then
        log "ERROR" "No FiveM versions found in server response"
        
        if [[ "${non_interactive}" == "false" ]]; then
            echo -e "${red}${bold}ERROR:${reset} Could not retrieve versions from FiveM server."
            echo -e "${yellow}Do you want to specify a custom download URL?${reset}"
            
            export OPTIONS=("Yes" "No (exit)")
            bashSelect
            
            case $? in
                0)
                    echo -e "${bold}Enter the direct download URL for the FiveM artifact:${reset}"
                    read -p "> " artifacts_version
                    return
                    ;;
                1)
                    cleanup_and_exit 1 "Installation cancelled by user."
                    ;;
            esac
        else
            cleanup_and_exit 1 "Could not retrieve FiveM versions in non-interactive mode."
        fi
    fi

    # Extract full version strings
    full_latest_recommended=$(echo "${VERSIONS[0]}" | cut -d'/' -f1)
    full_latest=$(echo "${VERSIONS[2]}" | cut -d'/' -f1 2>/dev/null || echo "${VERSIONS[0]}" | cut -d'/' -f1)
    
    # Extract just the version numbers (before the dash if present)
    latest_recommended=$(echo "$full_latest_recommended" | cut -d'-' -f1)
    latest=$(echo "$full_latest" | cut -d'-' -f1)
    
    log "INFO" "Latest recommended version: $latest_recommended"
    log "INFO" "Latest version: $latest"

    if [[ "${artifacts_version}" == "0" ]]; then
        if [[ "${non_interactive}" == "false" ]]; then
            status "Select a runtime version"
            echo -e "${cyan}FiveM requires a runtime version to operate. Select from the options below:${reset}\n"
            
            # Create options array for bashSelect
            export OPTIONS=(
                "Latest version → ${latest} (newest, may be experimental)"
                "Latest recommended version → ${latest_recommended} (stable, recommended for production)"
                "Choose custom version (advanced)"
                "Exit without installing"
            )
            
            bashSelect
            version_choice=$?
            
            case $version_choice in
                0)
                    artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${full_latest}/fx.tar.xz"
                    log "INFO" "Selected version: latest version ($latest)"
                    echo -e "${green}Selected version:${reset} Latest version (${bold}$latest${reset})"
                    ;;
                1)
                    artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${full_latest_recommended}/fx.tar.xz"
                    log "INFO" "Selected version: latest recommended version ($latest_recommended)"
                    echo -e "${green}Selected version:${reset} Latest recommended version (${bold}$latest_recommended${reset})"
                    ;;
                2)
                    clear
                    echo -e "${bold}Available versions:${reset}"
                    log "INFO" "Showing all available versions for user selection"
                    
                    # Get more versions to choose from
                    local all_full_versions=$(curl -s https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/ | grep -oP '[0-9]+\.[0-9]+\.[0-9]+/' | sort -Vr)
                    
                    # Create array of versions for bashSelect
                    local version_options=()
                    local version_urls=()
                    local i=0
                    
                    echo -e "${cyan}Recent versions:${reset}"
                    while read version && [ $i -lt 10 ]; do
                        if [ -n "$version" ]; then
                            # Extract just the version number (remove trailing slash)
                            clean_version=${version%/}
                            version_options+=("Version ${clean_version}")
                            version_urls+=("https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/$clean_version/fx.tar.xz")
                            i=$((i+1))
                        fi
                    done <<< "$all_full_versions"
                    
                    # Add option for custom URL
                    version_options+=("Enter custom version or URL")
                    version_options+=("Go back to main version selection")
                    
                    export OPTIONS=("${version_options[@]}")
                    bashSelect
                    selected_index=$?
                    
                    if [ $selected_index -eq $((${#version_options[@]} - 1)) ]; then
                        # Go back to main selection
                        selectVersion
                        return
                    elif [ $selected_index -eq $((${#version_options[@]} - 2)) ]; then
                        # Custom version/URL entry
                        echo -e "${yellow}Enter a version number or paste a complete download URL:${reset}"
                        read -p "> " custom_version
                        
                        # Check if it's a URL
                        if [[ "$custom_version" =~ ^https?:// ]]; then
                            artifacts_version="$custom_version"
                        else
                            artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/$custom_version/fx.tar.xz"
                        fi
                        log "INFO" "Custom version/URL selected: $artifacts_version"
                        echo -e "${green}Custom selection:${reset} ${bold}$artifacts_version${reset}"
                    else
                        # Selected a version from the list
                        artifacts_version="${version_urls[$selected_index]}"
                        selected_version=$(echo "${version_options[$selected_index]}" | sed 's/Version //')
                        log "INFO" "Selected version by index: $selected_version"
                        echo -e "${green}Selected version:${reset} ${bold}$selected_version${reset}"
                    fi
                    ;;
                3)
                    log "INFO" "Installation cancelled by user"
                    cleanup_and_exit 0 "${yellow}Installation cancelled by user.${reset}"
                    ;;
            esac

            return
        else
            artifacts_version="latest"
            log "INFO" "Non-interactive mode: using latest version"
        fi
    fi
    
    if [[ "${artifacts_version}" == "latest" ]]; then
        artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${full_latest}/fx.tar.xz"
        log "INFO" "Using latest version: $latest"
        echo -e "${green}Using latest version:${reset} ${bold}$latest${reset}"
    fi
    
    # Validate the URL
    if ! validate_url "$artifacts_version"; then
        log "ERROR" "Invalid artifacts URL: $artifacts_version"
        if [[ "${non_interactive}" == "false" ]]; then
            echo -e "${red}${bold}ERROR:${reset} The specified URL is invalid or cannot be reached."
            selectVersion
        else
            cleanup_and_exit 1 "Invalid artifacts URL in non-interactive mode: $artifacts_version"
        fi
    fi
}

function examServData() {
  runCommand "mkdir -p $dir/server-data" "Creating server-data directory"
  runCommand "git clone -q https://github.com/citizenfx/cfx-server-data.git $dir/server-data" "Downloading server data"
  status "Creating example server.cfg file"

  cat << EOF > $dir/server-data/server.cfg
# Only change the IP if you're using a server with multiple network interfaces, otherwise change the port only.
endpoint_add_tcp "0.0.0.0:30120"
endpoint_add_udp "0.0.0.0:30120"

# These resources will start by default.
ensure mapmanager
ensure chat
ensure spawnmanager
ensure sessionmanager
ensure basic-gamemode
ensure hardcap
ensure rconlog

# This allows players to use scripthook-based plugins such as the legacy Lambda Menu.
# Set this to 1 to allow scripthook. Do note that this does _not_ guarantee players won't be able to use external plugins.
sv_scriptHookAllowed 0

# Uncomment this and set a password to enable RCON. Make sure to change the password - it should look like set rcon_password "YOURPASSWORD"
#set rcon_password ""

# A comma-separated list of tags for your server.
# For example:
# - sets tags "drifting, cars, racing"
# Or:
# - sets tags "roleplay, military, tanks"
sets tags "default"

# A valid locale identifier for your server's primary language.
# For example "en-US", "fr-CA", "nl-NL", "de-DE", "en-GB", "pt-BR"
sets locale "en-US" 

# Set an optional server info and connecting banner image url.
# Size doesn't matter, any banner sized image will be fine.
#sets banner_detail "https://url.to/image.png"
#sets banner_connecting "https://url.to/image.png"

# Set your server's hostname. This is not usually shown anywhere in listings.
sv_hostname "FXServer, but unconfigured"

# Set your server's Project Name
sets sv_projectName "My FXServer Project"

# Set your server's Project Description
sets sv_projectDesc "Default FXServer requiring configuration"

# Set Game Build (https://docs.fivem.net/docs/server-manual/server-commands/#sv_enforcegamebuild-build)
#sv_enforceGameBuild 2802

# Nested configs!
#exec server_internal.cfg

# Loading a server icon (96x96 PNG file)
#load_server_icon myLogo.png

# convars which can be used in scripts
set temp_convar "hey world!"

# Remove the \`#\` from the below line if you want your server to be listed as 'private' in the server browser.
# Do not edit it if you *do not* want your server listed as 'private'.
# Check the following url for more detailed information about this:
# https://docs.fivem.net/docs/server-manual/server-commands/#sv_master1-newvalue
#sv_master1 ""

# Add system admins
add_ace group.admin command allow # allow all commands
add_ace group.admin command.quit deny # but don't allow quit
add_principal identifier.fivem:1 group.admin # add the admin to the group

# enable OneSync (required for server-side state awareness)
set onesync on

# Server player slot limit (see https://fivem.net/server-hosting for limits)
sv_maxclients 48

# Steam Web API key, if you want to use Steam authentication (https://steamcommunity.com/dev/apikey)
# -> replace "" with the key
set steam_webApiKey ""

# License key for your server (https://portal.cfx.re)
sv_licenseKey changeme
EOF
  log "INFO" "server.cfg file created successfully"
}

function checkPort(){
    log "DEBUG" "Checking port 40120"
    
    if lsof -i :40120 >> "$LOG_FILE" 2>&1; then
        log "WARN" "Port 40120 is already in use"
        
        if [[ "${non_interactive}" == "false" ]]; then
            if [[ "${kill_txAdmin}" == "0" ]]; then
                status "Port conflict detected"
                echo -e "${red}${bold}Port conflict:${reset} Something is already running on the default TxAdmin port (40120)."
                echo -e "${yellow}This could be another FiveM server or a different application.${reset}"
                
                export OPTIONS=(
                    "Kill process on port 40120" 
                    "Exit script"
                )
                
                bashSelect

                case $? in
                    0 )
                        kill_txAdmin="true"
                        log "INFO" "User chose to kill process on port 40120"
                        ;;
                    1 )
                        log "INFO" "User chose to exit due to port conflict"
                        cleanup_and_exit 0 "Installation cancelled due to port conflict."
                        ;;
                esac
            fi
        fi
        
        if [[ "${kill_txAdmin}" == "true" ]]; then
            status "Stopping process on port 40120"
            
            # Make sure psmisc is installed for fuser command
            if ! command -v fuser &> /dev/null; then
                runCommand "apt -y install psmisc" "Installing psmisc package for fuser command" 1 1
            fi
            
            # Try to identify the process using the port
            pid=$(lsof -ti :40120)
            if [ -n "$pid" ]; then
                proc_name=$(ps -p "$pid" -o comm=)
                log "INFO" "Found process using port 40120: PID $pid ($proc_name)"
                echo -e "${yellow}Found process:${reset} $proc_name (PID: $pid)"
            fi
            
            # Kill the process
            runCommand "fuser -k -n tcp 40120" "Forcefully stopping process on port 40120" 1 0
            
            # Verify the port is now free
            sleep 2
            if lsof -i :40120 >> "$LOG_FILE" 2>&1; then
                log "ERROR" "Failed to free port 40120, process is still running"
                echo -e "${red}${bold}ERROR:${reset} Failed to stop the process on port 40120."
                echo -e "${yellow}You may need to manually stop the process or restart your server.${reset}"
                
                if [[ "${non_interactive}" == "false" ]]; then
                    echo -e "${yellow}Do you want to continue anyway? This may cause issues.${reset}"
                    read -p "Continue? (y/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        cleanup_and_exit 1 "Installation aborted due to port conflict."
                    fi
                else
                    cleanup_and_exit 1 "Installation aborted due to port conflict in non-interactive mode."
                fi
            else
                log "SUCCESS" "Successfully freed port 40120"
                echo -e "${green}Successfully freed port 40120${reset}"
            fi
            
            return
        fi

        log "ERROR" "Port 40120 is in use and kill_txAdmin is not set to true"
        cleanup_and_exit 1 "${red}${bold}ERROR:${reset} Port 40120 is already in use. Use --kill-port to force stop the running process."
    fi
    
    log "DEBUG" "Port 40120 is available"
}

function checkDir(){
    log "DEBUG" "Checking if directory $dir already exists"
    
    if [[ -e $dir ]]; then
        log "WARN" "Directory $dir already exists"
        
        if [[ "${non_interactive}" == "false" ]]; then
            if [[ "${delete_dir}" == "0" ]]; then
                status "Directory already exists"
                echo -e "${red}${bold}Directory conflict:${reset} The directory $dir already exists."
                echo -e "${yellow}This could be an existing FiveM server or other files.${reset}"
                
                export OPTIONS=(
                    "Remove everything in $dir" 
                    "Exit script"
                )
                
                bashSelect
                
                case $? in
                    0 )
                    delete_dir="true"
                        log "INFO" "User chose to delete existing directory $dir"
                    ;;
                    1 )
                        log "INFO" "User chose to exit due to directory conflict"
                        cleanup_and_exit 0 "Installation cancelled due to directory conflict."
                    ;;
                esac
            fi
        fi
        
        if [[ "${delete_dir}" == "true" ]]; then
            status "Removing existing directory"
            
            # Count number of files to be deleted
            file_count=$(find "$dir" -type f | wc -l)
            log "INFO" "Preparing to delete $file_count files in $dir"
            
            if [ $file_count -gt 1000 ]; then
                log "WARN" "Large number of files ($file_count) to delete"
                echo -e "${yellow}${bold}WARNING:${reset} About to delete a large number of files ($file_count)."
                
                if [[ "${non_interactive}" == "false" ]]; then
                    echo -e "${red}${bold}This operation cannot be undone!${reset}"
                    read -p "Are you absolutely sure? (yes/N): " confirm
                    if [[ "$confirm" != "yes" ]]; then
                        log "INFO" "User cancelled deletion of directory with many files"
                        cleanup_and_exit 0 "Operation cancelled by user."
                    fi
                fi
            fi
            
            echo -e "${yellow}Removing directory $dir...${reset}"
            runCommand "rm -rf $dir" "Removing existing directory" 1 1
            
            # Verify directory was deleted
            if [[ -e $dir ]]; then
                log "ERROR" "Failed to delete directory $dir"
                cleanup_and_exit 1 "${red}${bold}ERROR:${reset} Failed to delete directory $dir. Check permissions and try again."
            else
                log "SUCCESS" "Successfully removed directory $dir"
                echo -e "${green}Directory successfully removed${reset}"
            fi
            
            return
        fi

        log "ERROR" "Directory $dir exists and delete_dir is not set to true"
        cleanup_and_exit 1 "${red}${bold}ERROR:${reset} Directory $dir already exists. Use --delete-dir to remove it."
    fi
    
    log "DEBUG" "Directory $dir does not exist, it will be created"
}

function selectDeployment(){
    if [[ "${txadmin_deployment}" == "0" ]]; then
        txadmin_deployment="true"

        if [[ "${non_interactive}" == "false" ]]; then
            status "Select deployment type"
            echo -e "${cyan}FiveM offers different ways to set up your server:${reset}"
            echo -e "${blue}• TxAdmin:${reset} Web-based admin panel for easy server management (recommended)"
            echo -e "${blue}• cfx-server-data:${reset} Basic setup without the admin panel (advanced)\n"
            
            export OPTIONS=(
                "Install template via TxAdmin (recommended)" 
                "Use cfx-server-data (advanced)" 
                "Exit installation"
            )
            
            bashSelect

            case $? in
                0 )
                    txadmin_deployment="true"
                    log "INFO" "Deployment type: TxAdmin"
                    echo -e "${green}Selected:${reset} TxAdmin deployment"
                    ;;
                1 )
                    txadmin_deployment="false"
                    log "INFO" "Deployment type: cfx-server-data"
                    echo -e "${green}Selected:${reset} cfx-server-data deployment"
                    ;;
                2 )
                    log "INFO" "Installation cancelled by user at deployment selection"
                    cleanup_and_exit 0 "${yellow}Installation cancelled by user.${reset}"
                    ;;
            esac
        fi
    fi
    
    if [[ "${txadmin_deployment}" == "false" ]]; then
        log "INFO" "Setting up server with cfx-server-data"
        echo -e "${blue}Setting up server with cfx-server-data...${reset}"
        examServData
    else
        log "INFO" "Server will be configured using TxAdmin web interface"
        echo -e "${blue}Server will be configured using TxAdmin web interface after installation${reset}"
    fi
}

function createCrontab(){
    if [[ "${crontab_autostart}" == "0" ]]; then
        crontab_autostart="false"

        if [[ "${non_interactive}" == "false" ]]; then
            status "Automatic server startup"
            echo -e "${cyan}Would you like the FiveM server to start automatically when the system boots?${reset}"
            echo -e "${blue}This is recommended for production servers.${reset}"
            
            export OPTIONS=(
                "Yes - Enable automatic startup (recommended)" 
                "No - I'll start the server manually"
            )
            
            bashSelect

            if [[ $? == 0 ]]; then
                crontab_autostart="true"
                log "INFO" "Automatic startup enabled"
                echo -e "${green}Automatic startup will be enabled${reset}"
            else
                log "INFO" "Automatic startup disabled"
                echo -e "${yellow}Automatic startup will be disabled${reset}"
            fi
        fi
    fi
    
    if [[ "${crontab_autostart}" == "true" ]]; then
        status "Configuring automatic startup"
        
        # Create a more robust crontab entry with logging
        crontab_content="@reboot root /bin/bash $dir/start.sh > $dir/autostart.log 2>&1"
        
        runCommand "echo \"$crontab_content\" > /etc/cron.d/fivem" "Configuring automatic startup via crontab" 1 0
        runCommand "chmod 644 /etc/cron.d/fivem" "Setting proper permissions for crontab file" 1 0
        
        log "SUCCESS" "Crontab entry created for automatic startup"
        echo -e "${green}✓ Automatic startup configured successfully${reset}"
        echo -e "${blue}The server will start automatically on system boot${reset}"
    else
        log "INFO" "Skipping automatic startup configuration"
        echo -e "${yellow}ℹ Automatic startup was not configured${reset}"
        echo -e "${blue}To start the server manually, run:${reset} ${bold}sh $dir/start.sh${reset}"
    fi
}

function installPma(){
    if [[ "${non_interactive}" == "false" ]]; then
        if [[ "${install_phpmyadmin}" == "0" ]]; then
            status "Database Configuration"
            echo -e "${cyan}FiveM can use a database to store persistent data.${reset}"
            echo -e "${blue}You can install MariaDB/MySQL and phpMyAdmin, or use an existing database.${reset}\n"
            
            export OPTIONS=(
                "Install MariaDB/MySQL and phpMyAdmin (recommended for new users)" 
                "Use existing database" 
                "Do not configure database"
            )

            bashSelect

            case $? in
                0 )
                    install_phpmyadmin="true"
                    existing_db_configured=false
                    log "INFO" "phpMyAdmin installation enabled"
                    echo -e "${green}MariaDB/MySQL and phpMyAdmin installation selected${reset}"
                    ;;
                1 )
                    install_phpmyadmin="false"
                    existing_db_configured=true
                    log "INFO" "Existing database configuration selected"
                    echo -e "${green}Existing database configuration selected${reset}"
                    configureExistingDatabase
                    ;;
                2 )
                    install_phpmyadmin="false"
                    existing_db_configured=false
                    log "INFO" "No database installation/configuration"
                    echo -e "${yellow}No database will be configured${reset}"
                    ;;
            esac
        fi
    fi
    
    if [[ "${install_phpmyadmin}" == "true" ]]; then
        log "INFO" "Installing phpMyAdmin and MariaDB"
        echo -e "\n${bold}${yellow}Installing MariaDB 11.4 and phpMyAdmin...${reset}"
        echo -e "${blue}This process may take several minutes. Please wait...${reset}\n"
        
        # Show progress during installation by not hiding output
        runCommand "bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/phpmyadmin.sh) -s ${pma_options[*]}" "Installing phpMyAdmin and MariaDB/MySQL" 0 1
        
        echo -e "\n${green}✓ MariaDB and phpMyAdmin installation completed!${reset}"
    fi
}

# Function to configure an existing database
function configureExistingDatabase() {
    log "INFO" "Configuring connection to existing database"
    echo -e "${blue}Please provide connection information for your existing database.${reset}"
    echo -e "${yellow}This information will be used to configure your FiveM server.${reset}\n"
    
    read -p "Database host [localhost]: " input_db_host
    existing_db_host=${input_db_host:-"localhost"}
    
    read -p "Database name [fivem]: " input_db_name
    existing_db_name=${input_db_name:-"fivem"}
    
    read -p "Database user [fivem]: " input_db_user
    existing_db_user=${input_db_user:-"fivem"}
    
    read -p "Database password: " input_db_password
    existing_db_password=${input_db_password}
    
    # Connection verification if possible
    if command -v mysql &> /dev/null; then
        log "INFO" "Attempting to verify database connection"
        echo -e "${blue}Verifying database connection...${reset}"
        
        if mysql -h "$existing_db_host" -u "$existing_db_user" -p"$existing_db_password" "$existing_db_name" -e "SELECT 1" &>/dev/null; then
            log "SUCCESS" "Database connection successful"
            echo -e "${green}✓ Database connection successful!${reset}"
        else
            log "WARN" "Unable to connect to database with provided information"
            echo -e "${yellow}⚠ Unable to verify database connection.${reset}"
            echo -e "${yellow}The information will still be saved, but you'll need to verify the configuration manually.${reset}"
            
            # Give user the option to retry
            read -p "Do you want to try again? (Y/n): " retry
            if [[ "$retry" != "n" && "$retry" != "N" ]]; then
                configureExistingDatabase
                return
            fi
        fi
    else
        log "INFO" "MySQL client not available, unable to verify connection"
        echo -e "${yellow}MySQL client not available to verify connection.${reset}"
        echo -e "${yellow}The information will be saved, but you'll need to verify the connection manually.${reset}"
    fi
    
    log "INFO" "Existing database information configured"
    echo -e "${green}Database information saved:${reset}"
    echo -e "  ${blue}Host:${reset} $existing_db_host"
    echo -e "  ${blue}Database:${reset} $existing_db_name"
    echo -e "  ${blue}User:${reset} $existing_db_user"
    echo -e "  ${blue}Password:${reset} $(echo "$existing_db_password" | sed 's/./*/g')"
}

function install(){
    log "INFO" "Starting FiveM installation"
    
    # Banner
    echo -e "\n${cyan}╔═══════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║ ${bold}${green}                     FIVEM SERVER INSTALLER                          ${reset}${cyan}║${reset}"
    echo -e "${cyan}║ ${reset}${blue}                      Version: $script_version                        ${reset}${cyan}║${reset}"
    echo -e "${cyan}╚═══════════════════════════════════════════════════════════════════════╝${reset}\n"
    
    # Create log file
    > $LOG_FILE
    
    # System checks and information gathering
    gather_system_info
    
    # Install required packages
    echo -e "\n${bold}${yellow}Installing required packages...${reset}"
    runCommand "apt update -y" "Updating package repository" 1 0
    
    local required_packages="wget git curl dos2unix net-tools sed screen xz-utils lsof iproute2 ca-certificates"
    
    # Check which required packages are already installed
    local packages_to_install=""
    for package in $required_packages; do
        if ! dpkg -l | grep -q "ii  $package "; then
            packages_to_install="$packages_to_install $package"
        fi
    done
    
    if [ -n "$packages_to_install" ]; then
        log "INFO" "Installing required packages: $packages_to_install"
        runCommand "apt install -y $packages_to_install" "Installing necessary packages" 1 1
    else
        log "INFO" "All required packages are already installed"
        echo -e "${green}✓ All required packages are already installed${reset}"
    fi
    
    # Choose the installation path
    choose_installation_path
    
    # Run pre-installation checks
    checkPort
    checkDir
    selectDeployment
    selectVersion
    createCrontab
    installPma

    # Create server directory
    echo -e "\n${bold}${yellow}Setting up FiveM server environment...${reset}"
    runCommand "mkdir -p $dir/server" "Creating server directories" 1 1
    runCommand "cd $dir/server/" "Navigating to server directory" 1 0

    # Download FiveM server
    echo -e "\n${bold}${yellow}Downloading FiveM server files...${reset}"
    log "INFO" "Downloading FxServer from $artifacts_version"
    
    # Download with progress bar
    echo -e "${blue}Downloading FxServer...${reset}"
    
    # Use wget with progress bar but log to file
    wget_log=$(mktemp)
    wget --progress=bar:force:noscroll \
         --show-progress \
         -O "$dir/server/fx.tar.xz" \
         "$artifacts_version" 2>&1 | tee "$wget_log"
         
    # Check if download was successful
    if [ ! -f "$dir/server/fx.tar.xz" ] || [ ! -s "$dir/server/fx.tar.xz" ]; then
        cat "$wget_log" >> "$LOG_FILE"
        rm -f "$wget_log"
        log "ERROR" "Failed to download FxServer from $artifacts_version"
        cleanup_and_exit 1 "${red}${bold}ERROR:${reset} Failed to download FxServer. Check the log for details: $LOG_FILE"
    fi
    
    rm -f "$wget_log"
    log "SUCCESS" "Successfully downloaded FxServer"
    
    # Extract the server files
    echo -e "${blue}Extracting FxServer archive...${reset}"
    runCommand "tar xf $dir/server/fx.tar.xz -C $dir/server/" "Extracting FxServer archive" 1 1
    runCommand "rm $dir/server/fx.tar.xz" "Removing downloaded archive" 1 0
    
    # Create management scripts
    echo -e "\n${bold}${yellow}Creating management scripts...${reset}"
    log "INFO" "Creating start, stop and access scripts"
    
    # Create start script
    cat << EOF > $dir/start.sh
#!/bin/bash
# FiveM Server Starter Script
# Created by FiveM Server Installer v${script_version}
# https://github.com/Dolyyyy/fiveminstaller

# Colors
red="\e[0;91m"
green="\e[0;92m"
yellow="\e[0;93m"
blue="\e[0;94m"
magenta="\e[0;95m"
cyan="\e[0;96m"
bold="\e[1m"
reset="\e[0m"

echo -e "\${cyan}╔═══════════════════════════════════════════════════════════════╗\${reset}"
echo -e "\${cyan}║ \${bold}\${green}                 FIVEM SERVER STARTER                  \${reset}\${cyan}║\${reset}"
echo -e "\${cyan}╚═══════════════════════════════════════════════════════════════╝\${reset}"

port=\$(lsof -Pi :40120 -sTCP:LISTEN -t)
if [ -z "\$port" ]; then
    echo -e "\${blue}Starting TxAdmin...\${reset}"
    # Check for updates before starting (optional)
    # echo -e "\${yellow}Checking for FiveM updates...\${reset}"
    # cd $dir && bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh) -u $dir
    
    # Start the server
    screen -dmS fivem sh $dir/server/run.sh
    
    # Wait for server to start
    echo -e "\${yellow}Waiting for TxAdmin to start...\${reset}"
    for i in {1..10}; do
        if lsof -Pi :40120 -sTCP:LISTEN -t > /dev/null; then
            echo -e "\n\${green}\${bold}TxAdmin was started successfully!\${reset}"
            echo -e "\${green}Web Interface: http://\$(hostname -I | awk '{print \$1}'):40120\${reset}"
            exit 0
        fi
        printf "."
        sleep 1
    done
    echo -e "\n\${yellow}TxAdmin seems to be starting slowly. Check status manually.\${reset}"
else
    echo -e "\n\${red}The default \${reset}\${bold}TxAdmin\${reset}\${red} port is already in use -> Is a \${reset}\${bold}FiveM Server\${reset}\${red} already running?\${reset}"
fi
EOF
    runCommand "chmod +x $dir/start.sh" "Making the start script executable" 1 0

    # Create attach script with a more informative header
    cat << EOF > $dir/attach.sh
#!/bin/bash
# FiveM Server Console Access
# Created by FiveM Server Installer v${script_version}
# https://github.com/Dolyyyy/fiveminstaller

# Colors
red="\e[0;91m"
green="\e[0;92m"
bold="\e[1m"
reset="\e[0m"

echo -e "\${green}Connecting to FiveM server console...\${reset}"
echo -e "\${red}Press \${bold}Ctrl+A\${reset} \${red}then \${bold}D\${reset} \${red}to detach from console\${reset}"
sleep 2
screen -xS fivem
EOF
    runCommand "chmod +x $dir/attach.sh" "Making the attach script executable" 1 0

    # Create stop script with confirmation
    cat << EOF > $dir/stop.sh
#!/bin/bash
# FiveM Server Stop Script
# Created by FiveM Server Installer v${script_version}
# https://github.com/Dolyyyy/fiveminstaller

# Colors
red="\e[0;91m"
green="\e[0;92m"
yellow="\e[0;93m"
bold="\e[1m"
reset="\e[0m"

echo -e "\${red}WARNING: \${bold}You are about to stop the FiveM server!\${reset}"
echo -e "\${yellow}All players will be disconnected.\${reset}"
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo

if [[ \$REPLY =~ ^[Yy]\$ ]]; then
    echo -e "\${yellow}Stopping FiveM server...\${reset}"
    screen -XS fivem quit
    sleep 2
    if ! screen -list | grep -q "fivem"; then
        echo -e "\${green}FiveM server stopped successfully.\${reset}"
    else
        echo -e "\${red}Failed to stop FiveM server. Try again or check the server status.\${reset}"
    fi
else
    echo -e "\${green}Operation canceled. Server continues running.\${reset}"
fi
EOF
    runCommand "chmod +x $dir/stop.sh" "Making the stop script executable" 1 0
    
    # Create update script for easy updates
    cat << EOF > $dir/update.sh
#!/bin/bash
# FiveM Server Update Script
# Created by FiveM Server Installer v${script_version}
# https://github.com/Dolyyyy/fiveminstaller

# Colors
red="\e[0;91m"
green="\e[0;92m"
yellow="\e[0;93m"
bold="\e[1m"
reset="\e[0m"

echo -e "\${yellow}This script will update your FiveM server to the latest version.\${reset}"
echo -e "\${red}WARNING: \${bold}The server will be stopped if it's running!\${reset}"
read -p "Continue? (y/N): " -n 1 -r
echo

if [[ \$REPLY =~ ^[Yy]\$ ]]; then
    # Check if server is running and stop it
    if screen -list | grep -q "fivem"; then
        echo -e "\${yellow}Stopping FiveM server...\${reset}"
        screen -XS fivem quit
        sleep 2
    fi
    
    # Run the updater
    echo -e "\${green}Starting update process...\${reset}"
    bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh) -u $dir
fi
EOF
    runCommand "chmod +x $dir/update.sh" "Creating update script" 1 0

    # Check if port 40120 is free to launch TxAdmin
    port=$(lsof -Pi :40120 -sTCP:LISTEN -t)

    if [[ -z "$port" ]]; then
        log "INFO" "Starting TxAdmin for first-time setup"
        echo -e "\n${bold}${yellow}Starting TxAdmin for first-time setup...${reset}"

        # Clean up existing log file
        if [[ -e '/tmp/fivem.log' ]]; then
        rm /tmp/fivem.log
        fi
        
        # Start TxAdmin in a screen session with enhanced logging
        log "INFO" "Starting TxAdmin with enhanced logging"
        screen -L -Logfile /tmp/fivem.log -dmS fivem $dir/server/run.sh
        
        # Also create a separate process to monitor the screen output
        (
            while true; do
                if screen -list | grep -q "fivem"; then
                    # Capture screen output directly
                    screen -S fivem -X hardcopy /tmp/fivem_screen.txt
                    # If screen output contains PIN, copy it to our main log
                    if [ -f "/tmp/fivem_screen.txt" ] && grep -q "Use the PIN below to register" /tmp/fivem_screen.txt 2>/dev/null; then
                        cat /tmp/fivem_screen.txt >> /tmp/fivem.log
                        break
                    fi
                    sleep 2
                else
                    break
                fi
            done
        ) &
        monitor_pid=$!

        # Wait for TxAdmin to start
        echo -e "${blue}Waiting for TxAdmin to start...${reset}"
        local max_attempts=60
        local started=false
        
        for ((i=1; i<=max_attempts; i++)); do
            if grep -q "able to access" /tmp/fivem.log 2>/dev/null; then
                started=true
                break
            fi
            printf "."
            sleep 1
        done

        echo
        
        if [ "$started" = true ]; then
            log "SUCCESS" "TxAdmin started successfully"
            
            # Wait specifically for the PIN to be displayed in the box format
            echo -e "${blue}Waiting for PIN to be generated...${reset}"
            local pin_attempts=45
            local pin_found=false
            
            for ((j=1; j<=pin_attempts; j++)); do
                # Check if the PIN box is displayed
                if grep -q "Use the PIN below to register" /tmp/fivem.log 2>/dev/null; then
                    # Wait more time to ensure the PIN line is written completely
                    sleep 5
                    pin_found=true
                    log "DEBUG" "PIN message found, waiting for PIN to be fully written"
                    break
                fi
                printf "."
                sleep 1
            done
            
            echo
            
            if [ "$pin_found" = true ]; then
                log "INFO" "PIN box detected, extracting PIN"
                
                # DEBUG: Show what's actually in the log file around the PIN
                log "DEBUG" "Content around PIN in fivem.log:"
                grep -A 10 -B 5 "Use the PIN below to register" /tmp/fivem.log >> "$LOG_FILE" 2>&1
                
                # Extract the PIN from the log file
                # TxAdmin displays the PIN in a box format like:
                # ┃   Use the PIN below to register:   ┃
                # ┃                9334                ┃
                
                # Method 1: Look for the line immediately after "Use the PIN below to register"
                pin=$(grep -A 3 "Use the PIN below to register" /tmp/fivem.log | grep -E "┃\s*[0-9]{4}\s*┃" | grep -oE "[0-9]{4}" | tail -1)
                log "DEBUG" "Method 1 result: '$pin'"
                
                # Method 2: Look for any line with the box pattern containing exactly 4 digits
                if [ -z "$pin" ]; then
                    pin=$(grep -E "┃\s*[0-9]{4}\s*┃" /tmp/fivem.log | grep -oE "[0-9]{4}" | tail -1)
                    log "DEBUG" "Method 2 result: '$pin'"
                fi
                
                # Method 3: Look for 4 digits in the context of the PIN box (larger context)
                if [ -z "$pin" ]; then
                    pin=$(grep -A 10 "Use the PIN below to register" /tmp/fivem.log | grep -oE "[0-9]{4}" | tail -1)
                    log "DEBUG" "Method 3 result: '$pin'"
                fi
                
                # Method 4: Look for any 4-digit number after the PIN message
                if [ -z "$pin" ]; then
                    pin_line_num=$(grep -n "Use the PIN below to register" /tmp/fivem.log | tail -1 | cut -d: -f1)
                    if [ -n "$pin_line_num" ]; then
                        # Get the next 5 lines after the PIN message
                        pin=$(sed -n "$((pin_line_num+1)),$((pin_line_num+5))p" /tmp/fivem.log | grep -oE "[0-9]{4}" | head -1)
                        log "DEBUG" "Method 4 (line $pin_line_num) result: '$pin'"
                    fi
                fi
                
                # Method 5: Search for specific Unicode characters followed by 4 digits
                if [ -z "$pin" ]; then
                    pin=$(grep -oP "┃\s*\K[0-9]{4}(?=\s*┃)" /tmp/fivem.log | tail -1)
                    log "DEBUG" "Method 5 (Unicode pattern) result: '$pin'"
                fi
                
                # Method 6: Final fallback - last 4-digit number in the file
                if [ -z "$pin" ]; then
                    pin=$(grep -oE "[0-9]{4}" /tmp/fivem.log | tail -1)
                    log "DEBUG" "Method 6 (fallback) result: '$pin'"
                fi
                
                # Validate that we have exactly a 4-digit PIN
                if [[ "$pin" =~ ^[0-9]{4}$ ]]; then
                    log "INFO" "PIN extracted successfully: $pin"
                    
                    # Additional verification: show the exact line where PIN was found
                    pin_context=$(grep -A 2 -B 2 "$pin" /tmp/fivem.log | tail -5)
                    log "DEBUG" "PIN found in context: $pin_context"
                else
                    pin="unknown"
                    log "WARN" "Could not extract valid 4-digit PIN from logs. Found: '$pin'"
                    # Debug: show more of the log
                    log "DEBUG" "Last 20 lines of fivem.log:"
                    tail -20 /tmp/fivem.log >> "$LOG_FILE" 2>&1
                    log "DEBUG" "All 4-digit numbers found in log:"
                    grep -oE "[0-9]{4}" /tmp/fivem.log >> "$LOG_FILE" 2>&1
                fi
            else
                pin="unknown"
                log "WARN" "PIN box was not detected in the expected time"
                # Debug: show the entire log to see what we captured
                log "DEBUG" "Complete fivem.log content:"
                cat /tmp/fivem.log >> "$LOG_FILE" 2>&1
            fi
            
            # Get the server IP address and TxAdmin URL
            server_ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
            txadmin="http://${server_ip}:40120"
            
            # Display server information
            clear
            echo -e "\n${cyan}╔═══════════════════════════════════════════════════════════════════════╗${reset}"
            echo -e "${cyan}║ ${bold}${green}                    FIVEM SERVER INSTALLED                         ${reset}${cyan}║${reset}"
            echo -e "${cyan}╚═══════════════════════════════════════════════════════════════════════╝${reset}\n"
            
            echo -e "${green}${bold}TxAdmin${reset}${green} was started successfully!${reset}"
            
            echo -e "\n${bold}${yellow}SERVER INFORMATION${reset}"
            echo -e "${blue}TxAdmin Web Interface:${reset} ${bold}${txadmin}${reset}"
            echo -e "${blue}Initial PIN:${reset} ${bold}${pin}${reset} (use it in the next 5 minutes!)"
            echo -e "${blue}Server Data Path:${reset} ${bold}$dir/server-data${reset}"
            
            echo -e "\n${bold}${yellow}MANAGEMENT COMMANDS${reset} ${cyan}(via SSH)${reset}"
            echo -e "${blue}Start Server:${reset}   ${bold}sh $dir/start.sh${reset}"
            echo -e "${blue}Stop Server:${reset}    ${bold}sh $dir/stop.sh${reset}"
            echo -e "${blue}View Console:${reset}   ${bold}sh $dir/attach.sh${reset}"
            echo -e "${blue}Update Server:${reset}  ${bold}sh $dir/update.sh${reset}"

            if [[ "$install_phpmyadmin" == "true" ]]; then
                echo -e "\n${bold}${yellow}DATABASE INFORMATION${reset}"
                # Get database credentials from MariaDB files
                if [ -f "/root/.mariadbPhpma" ]; then
                    runCommand "cat /root/.mariadbPhpma" "Reading MariaDB login information" 1 0
                    runCommand "rm /root/.mariadbPhpma" "Removing temporary MariaDB file" 1 0
                fi
                
                rootPasswordMariaDB=""
                if [ -f "/root/.mariadbRoot" ]; then
                    rootPasswordMariaDB=$( cat /root/.mariadbRoot )
                    rm /root/.mariadbRoot
                fi
                
                # Create FiveM database and user
                fivempasswd=$( pwgen 32 1 );
                if [ -n "$rootPasswordMariaDB" ]; then
                    mariadb -u root -p$rootPasswordMariaDB -e "CREATE DATABASE IF NOT EXISTS fivem;"
                    mariadb -u root -p$rootPasswordMariaDB -e "GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost' IDENTIFIED BY '${fivempasswd}';"
                    mariadb -u root -p$rootPasswordMariaDB -e "FLUSH PRIVILEGES;"
                    
                    echo -e "${blue}Database Name:${reset} ${bold}fivem${reset}"
                    echo -e "${blue}Database User:${reset} ${bold}fivem${reset}"
                    echo -e "${blue}Database Password:${reset} ${bold}${fivempasswd}${reset}"
                    echo -e "${blue}MySQL Connection String:${reset}"
                    echo -e "${bold}set mysql_connection_string \"server=127.0.0.1;database=fivem;userid=fivem;password=${fivempasswd}\"${reset}"
                    
                    if [ -f "/root/.PHPma" ]; then
                        runCommand "cat /root/.PHPma" "Reading phpMyAdmin information" 1 0
                    fi
                else
                    log "WARN" "Could not retrieve root MariaDB password"
                    echo -e "${yellow}Note: Could not configure the FiveM database automatically.${reset}"
                    echo -e "${yellow}You may need to set up the database manually.${reset}"
                fi
            fi
            
            # Create installation info file
            create_installation_info
            
            # Clean up monitoring process and temporary files
            if [ -n "$monitor_pid" ]; then
                kill $monitor_pid 2>/dev/null || true
            fi
            rm -f /tmp/fivem_screen.txt
            
            echo -e "\n${bold}${green}Installation information has been saved to:${reset} $dir/installation_info.txt"
            echo -e "${yellow}Please save this information for future reference!${reset}\n"
        else
            log "ERROR" "TxAdmin did not start in the expected time"
            
            # Clean up monitoring process and temporary files
            if [ -n "$monitor_pid" ]; then
                kill $monitor_pid 2>/dev/null || true
            fi
            rm -f /tmp/fivem_screen.txt
            
            echo -e "${red}${bold}WARNING:${reset} TxAdmin did not start in the expected time."
            echo -e "${yellow}You may need to manually start it using:${reset} ${bold}sh $dir/start.sh${reset}"
            echo -e "${yellow}Check the logs for more information:${reset} ${bold}less /tmp/fivem.log${reset}"
        fi
    else
        log "ERROR" "TxAdmin port 40120 is already in use"
        echo -e "\n${red}${bold}ERROR:${reset} The default ${bold}TxAdmin${reset} port (40120) is already in use."
        echo -e "${yellow}This could indicate that a FiveM server is already running.${reset}"
        echo -e "${yellow}Please stop any existing FiveM servers or change the port and try again.${reset}"
        
        # Save basic installation info even if TxAdmin didn't start
        create_installation_info
    fi
}

# Function to create the installation info file
create_installation_info() {
    log "INFO" "Creating installation information file"
    
    # Create the info file with a nice format
    cat << EOF > $dir/installation_info.txt
┌───────────────────────────────────────────────────────────────────────┐
│                        FIVEM SERVER INFORMATION                        │
└───────────────────────────────────────────────────────────────────────┘

▶ INSTALLATION DETAILS
  • Date: $(date "+%Y-%m-%d %H:%M:%S")
  • Host: $(hostname)
  • IP Address: $(ip route get 1.1.1.1 | awk '{print $7; exit}')
  • Path: $dir

▶ SERVER ACCESS
  • TxAdmin Web Interface: ${txadmin}
  • Initial Pin: ${pin} (use it in the next 5 minutes!)
  • TxAdmin Port: 40120
  • Default Game Port: 30120

▶ MANAGEMENT SCRIPTS
  • Start Server: sh $dir/start.sh
  • Stop Server: sh $dir/stop.sh
  • View Console: sh $dir/attach.sh
  • Update Server: sh $dir/update.sh

▶ SERVER FILES
  • Server Data: $dir/server-data
  • Server Configuration: $dir/server-data/server.cfg
  • Log File: $LOG_FILE

▶ SYSTEM INFORMATION
  • OS: $SYS_OS
  • Kernel: $SYS_KERNEL
  • CPU: $SYS_CPU ($SYS_CPU_CORES cores)
  • RAM: $SYS_MEM_TOTAL ($SYS_MEM_FREE free)
  • Disk Space: $SYS_DISK_TOTAL ($SYS_DISK_FREE available)

EOF

    if [[ "$install_phpmyadmin" == "true" ]]; then
        cat << EOF >> $dir/installation_info.txt
▶ DATABASE INFORMATION
  • Database Type: MariaDB/MySQL (Installed with this script)
  • Database Name: fivem
  • Database User: fivem
  • Database Password: ${fivempasswd}
  • MySQL Connection String:
    set mysql_connection_string "server=127.0.0.1;database=fivem;userid=fivem;password=${fivempasswd}"
  • phpMyAdmin: http://$(ip route get 1.1.1.1 | awk '{print $7; exit}')/phpmyadmin

EOF
    elif [[ "$existing_db_configured" == "true" ]]; then
        cat << EOF >> $dir/installation_info.txt
▶ DATABASE INFORMATION
  • Database Type: MariaDB/MySQL (External/Pre-existing)
  • Database Host: $existing_db_host
  • Database Name: $existing_db_name
  • Database User: $existing_db_user
  • Database Password: $existing_db_password
  • MySQL Connection String:
    set mysql_connection_string "server=$existing_db_host;database=$existing_db_name;userid=$existing_db_user;password=$existing_db_password"

EOF
    fi

    cat << EOF >> $dir/installation_info.txt
▶ SUPPORT & RESOURCES
  • Installation Script: https://github.com/Dolyyyy/fiveminstaller
  • FiveM Documentation: https://docs.fivem.net/
  • Support Forum: https://forum.cfx.re/
  • Creator's GitHub: https://github.com/Dolyyyy

┌───────────────────────────────────────────────────────────────────────┐
│      ♦ Thank you for using Dolyyyy's FiveM Server Installer! ♦        │
└───────────────────────────────────────────────────────────────────────┘
EOF

    # Set proper permissions
    chmod 644 "$dir/installation_info.txt"
    
    log "INFO" "Installation information has been saved to $dir/installation_info.txt"
}

function update() {
    log "INFO" "Updating FiveM"
    selectVersion

    if [[ "${non_interactive}" == "false" ]]; then
        status "Select the alpine directory"
        readarray -t directories <<<$(find / -name "alpine")
        export OPTIONS=(${directories[*]})

        bashSelect

        dir=${directories[$?]}/..
        log "INFO" "Selected directory: $dir"
    else
        if [[ "$update_artifacts" == false ]]; then
            log "ERROR" "Directory must be specified in non-interactive mode using --update <path>."
            exit 1
        fi
        dir=$update_artifacts
        log "INFO" "Using specified directory: $dir"
    fi

    checkPort

    runCommand "rm -rf $dir/alpine" "Removing alpine directory"
    runCommand "rm -f $dir/run.sh" "Removing run.sh file"
    runCommand "wget --directory-prefix=$dir $artifacts_version" "Downloading fx.tar.xz"
    log "INFO" "Download successful"
    runCommand "tar xf $dir/fx.tar.xz -C $dir" "Extracting fx.tar.xz"
    log "INFO" "Extraction successful"
    runCommand "rm -r $dir/fx.tar.xz" "Removing fx.tar.xz"
    clear
    log "INFO" "Update successful"
    echo "${green}Update successful${reset}"
    exit 0
}

function main(){
    # Initialize log file and set up logging
    setup_logging
    
    # Display welcome banner
    echo -e "\n${cyan}╔═══════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║ ${bold}${green}                      FIVEM SERVER INSTALLER                            ${reset}${cyan}║${reset}"
    echo -e "${cyan}║ ${reset}${blue}                          Version: $script_version                           ${reset}${cyan}║${reset}"
    echo -e "${cyan}║ ${reset}${yellow}            https://github.com/Dolyyyy/fiveminstaller                 ${reset}${cyan}║${reset}"
    echo -e "${cyan}╚═══════════════════════════════════════════════════════════════════════════════╝${reset}\n"
    
    log "INFO" "Starting FiveM Server Installer v$script_version"
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        log "WARN" "curl is not installed, installing now..."
        apt update -y && apt -y install curl
    fi
    
    # Gather basic system information
    log "INFO" "Running on: $(uname -a)"
    log "INFO" "Detected IP: $(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo 'unknown')"

    if [[ "${non_interactive}" == "false" ]]; then
        log "INFO" "Interactive mode enabled"
        
        # Source BashSelect from GitHub
        if ! source <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/bashselect.sh); then
            log "ERROR" "Failed to source BashSelect script"
            echo -e "${red}${bold}ERROR:${reset} Failed to source the BashSelect script. Check your internet connection."
            exit 1
        fi
        
        if [[ "${update_artifacts}" == "false" ]]; then
            status "What would you like to do?"
            
            export OPTIONS=(
                "Install a new FiveM server" 
                "Update an existing FiveM server" 
                "Exit without making changes"
            )
            
            bashSelect

            case $? in
                0 )
                    log "INFO" "User selected: Install a new FiveM server"
                    install
                    ;;
                1 )
                    log "INFO" "User selected: Update an existing FiveM server"
                    update
                    ;;
                2 )
                    log "INFO" "User selected: Exit without making changes"
                    cleanup_and_exit 0 "${green}Exiting without making changes. Goodbye!${reset}"
                    ;;
            esac
        else
            log "INFO" "Update flag detected, running update process"
            update
        fi
        
        # If we got here, we've completed the requested action
        log "INFO" "Operation completed successfully"
        cleanup_and_exit 0 "${green}${bold}Operation completed successfully!${reset}"
    else
        log "INFO" "Non-interactive mode enabled"
    
    if [[ "${update_artifacts}" == "false" ]]; then
            log "INFO" "Running installation in non-interactive mode"
        install
    else
            log "INFO" "Running update in non-interactive mode"
        update
        fi
        
        # If we got here, we've completed the requested action
        log "INFO" "Non-interactive operation completed successfully"
        cleanup_and_exit 0 "${green}${bold}Operation completed successfully!${reset}"
    fi
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo -e "${bold}Usage: bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh) [OPTIONS]${reset}"
            echo "Options:"
            echo "  -h, --help                      Display this help message."
            echo "      --non-interactive           Skip all interactive prompts by providing all required inputs as options."
            echo "                                  If --phpmyadmin is included, you must also choose between --simple or --security."
            echo "                                      When using --security, you must provide both --db_user and --db_password."
            echo "  -v, --version <URL|latest>      Choose an artifacts version."
            echo "                                  Default: latest"
            echo "  -u, --update <path>             Update the artifacts version and specify the directory."
            echo "                                  Use -v or --version to specify the version or it will use the latest version."
            echo "      --no-txadmin                Disable txAdmin deployment and use cfx-server-data."
            echo "  -c, --crontab                   Enable or disable crontab autostart."
            echo "      --kill-port                 Forcefully stop any process running on the TxAdmin port (40120)."
            echo "      --delete-dir                Forcefully delete the /home/FiveM directory if it exists."
            echo "  -d, --dir <path>                Specify a custom installation path."
            echo ""
            echo "PHPMyAdminInstaller Options:"
            echo "  -p, --phpmyadmin                Enable or disable phpMyAdmin installation."
            echo "      --db_user <name>            Specify a database user."
            echo "      --db_password <password>    Set a custom password for the database."
            echo "      --generate_password         Automatically generate a secure password for the database."
            echo "      --reset_password            Reset the database password if one already exists."
            echo "      --remove_db                 Remove MySQL/MariaDB and reinstall it."
            echo "      --remove_pma                Remove phpMyAdmin and reinstall it if it already exists."
            echo ""
            echo "Existing Database Options:"
            echo "  --db-host <host>                Specify the host for the existing database."
            echo "  --db-name <name>                Specify the name for the existing database."
            echo "  --db-user <user>                Specify the user for the existing database."
            echo "  --db-password <password>        Set a custom password for the existing database."
            exit 0
            ;;
        --non-interactive)
            non_interactive=true
            pma_options+=("--non-interactive")
            shift
            ;;
        -v|--version)
            artifacts_version="$2"
            shift 2
            ;;
        -u|--update)
            update_artifacts="$2"
            shift 2
            ;;
        --no-txadmin)
            txadmin_deployment=false
            shift
            ;;
        -p|--phpmyadmin)
            install_phpmyadmin=true
            shift
            ;;
        -c|--crontab)
            crontab_autostart=true
            shift
            ;;
        --kill-port)
            kill_txAdmin=true
            shift
            ;;
        --delete-dir)
            delete_dir=true
            shift
            ;;
        -d|--dir)
            dir="$2"
            shift 2
            ;;

        # PHPMyAdmin installer Options:
        --security)
            pma_options+=("--security")
            shift
            ;;
        --simple)
            pma_options+=("--simple")
            shift
            ;;
        --db_user)
            pma_options+=("--db_user $2")
            shift 2
            ;;
        --db_password)
            pma_options+=("--db_password $2")
            shift 2
            ;;
        --generate_password)
            pma_options+=("--generate_password")
            shift
            ;;
        --reset_password)
            pma_options+=("--reset_password")
            shift
            ;;
        --remove_db)
            pma_options+=("--remove_db")
            shift
            ;;
        --remove_pma)
            pma_options+=("--remove_pma")
            shift
            ;;
        # Existing Database Options:
        --db-host)
            existing_db_host="$2"
            existing_db_configured=true
            shift 2
            ;;
        --db-name)
            existing_db_name="$2"
            existing_db_configured=true
            shift 2
            ;;
        --db-user)
            existing_db_user="$2"
            existing_db_configured=true
            shift 2
            ;;
        --db-password)
            existing_db_password="$2"
            existing_db_configured=true
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "${non_interactive}" == "true" && "${install_phpmyadmin}" == "true" ]]; then
    errors=()

    if ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--security" && 
       ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--simple"; then
        errors+=("${red}Error:${reset} With --non-interactive, either --security or --simple must be set.")
    fi

    if printf "%s\n" "${pma_options[@]}" | grep -q -- "--security"; then
        if ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--db_user"; then
            errors+=("${red}Error:${reset} With --non-interactive and --security, --db_user <user> must be set.")
        fi

        if ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--db_password" && 
           ! printf "%s\n" "${pma_options[@]}" | grep -q -- "--generate_password"; then
            errors+=("${red}Error:${reset} With --non-interactive and --security, either --db_password <password> or --generate_password must be set.")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            echo -e "$error"
        done
        exit 1
    fi
fi

main
