#!/bin/bash

# Colors for messages
red="\e[0;91m"
green="\e[0;92m"
blue="\e[0;94m"
yellow="\e[0;93m"
bold="\e[1m"
reset="\e[0m"

# Log file
LOG_FILE="/tmp/fivem_install.log"

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

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    case $level in
        "INFO") color=$green ;;
        "ERROR") color=$red ;;
        "WARN") color=$yellow ;;
        "DEBUG") color=$blue ;;
        *) color=$reset ;;
    esac
    
    echo -e "${timestamp} [${color}${level}${reset}] ${message}" | tee -a $LOG_FILE
}

# Check that the script is run as root
if [ "$EUID" -ne 0 ]; then
    log "ERROR" "This script must be run as root"
    exit 1
fi

status(){
  clear
  log "INFO" "$@..."
  sleep 1
}

runCommand(){
    COMMAND=$1
    LOG_MSG=${2:-"Executing command"}

    log "DEBUG" "Command: $COMMAND"
    log "INFO" "$LOG_MSG"

    eval $COMMAND >> $LOG_FILE 2>&1
    BASH_CODE=$?
    if [ $BASH_CODE -ne 0 ]; then
      log "ERROR" "An error occurred: $COMMAND returned $BASH_CODE"
      log "ERROR" "Check the log file for more details: $LOG_FILE"
      exit ${BASH_CODE}
    fi
}

# Determine the default installation path
get_default_dir() {
    # If the user is root, use /home/FiveM
    # Otherwise, use the user's home directory
    local current_user=$(who am i | awk '{print $1}')
    
    if [ "$current_user" == "root" ]; then
        echo "/home/FiveM"
    else
        echo "/home/$current_user/FiveM"
    fi
}

# Function to choose the installation path
choose_installation_path() {
    default_dir=$(get_default_dir)
    
    if [[ "${non_interactive}" == "false" ]]; then
        log "INFO" "Choose the installation path for FiveM"
        read -p "Installation path [$default_dir]: " input_dir
        dir=${input_dir:-$default_dir}
    else
        dir=$default_dir
        log "INFO" "Non-interactive mode: using default path $dir"
    fi
    
    log "INFO" "FiveM will be installed in: $dir"
}

function selectVersion(){
    log "INFO" "Retrieving available versions"
    readarray -t VERSIONS <<< $(curl -s https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/ | egrep -m 3 -o '[0-9].*/fx.tar.xz')

    latest_recommended=$(echo "${VERSIONS[0]}" | cut -d'-' -f1)
    latest=$(echo "${VERSIONS[2]}" | cut -d'-' -f1)

    if [[ "${artifacts_version}" == "0" ]]; then
        if [[ "${non_interactive}" == "false" ]]; then
            status "Select a runtime version"
            export OPTIONS=("latest version -> $latest" "latest recommended version -> $latest_recommended" "choose custom version" "do nothing")

            bashSelect

            case $? in
                0 )
                    artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${VERSIONS[2]}"
                    log "INFO" "Selected version: latest version ($latest)"
                    ;;
                1 )
                    artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${VERSIONS[0]}"
                    log "INFO" "Selected version: latest recommended version ($latest_recommended)"
                    ;;
                2 )
                    clear
                    read -p "Enter the download link: " artifacts_version
                    log "INFO" "Custom version selected: $artifacts_version"
                    ;;
                3 )
                    log "INFO" "Installation cancelled by user"
                    exit 0
            esac

            return
        else
            artifacts_version="latest"
        fi
    fi
    if [[ "${artifacts_version}" == "latest" ]]; then
        artifacts_version="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${VERSIONS[2]}"
        log "INFO" "Using latest version: $latest"
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
    lsof -i :40120 >> $LOG_FILE 2>&1
    if [[ $( echo $? ) == 0 ]]; then
        if [[ "${non_interactive}" == "false" ]]; then
            if [[ "${kill_txAdmin}" == "0" ]]; then
                status "It looks like something is already running on the default TxAdmin port. Can we stop/kill it?"
                export OPTIONS=("Kill process on port 40120" "Exit script")
                bashSelect

                case $? in
                    0 )
                        kill_txAdmin="true"
                        ;;
                    1 )
                        exit 0
                        ;;
                esac
            fi
        fi
        if [[ "${kill_txAdmin}" == "true" ]]; then
            status "Stopping process on port 40120"
            runCommand "apt -y install psmisc"
            runCommand "fuser -4 40120/tcp -k" "Forcefully stopping process on port 40120"
            return
        fi

        log "ERROR" "It looks like something is already running on the default TxAdmin port."
        exit 1
    fi
}

function checkDir(){
    log "DEBUG" "Checking if directory $dir already exists"
    if [[ -e $dir ]]; then
        if [[ "${non_interactive}" == "false" ]]; then
            if [[ "${delete_dir}" == "0" ]]; then
                status "It looks like there is already a $dir directory. Can we remove it?"
                export OPTIONS=("Remove everything in $dir" "Exit script")
                bashSelect
                case $? in
                    0 )
                    delete_dir="true"
                    ;;
                    1 )
                    exit 0
                    ;;
                esac
            fi
        fi
        if [[ "${delete_dir}" == "true" ]]; then
            status "Removing $dir"
            runCommand "rm -r $dir" "Removing existing directory"
            return
        fi

        log "ERROR" "It looks like there is already a $dir directory."
        exit 1
    fi
}

function selectDeployment(){
    if [[ "${txadmin_deployment}" == "0" ]]; then
        txadmin_deployment="true"

        if [[ "${non_interactive}" == "false" ]]; then
            status "Select deployment type"
            export OPTIONS=("Install template via TxAdmin" "Use cfx-server-data" "Do nothing")
            bashSelect

            case $? in
                0 )
                    txadmin_deployment="true"
                    log "INFO" "Deployment type: TxAdmin"
                    ;;
                1 )
                    txadmin_deployment="false"
                    log "INFO" "Deployment type: cfx-server-data"
                    ;;
                2 )
                    log "INFO" "Installation cancelled by user"
                    exit 0
            esac
        fi
    fi
    if [[ "${txadmin_deployment}" == "false" ]]; then
        examServData
    fi
}

function createCrontab(){
    if [[ "${crontab_autostart}" == "0" ]]; then
        crontab_autostart="false"

        if [[ "${non_interactive}" == "false" ]]; then
            status "Create crontab to autostart txadmin (recommended)"
            export OPTIONS=("Yes" "No")
            bashSelect

            if [[ $? == 0 ]]; then
                crontab_autostart="true"
                log "INFO" "Crontab creation enabled"
            else
                log "INFO" "Crontab creation disabled"
            fi
        fi
    fi
    if [[ "${crontab_autostart}" == "true" ]]; then
        status "Creating crontab entry"
        runCommand "echo \"@reboot          root    /bin/bash $dir/start.sh\" > /etc/cron.d/fivem" "Configuring automatic startup via crontab"
    fi
}

function installPma(){
    if [[ "${non_interactive}" == "false" ]]; then
        if [[ "${install_phpmyadmin}" == "0" ]]; then
            status "Install MariaDB/MySQL and phpmyadmin"

            export OPTIONS=("Yes" "No")

            bashSelect

            case $? in
                0 )
                    install_phpmyadmin="true"
                    log "INFO" "phpMyAdmin installation enabled"
                    ;;
                1 )
                    install_phpmyadmin="false"
                    log "INFO" "phpMyAdmin installation disabled"
                    ;;
            esac
        fi
    fi
    if [[ "${install_phpmyadmin}" == "true" ]]; then
        log "INFO" "Installing phpMyAdmin"
        runCommand "bash <(curl -s https://raw.githubusercontent.com/JulianGransee/PHPMyAdminInstaller/main/install.sh) -s ${pma_options[*]}" "Installing phpMyAdmin and MariaDB/MySQL"
    fi
}

function install(){
    log "INFO" "Starting FiveM installation"
    # Create log file
    > $LOG_FILE
    
    runCommand "apt update -y" "Updating packages"
    runCommand "apt install -y wget git curl dos2unix net-tools sed screen xz-utils lsof" "Installing necessary packages"

    # Choose the installation path
    choose_installation_path
    
    checkPort
    checkDir
    selectDeployment
    selectVersion
    createCrontab
    installPma

    runCommand "mkdir -p $dir/server" "Creating directories for the FiveM server"
    runCommand "cd $dir/server/" "Navigating to the server directory"

    runCommand "wget $artifacts_version -O $dir/server/fx.tar.xz" "Downloading FxServer"
    runCommand "tar xf $dir/server/fx.tar.xz -C $dir/server/" "Extracting FxServer archive"
    runCommand "rm $dir/server/fx.tar.xz" "Removing the archive"

    status "Creating start, stop and access scripts"
    cat << EOF > $dir/start.sh
#!/bin/bash
red="\e[0;91m"
green="\e[0;92m"
bold="\e[1m"
reset="\e[0m"
port=\$(lsof -Pi :40120 -sTCP:LISTEN -t)
if [ -z "\$port" ]; then
    screen -dmS fivem sh $dir/server/run.sh
    echo -e "\n\${green}TxAdmin was started!\${reset}"
else
    echo -e "\n\${red}The default \${reset}\${bold}TxAdmin\${reset}\${red} port is already in use -> Is a \${reset}\${bold}FiveM Server\${reset}\${red} already running?\${reset}"
fi
EOF
    runCommand "chmod +x $dir/start.sh" "Making the start script executable"

    runCommand "echo \"screen -xS fivem\" > $dir/attach.sh" "Creating the access script"
    runCommand "chmod +x $dir/attach.sh" "Making the access script executable"

    runCommand "echo \"screen -XS fivem quit\" > $dir/stop.sh" "Creating the stop script"
    runCommand "chmod +x $dir/stop.sh" "Making the stop script executable"

    port=$(lsof -Pi :40120 -sTCP:LISTEN -t)

    if [[ -z "$port" ]]; then
        log "INFO" "Starting TxAdmin"
        if [[ -e '/tmp/fivem.log' ]]; then
        rm /tmp/fivem.log
        fi
        screen -L -Logfile /tmp/fivem.log -dmS fivem $dir/server/run.sh

        sleep 2
        log "INFO" "Waiting for TxAdmin to start..."

        line_counter=0
        while true; do
        while read -r line; do
            echo $line
            if [[ "$line" == *"able to access"* ]]; then
            break 2
            fi
        done < /tmp/fivem.log
        sleep 1
        done

        cat -v /tmp/fivem.log > /tmp/fivem.log.tmp

        while read -r line; do
        if [[ "$line" == *"PIN"*  ]]; then
            let "line_counter += 2"
            break 2
        fi
        let "line_counter += 1"
        done < /tmp/fivem.log.tmp

        pin_line=$( head -n $line_counter /tmp/fivem.log | tail -n +$line_counter )
        pin=$( cat -v /tmp/fivem.log.tmp | sed --regexp-extended --expression='s/\^\[\[([0-9][0-9][a-z])|([0-9][a-z])|(\^\[\[)|(\[.*\])|(M-bM-\^TM-\^C)|(\^M)//g' )
        pin=$( echo $pin | sed --regexp-extended --expression='s/[\ ]//g' )

        rm /tmp/fivem.log.tmp
        clear

        log "INFO" "TxAdmin was started successfully"
        txadmin="http://$(ip route get 1.1.1.1 | awk '{print $7; exit}'):40120"
        
        echo -e "\n${green}${bold}TxAdmin${reset}${green} was started successfully${reset}"
        echo -e "\n\n${red}${bold}Commands usable via SSH only:${reset}\n"
        echo -e "${blue}To ${reset}${bold}start${reset}${blue} TxAdmin run -> ${reset}${bold}sh $dir/start.sh${reset}\n"
        echo -e "${blue}To ${reset}${bold}stop${reset}${blue} TxAdmin run -> ${reset}${bold}sh $dir/stop.sh${reset}\n"
        echo -e "${blue}To see the ${reset}${bold}\"Live Console\"${reset}${blue} run -> ${reset}${bold}sh $dir/attach.sh${reset}\n"

        echo -e "\n${green}TxAdmin Web Interface: ${reset}${blue}${txadmin}\n"

        echo -e "${green}Pin: ${reset}${blue}${pin:(-4)}${reset}${green} (use it in the next 5 minutes!)"

        echo -e "\n${green}Server-Data Path: ${reset}${blue}$dir/server-data${reset}"

        if [[ "$install_phpmyadmin" == "true" ]]; then
            echo
            echo "${bold}MariaDB and PHPMyAdmin data:${reset}"
            runCommand "cat /root/.mariadbPhpma"
            runCommand "rm /root/.mariadbPhpma"
            rootPasswordMariaDB=$( cat /root/.mariadbRoot )
            rm /root/.mariadbRoot
            fivempasswd=$( pwgen 32 1 );
            mariadb -u root -p$rootPasswordMariaDB -e "CREATE DATABASE fivem;"
            mariadb -u root -p$rootPasswordMariaDB -e "GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost' IDENTIFIED BY '${fivempasswd}';"
            echo "
${bold}FiveM MySQL Data${reset}
    User: fivem
    Password: ${fivempasswd}
    Database name: fivem
    FiveM MySQL Connection String:
        set mysql_connection_string \"server=127.0.0.1;database=fivem;userid=fivem;password=${fivempasswd}\""
            runCommand "cat /root/.PHPma"
        fi

        # Save all information to a file
        cat << EOF > $dir/installation_info.txt
Installation Date: $(date "+%Y-%m-%d %H:%M:%S")
Installation Path: $dir
TxAdmin Web Interface: ${txadmin}
Initial Pin: ${pin:(-4)}
EOF

        if [[ "$install_phpmyadmin" == "true" ]]; then
            cat << EOF >> $dir/installation_info.txt

FiveM MySQL Data
User: fivem
Password: ${fivempasswd}
Database name: fivem
MySQL Connection String for FiveM:
set mysql_connection_string "server=127.0.0.1;database=fivem;userid=fivem;password=${fivempasswd}"
EOF
        fi

        log "INFO" "Installation information has been saved to $dir/installation_info.txt"
        sleep 1

    else
        log "ERROR" "The default TxAdmin port is already in use. Is a FiveM server already running?"
        echo -e "\n${red}The default ${reset}${bold}TxAdmin${reset}${red} port is already in use -> Is a ${reset}${bold}FiveM Server${reset}${red} already running?${reset}"
    fi
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
    # Initialize log file
    > $LOG_FILE
    log "INFO" "Starting FiveM installation/update script"
    
    # Check for curl
    curl --version >> $LOG_FILE 2>&1
    if [[ $? == 127  ]]; then  
        log "WARN" "curl is not installed, installing now..."
        apt update -y && apt -y install curl
    fi
    clear 

    if [[ "${non_interactive}" == "false" ]]; then
        log "INFO" "Interactive mode enabled"
        source <(curl -s https://raw.githubusercontent.com/JulianGransee/BashSelect.sh/main/BashSelect.sh)
        
        if [[ "${update_artifacts}" == "false" ]]; then
            status "What would you like to do?"
            export OPTIONS=("Install FiveM" "Update FiveM" "Do nothing")
            bashSelect

            case $? in
                0 )
                    install;;
                1 )
                    update;;
                2 )
                    log "INFO" "Exit requested by user"
                    exit 0
            esac
        fi
        exit 0
    fi
    
    if [[ "${update_artifacts}" == "false" ]]; then
        install
    else
        update
    fi
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo -e "${bold}Usage: bash <(curl -s https://raw.githubusercontent.com/Twe3x/fivem-installer/main/setup.sh) [OPTIONS]${reset}"
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
