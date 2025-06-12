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

# Function to determine default installation directory
get_default_install_dir() {
    # Try to find a suitable user directory
    if [[ -n "$SUDO_USER" ]] && [[ "$SUDO_USER" != "root" ]]; then
        # Script run with sudo, use the original user
        default_dir="/home/$SUDO_USER/FiveM"
        log "INFO" "Using sudo user directory: $default_dir"
    elif [[ -d "/home" ]]; then
        # Look for existing users in /home (excluding system users and FiveM)
        local users=($(ls /home 2>/dev/null | grep -v "lost+found" | grep -v "FiveM"))
        if [[ ${#users[@]} -gt 0 ]]; then
            # Use the first non-system user found
            for user in "${users[@]}"; do
                if [[ -d "/home/$user" ]] && [[ "$user" != "root" ]]; then
                    default_dir="/home/$user/FiveM"
                    log "INFO" "Using existing user directory: $default_dir"
                    break
                fi
            done
        fi
    fi
    
    # Fallback to /home/FiveM if no suitable user found
    if [[ -z "$default_dir" ]]; then
        default_dir="/home/FiveM"
        log "INFO" "Using fallback directory: $default_dir"
    fi
}
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

# MariaDB/phpMyAdmin variables
rootPasswordMariaDB=""
pmaPassword=""
blowfish_secret=""

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

# Check that the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${red}${bold}ERROR:${reset} This script must be run as root"
	exit 1
fi

# Initialize logging before doing anything else
setup_logging

# Function to show status in a nice box (non-interactive)
status(){
  if [[ "${non_interactive}" == "false" ]]; then
    clear
    echo -e "${cyan}╔════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║                                                                            ║${reset}"
    echo -e "${cyan}║${reset}  ${bold}${green} $@ ${reset}${cyan}  ║${reset}"
    echo -e "${cyan}║                                                                            ║${reset}"
    echo -e "${cyan}╚════════════════════════════════════════════════════════════════════════════╝${reset}"
    log "INFO" "$@..."
    sleep 1
  else
    echo -e "${green}${@}...${reset}"
    log "INFO" "${@}..."
    sleep 0.2
  fi
}

# Function to show loading animation
show_loading() {
    local message="$1"
    local pid="$2"
    local delay=0.3
    local spinstr='|/-\'
    local count=0
    
    while kill -0 "$pid" 2>/dev/null; do
        local spin_char=${spinstr:$count:1}
        printf "\r${blue}${message}${reset} [${cyan}${spin_char}${reset}] "
        count=$(( (count + 1) % 4 ))
        sleep $delay
    done
    
    # Clear the spinner and show completion
    printf "\r${blue}${message}${reset} [${green}OK${reset}] \n"
}

# Function to show dots loading for very long operations
show_dots_loading() {
    local message="$1"
    local pid="$2"
    local delay=1
    local dots=""
    local max_dots=3
    
    printf "${blue}${message}${reset}"
    
    while kill -0 "$pid" 2>/dev/null; do
        if [ ${#dots} -ge $max_dots ]; then
            dots=""
            printf "\r${blue}${message}${reset}   "
            printf "\r${blue}${message}${reset}"
        fi
        dots="${dots}."
        printf "${cyan}.${reset}"
        sleep $delay
    done
    
    # Show completion
    printf " ${green}[OK]${reset}\n"
}

# Enhanced runCommand function
runCommand(){
    COMMAND=$1
    LOG_MSG=${2:-"Executing command"}
    HIDE_OUTPUT=${3:-0}
    CRITICAL=${4:-0}  # If 1, exit on failure; if 0, just log error and continue
    SHOW_LOADING=${5:-0}  # If 1, show spinner; if 2, show dots for very long operations

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

    # Execute with appropriate output redirection and optional loading animation
    if [ "$HIDE_OUTPUT" -eq 1 ]; then
        if [ "$SHOW_LOADING" -eq 1 ]; then
            # Run command in background and show spinner
            eval $COMMAND >> "$LOG_FILE" 2>&1 &
            local cmd_pid=$!
            show_loading "$LOG_MSG" $cmd_pid
            wait $cmd_pid
            BASH_CODE=$?
        elif [ "$SHOW_LOADING" -eq 2 ]; then
            # Run command in background and show dots for very long operations
            eval $COMMAND >> "$LOG_FILE" 2>&1 &
            local cmd_pid=$!
            show_dots_loading "$LOG_MSG" $cmd_pid
            wait $cmd_pid
            BASH_CODE=$?
        else
            eval $COMMAND >> "$LOG_FILE" 2>&1
            BASH_CODE=$?
        fi
    else
        if [ "$SHOW_LOADING" -ge 1 ]; then
            # For visible output with loading, show a simple progress message
            echo -e "${blue}${LOG_MSG}... ${yellow}(This may take a while)${reset}"
            eval $COMMAND 2>&1 | tee -a "$LOG_FILE"
            BASH_CODE=${PIPESTATUS[0]}
        else
            eval $COMMAND 2>&1 | tee -a "$LOG_FILE"
            BASH_CODE=${PIPESTATUS[0]}
        fi
    fi

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

# =============================================================================
# MARIADB/PHPMYADMIN INSTALLATION FUNCTIONS (formerly in phpmyadmin.sh)
# =============================================================================

# Function to check for existing MariaDB installation
function serverCheck() {
    status "System Check"
    log "INFO" "Checking for existing MariaDB installation"
    
    mariadb --version >> "$LOG_FILE" 2>&1
    if [[ $? != 127 ]]; then
        log "WARN" "MariaDB is already installed"
        if [[ "${non_interactive}" == "false" ]]; then
            status "MariaDB already installed"
            echo -e "${yellow}${bold}ATTENTION :${reset} MariaDB/MySQL is already installed on this system."
            echo -e "${blue}What do you want to do ?${reset}\n"
            
            export OPTIONS=(
                "Reset MySQL/MariaDB password and continue installation" 
                "Remove MariaDB/MySQL completely" 
                "Continue without reinstalling MariaDB"
                "Quit the script"
            )

            bashSelect
            case $? in
                0 )
                    log "INFO" "User chose to reset MySQL password"
                    echo -e "${green}Selected:${reset} Reset MySQL password"
                    ;;
                1 )
                    log "INFO" "User chose to remove MariaDB completely"
                    echo -e "${green}Selected:${reset} Completely remove MariaDB"
                    
                    status "Removing MariaDB/MySQL"
                    echo -e "${yellow}Completely removing MariaDB/MySQL...${reset}"
                    runCommand "service mariadb stop || service mysql stop || systemctl stop mariadb" "Stopping MariaDB service" 1 0
                    runCommand "DEBIAN_FRONTEND=noninteractive apt -y remove --purge mariadb-*" "Removing MariaDB packages" 1 1
                    runCommand "rm -rf /var/lib/mysql/" "Removing MySQL data" 1 0
                    log "SUCCESS" "MariaDB completely removed"
                    ;;
                2 )
                    log "INFO" "User chose to continue without reinstalling"
                    echo -e "${green}Selected:${reset} Continue without reinstalling MariaDB"
                    return 0
                    ;;
                3 )
                    log "INFO" "User chose to exit"
                    echo -e "${yellow}Installation canceled by user.${reset}"
                    exit 0
                    ;;
            esac
        else
            log "WARN" "MariaDB already installed in non-interactive mode, continuing"
        fi
    fi

    if [[ -d /usr/share/phpmyadmin ]]; then
        log "WARN" "phpMyAdmin directory already exists"
        if [[ "${non_interactive}" == "false" ]]; then
            status "phpMyAdmin already present"
            echo -e "${yellow}${bold}ATTENTION :${reset} The phpMyAdmin directory already exists."
            echo -e "${blue}What do you want to do ?${reset}\n"

            export OPTIONS=(
                "Remove the existing phpMyAdmin directory" 
                "Continue without reinstalling phpMyAdmin"
                "Quit the script"
            )

            bashSelect
            case $? in
                0 )
                    log "INFO" "User chose to remove existing phpMyAdmin"
                    echo -e "${green}Selected:${reset} Remove existing phpMyAdmin"
                    runCommand "rm -rf /usr/share/phpmyadmin/" "Removing existing phpMyAdmin directory" 1 1
                    ;;
                1 )
                    log "INFO" "User chose to continue without reinstalling phpMyAdmin"
                    echo -e "${green}Selected:${reset} Continue without reinstalling phpMyAdmin"
                    return 0
                    ;;
                2 )
                    log "INFO" "User chose to exit due to existing phpMyAdmin"
                    echo -e "${yellow}Installation canceled by user.${reset}"
                    exit 0
                    ;;
            esac
        else
            log "INFO" "phpMyAdmin already exists in non-interactive mode, removing"
            runCommand "rm -rf /usr/share/phpmyadmin/" "Removing existing phpMyAdmin directory" 1 1
        fi
    fi
}

# Function to install PHP
function phpinstall() {
    log "INFO" "Installing PHP"
    
    eval $( cat /etc/*release* )
    if [[ "$ID" == "debian" && $VERSION_ID > 10 ]]; then
        runCommand "wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg" "adding main PHP repository for Debian - https://deb.sury.org" 1 0
        runCommand "sh -c 'echo \"deb https://packages.sury.org/php/ \$(lsb_release -sc) main\" > /etc/apt/sources.list.d/php.list'" "Adding PHP repository" 1 0
        runCommand "apt -y update" "Updating package lists" 1 1
        runCommand "apt -y install php8.3 php8.3-{cli,fpm,common,mysql,zip,gd,mbstring,curl,xml,bcmath} libapache2-mod-php8.3" "installing php8.3" 1 1
    else
        runCommand "apt -y install php php-{cli,fpm,common,mysql,zip,gd,mbstring,curl,xml,bcmath} libapache2-mod-php" "installing default php version" 1 1
    fi
}

# Function to install and configure Apache
function webserverInstall(){
    log "INFO" "Configuring Apache for phpMyAdmin"
    
    cat > /etc/apache2/conf-available/phpmyadmin.conf << 'EOF'
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php

    <IfModule mod_php5.c>
        <IfModule mod_mime.c>
            AddType application/x-httpd-php .php
        </IfModule>
        <FilesMatch ".+\.php$">
            SetHandler application/x-httpd-php
        </FilesMatch>

        php_value include_path .
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/
        php_admin_value mbstring.func_overload 0
    </IfModule>
    <IfModule mod_php.c>
        <IfModule mod_mime.c>
            AddType application/x-httpd-php .php
        </IfModule>
        <FilesMatch ".+\.php$">
            SetHandler application/x-httpd-php
        </FilesMatch>

        php_value include_path .
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/
        php_admin_value mbstring.func_overload 0
    </IfModule>

</Directory>

# Authorize for setup
<Directory /usr/share/phpmyadmin/setup>
    <IfModule mod_authz_core.c>
        <IfModule mod_authn_file.c>
            AuthType Basic
            AuthName "phpMyAdmin Setup"
            AuthUserFile /etc/phpmyadmin/htpasswd.setup
        </IfModule>
        Require valid-user
    </IfModule>
</Directory>

# Disallow web access to directories that dont need it
<Directory /usr/share/phpmyadmin/templates>
    Require all denied
</Directory>
<Directory /usr/share/phpmyadmin/libraries>
    Require all denied
</Directory>
<Directory /usr/share/phpmyadmin/setup/lib>
    Require all denied
</Directory>
EOF

    runCommand "/etc/init.d/apache2 start" "Starting Apache" 1 0
    runCommand "a2enconf phpmyadmin.conf" "Enabling phpMyAdmin configuration" 1 1
    
    phpinstall
    
    runCommand "service apache2 restart" "Restarting Apache" 1 1
}

# Function to install and secure MariaDB
function dbInstall(){
    status "generating passwords"
    rootPasswordMariaDB=$( pwgen 16 1 );
    pmaPassword=$( pwgen 32 1 );
    blowfish_secret=$( pwgen 32 1 );
    
    log "INFO" "Generated passwords for MariaDB and phpMyAdmin"

    status "securing the mariadb installation"

    # First, set the root password using mysql_secure_installation approach
    runCommand "mariadb -u root -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${rootPasswordMariaDB}';\"" "Setting root password" 1 1
    runCommand "mariadb -u root -p${rootPasswordMariaDB} -e \"DELETE FROM mysql.user WHERE User='';\"" "Removing anonymous users" 1 1
    
    # Remove test database
    runCommand "mariadb -u root -p${rootPasswordMariaDB} -e \"DROP DATABASE IF EXISTS test;\"" "Removing test database" 1 0
    runCommand "mariadb -u root -p${rootPasswordMariaDB} -e \"DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';\"" "Removing test database privileges" 1 0
    
    # Create remote root access with proper approach for MariaDB 11.4
    log "INFO" "Configuring remote root access"
    cat > /tmp/remote_root.sql << EOF
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${rootPasswordMariaDB}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    
    runCommand "mariadb -u root -p${rootPasswordMariaDB} < /tmp/remote_root.sql" "Configuring remote root access" 1 1
    rm -f /tmp/remote_root.sql

    # Configure MariaDB to listen on all interfaces
    runCommand "sed -i -E 's/^#?bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf" "Configuring MariaDB bind-address" 1 1
    runCommand "systemctl restart mariadb || service mariadb restart" "Restarting MariaDB service to apply bind-address" 1 1 1
}

# Function to install and configure phpMyAdmin
function pmaInstall() {
    log "INFO" "Installing phpMyAdmin"

    runCommand "wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip" "Downloading phpMyAdmin" 1 1 2
    runCommand "unzip phpMyAdmin-latest-all-languages.zip" "Extracting phpMyAdmin" 1 1 1
    runCommand "rm phpMyAdmin-latest-all-languages.zip" "Removing downloaded archive" 1 1
    runCommand "mv phpMyAdmin-* /usr/share/phpmyadmin" "Moving phpMyAdmin files" 1 1
    runCommand "mkdir -p /var/lib/phpmyadmin/tmp" "Creating temporary directory" 1 1
    runCommand "cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php" "Copying configuration file" 1 1

    # Configuration of phpMyAdmin settings
    log "INFO" "Configuring phpMyAdmin settings"
    
    # Configure blowfish secret - use single quotes to avoid shell expansion
    runCommand "sed -i \"s/\\\$cfg\\['blowfish_secret'\\] = '';/\\\$cfg\\['blowfish_secret'\\] = '${blowfish_secret}';/\" /usr/share/phpmyadmin/config.inc.php" "Configuring blowfish secret" 1 1

    # Configuration of phpMyAdmin control tables - avoid shell expansion issues
    sed -i 's|// $cfg\['\''Servers'\''\]\[$i\]\['\''controluser'\''\] = '\''pma'\'';|$cfg['\''Servers'\''][$i]['\''controluser'\''] = '\''pma'\'';|' /usr/share/phpmyadmin/config.inc.php
    sed -i "s|// \$cfg\\['Servers'\\]\\[\$i\\]\\['controlpass'\\] = 'pmapass';|\$cfg['Servers'][\$i]['controlpass'] = '${pmaPassword}';|" /usr/share/phpmyadmin/config.inc.php
    sed -i 's|// $cfg\['\''Servers'\''\]\[$i\]\['\''pmadb'\''\] = '\''phpmyadmin'\'';|$cfg['\''Servers'\''][$i]['\''pmadb'\''] = '\''phpmyadmin'\'';|' /usr/share/phpmyadmin/config.inc.php

    # Configuration of phpMyAdmin tables
    local table_configs=(
        "bookmarktable" "relation" "table_info" "table_coords" "pdf_pages" 
        "column_info" "history" "table_uiprefs" "tracking" "userconfig" 
        "recent" "favorite" "users" "usergroups" "navigationhiding" 
        "savedsearches" "central_columns" "designer_settings" "export_templates"
    )
    
    for table in "${table_configs[@]}"; do
        sed -i "s|// \$cfg\\['Servers'\\]\\[\$i\\]\\['${table}'\\] = 'pma__${table}';|\$cfg['Servers'][\$i]['${table}'] = 'pma__${table}';|" /usr/share/phpmyadmin/config.inc.php >> "$LOG_FILE" 2>&1
    done

    runCommand "printf \"\\\$cfg['TempDir'] = '/var/lib/phpmyadmin/tmp';\" >> /usr/share/phpmyadmin/config.inc.php" "Configuring temporary directory" 1 1

    runCommand "chown -R www-data:www-data /var/lib/phpmyadmin" "Setting permissions" 1 1
    runCommand "service mariadb start || service mysql start || systemctl start mariadb" "Starting MariaDB service" 1 1
    runCommand "mariadb -u root -p${rootPasswordMariaDB} < /usr/share/phpmyadmin/sql/create_tables.sql" "Importing phpMyAdmin tables" 1 1 1
    runCommand "mariadb -u root -p${rootPasswordMariaDB} -e \"CREATE USER IF NOT EXISTS 'pma'@'localhost' IDENTIFIED BY '${pmaPassword}';\"" "Creating phpMyAdmin control user" 1 1
    
    # Use SQL without shell expansion issues - avoid wildcards in runCommand
    log "INFO" "Granting privileges to phpMyAdmin control user"
    cat > /tmp/grant_pma.sql << EOF
GRANT SELECT, INSERT, UPDATE, DELETE ON phpmyadmin.* TO 'pma'@'localhost';
EOF
    
    mariadb -u root -p${rootPasswordMariaDB} < /tmp/grant_pma.sql >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Granting privileges to phpMyAdmin control user - Completed successfully"
    else
        log "ERROR" "Failed to grant privileges to phpMyAdmin control user"
        rm -f /tmp/grant_pma.sql
        return 1
    fi
    
    rm -f /tmp/grant_pma.sql
    runCommand "mariadb -u root -p${rootPasswordMariaDB} -e \"FLUSH PRIVILEGES;\"" "Flushing privileges" 1 1
}

# Main phpMyAdmin installation function
function install_mariadb_phpmyadmin(){
    log "INFO" "Starting MariaDB and phpMyAdmin installation"
    
    echo -e "\n${cyan}╔═══════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║ ${bold}${green}                    MARIADB & PHPMYADMIN INSTALLATION                    ${reset}${cyan}║${reset}"
    echo -e "${cyan}║ ${reset}${blue}                          Version: $script_version                           ${reset}${cyan}║${reset}"
    echo -e "${cyan}╚═══════════════════════════════════════════════════════════════════════════════╝${reset}\n"

    # System check
    serverCheck

    echo -e "${green}=== Database Installation Progress ===${reset}"
    echo -e "${blue}Step 1/8: Updating system packages...${reset}"
    runCommand "apt -y update" "Updating package list" 1 1 1

    echo -e "${blue}Step 2/8: Upgrading system packages...${reset}"
    runCommand "apt -y upgrade" "Upgrading system packages" 1 1 2

    # Add MariaDB 11.4 repository for latest version
    echo -e "${blue}Step 3/8: Setting up MariaDB 11.4 repository...${reset}"
    status "Adding MariaDB 11.4 repository"
    runCommand "apt install -y apt-transport-https curl gnupg lsb-release" "Installing repository tools" 1 1 1
    
    # Detect distribution and set appropriate repository
    eval $( cat /etc/*release* )
    DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -sc)
    
    if [[ "$DISTRO" == "ubuntu" ]]; then
        MARIADB_REPO="deb https://deb.mariadb.org/11.4/ubuntu $CODENAME main"
    elif [[ "$DISTRO" == "debian" ]]; then
        MARIADB_REPO="deb https://deb.mariadb.org/11.4/debian $CODENAME main"
    else
        # Fallback to Ubuntu jammy for unknown distributions
        MARIADB_REPO="deb https://deb.mariadb.org/11.4/ubuntu jammy main"
        log "WARN" "Unknown distribution detected, using Ubuntu jammy repository"
        echo -e "${yellow}Unknown distribution detected, using Ubuntu jammy repository${reset}"
    fi
    
    log "INFO" "Adding MariaDB repository for $DISTRO $CODENAME"
    echo -e "${blue}Adding MariaDB repository for $DISTRO $CODENAME${reset}"
    runCommand "curl -o /etc/apt/trusted.gpg.d/mariadb_release_signing_key.asc 'https://mariadb.org/mariadb_release_signing_key.asc'" "Downloading MariaDB GPG key" 1 1
    runCommand "sh -c \"echo '$MARIADB_REPO' > /etc/apt/sources.list.d/mariadb.list\"" "Configuring MariaDB repository" 1 1
    
    # Update package list with new repository
    echo -e "${blue}Step 4/8: Updating package lists with MariaDB repository...${reset}"
    runCommand "apt -y update" "Updating with new repository" 1 1 1

    echo -e "${blue}Step 5/8: Installing Apache2, MariaDB 11.4, and required packages...${reset}"
    echo -e "${yellow}This step may take several minutes depending on your internet connection...${reset}"
    runCommand "apt install -y apache2 mariadb-server=1:11.4* mariadb-client=1:11.4* pwgen expect iproute2 wget zip apt-transport-https lsb-release ca-certificates curl dialog unzip" "Installing necessary packages with MariaDB 11.4" 1 1 2

    echo -e "${blue}Step 6/8: Starting MariaDB service...${reset}"
    runCommand "service mariadb start || service mysql start || systemctl start mariadb" "Starting MariaDB service" 1 1

    echo -e "${blue}Step 7/8: Configuring MariaDB security and phpMyAdmin...${reset}"
    dbInstall
    pmaInstall

    echo -e "${blue}Step 8/8: Finalizing installation...${reset}"
    runCommand "service mariadb restart || service mysql restart || systemctl restart mariadb" "Restarting MariaDB service" 1 1

    webserverInstall

    log "SUCCESS" "MariaDB and phpMyAdmin installation completed successfully"
    echo -e "\n${green}✓ MariaDB and phpMyAdmin installation completed!${reset}"
}

# =============================================================================
# END OF MARIADB/PHPMYADMIN FUNCTIONS
# =============================================================================

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

# =============================================================================
# BASHSELECT FUNCTION (formerly in bashselect.sh)
# =============================================================================

function bashSelect() {
  function printOptions() { # printing the different options
    it=$1
    for i in "${!OPTIONS[@]}"; do
      if [[ "$i" -eq "$it" ]]; then
        echo -e "\033[7m  $i) ${OPTIONS[$i]} \033[0m"
      else
        echo "  $i) ${OPTIONS[$i]}"
      fi
    done
  }

  trap 'echo -ne "\033[?25h"; exit' SIGINT SIGTERM
  echo -ne "\033[?25l"
  it=0

  printOptions $it

  while true; do # loop through array to capture every key press until enter is pressed
    # capture key input
    read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
      read -rsn2 key
    fi

    echo -ne "\033[${#OPTIONS[@]}A\033[J"

    # handle key input
    case $key in
      '[A' | '[C') ((it--));; # up or right arrow
      '[B' | '[D') ((it++));; # down or left arrow
      '')
        echo -ne "\033[?25h"
        return "$it"
        ;;
    esac

    # manage that you can't select something out of range
    min_len=0
    max_len=$(( ${#OPTIONS[@]} - 1 ))
    if [[ "$it" -lt "$min_len" ]]; then
      it=$max_len
    elif [[ "$it" -gt "$max_len" ]]; then
      it=$min_len
    fi

    printOptions $it

  done
}

# =============================================================================
# DATABASE CONFIGURATION FUNCTIONS
# =============================================================================

# Function to configure existing database
function configureExistingDatabase() {
    log "INFO" "Configuring existing database connection"
    
    if [[ "${non_interactive}" == "false" ]]; then
        status "Existing Database Configuration"
        echo -e "${cyan}Please provide your existing database connection details:${reset}\n"
        
        # Get database host
        read -p "Database Host/IP (default: localhost): " existing_db_host
        existing_db_host=${existing_db_host:-localhost}
        
        # Get database name  
        read -p "Database Name (default: fivem): " existing_db_name
        existing_db_name=${existing_db_name:-fivem}
        
        # Get database user
        read -p "Database User (default: root): " existing_db_user
        existing_db_user=${existing_db_user:-root}
        
        # Get database password
        echo -n "Database Password: "
        read -s existing_db_password
        echo
        
        # Test database connection
        echo -e "\n${blue}Testing database connection...${reset}"
        if mysql -h"$existing_db_host" -u"$existing_db_user" -p"$existing_db_password" -e "USE $existing_db_name;" 2>/dev/null; then
            log "SUCCESS" "Database connection test successful"
            echo -e "${green}✓ Database connection successful!${reset}"
            existing_db_configured=true
        else
            log "ERROR" "Database connection test failed"
            echo -e "${red}✗ Database connection failed!${reset}"
            echo -e "${yellow}Please check your database credentials and try again.${reset}"
            existing_db_configured=false
            return 1
        fi
    else
        log "WARN" "Existing database configuration skipped in non-interactive mode"
        existing_db_configured=false
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
        # Use integrated MariaDB/phpMyAdmin installation
        install_mariadb_phpmyadmin
    fi
}

# =============================================================================
# FIVEM INSTALLATION FUNCTIONS
# =============================================================================

# Function to validate URL
validate_url() {
    local url="$1"
    if curl --connect-timeout 10 --max-time 30 --output /dev/null --silent --head --fail "$url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to select FiveM version (based on your working method)
selectVersion(){
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
                    local all_versions=$(curl -s https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/ | egrep -o '[0-9][^/]*/fx.tar.xz' | head -10)
                    
                    # Create array of versions for bashSelect
                    local version_options=()
                    local version_urls=()
                    local i=0
                    
                    echo -e "${cyan}Recent versions:${reset}"
                    while read version && [ $i -lt 10 ]; do
                        if [ -n "$version" ]; then
                            # Extract just the version number (remove /fx.tar.xz)
                            clean_version=${version%/fx.tar.xz}
                            version_options+=("Version ${clean_version}")
                            version_urls+=("https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/$clean_version/fx.tar.xz")
                            i=$((i+1))
                        fi
                    done <<< "$all_versions"
                    
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

# Function to download and extract server artifacts
download_server_artifacts() {
    local install_dir=$1
    
    status "Downloading FiveM Server Artifacts"
    log "INFO" "Downloading server artifacts to $install_dir"
    
    # Create temp directory for download
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # artifacts_version should now contain the full URL
    local download_url="$artifacts_version"
    
    log "INFO" "Downloading from: $download_url"
    
    # Try wget first
    local download_success=false
    if wget --timeout=60 --tries=3 -O fx.tar.xz "$download_url" >> "$LOG_FILE" 2>&1; then
        log "SUCCESS" "Download successful with wget"
        download_success=true
    else
        log "WARN" "wget failed, trying curl"
        # Try curl as fallback
        if curl --connect-timeout 10 --max-time 300 -L -o fx.tar.xz "$download_url" >> "$LOG_FILE" 2>&1; then
            log "SUCCESS" "Download successful with curl"
            download_success=true
        else
            log "ERROR" "Both wget and curl failed"
        fi
    fi
    
    if [[ "$download_success" != "true" ]]; then
        log "ERROR" "Download failed from: $download_url"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify downloaded file
    if [[ ! -f "fx.tar.xz" ]] || [[ ! -s "fx.tar.xz" ]]; then
        log "ERROR" "Downloaded file is missing or empty"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extract to install directory
    log "INFO" "Extracting artifacts to $install_dir"
    if tar -xJf fx.tar.xz -C "$install_dir" >> "$LOG_FILE" 2>&1; then
        log "SUCCESS" "Extraction successful"
    else
        log "ERROR" "Extraction failed"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    log "SUCCESS" "Server artifacts downloaded and extracted successfully"
}

# Function to let user choose artifacts version (wrapper for selectVersion)
choose_artifacts_version() {
    if [[ "$artifacts_version" == "0" ]]; then
        selectVersion
    fi
}

# Function to create server configuration
create_server_config() {
    local install_dir=$1
    
    status "Creating Server Configuration"
    log "INFO" "Creating server configuration files"
    
    # Create server.cfg
    cat > "$install_dir/server.cfg" << 'EOF'
# FiveM Server Configuration
# Generated by FiveM Server Installer

## Server Information
sv_hostname "My FiveM Server"
sv_maxclients 48

## Server Identity
set sv_projectName "My FiveM Server"
set sv_projectDesc "A FiveM server created with the installer"

## License Key (REQUIRED)
# Get your license key from https://keymaster.fivem.net/
# sv_licenseKey "YOUR_LICENSE_KEY_HERE"

## Server Endpoints
endpoint_add_tcp "0.0.0.0:30120"
endpoint_add_udp "0.0.0.0:30120"

## Server Commands
add_ace group.admin command allow # allow all commands
add_ace group.admin command.quit deny # but don't allow quit
add_principal identifier.fivem:1 group.admin # add the admin to the group

# Hide player endpoints from the API
set sv_endpointprivacy true

# Server player slot reservation
set sv_slotpriority ""

# Grant permissions to the user with the admin rights
add_ace resource.webadmin command.restart allow
add_ace resource.webadmin command.stop allow

# Enable OneSync (required for 32+ players)
set onesync on

## Voice Chat Configuration
setr voice_use3dAudio true
setr voice_useSendingRangeOnly true

## Resource Settings
ensure mapmanager
ensure chat
ensure spawnmanager
ensure sessionmanager
ensure hardcap
ensure baseevents

## Custom Resources
# ensure my-custom-resource

## Loading Screen (optional)
# loadscreen_manual_shutdown 'yes'
# loadscreen http://example.com/loading.html

## Download Settings
set sv_downloadUrl ""

## Scripting
set mysql_connection_string "server=localhost;uid=root;password=YOUR_DB_PASSWORD;database=fivem;port=3306;"

## Additional Settings
set sv_enforceGameBuild 2545

# Console Commands
exec permissions.cfg
EOF

    # Create permissions.cfg
    cat > "$install_dir/permissions.cfg" << 'EOF'
# Permissions Configuration
# Add your admins here

## Admin Commands
add_ace group.admin command allow
add_ace group.admin command.quit deny

## Add your admin identifiers here
# Example:
# add_principal identifier.license:YOUR_LICENSE_HERE group.admin
# add_principal identifier.steam:YOUR_STEAM_HEX_HERE group.admin
# add_principal identifier.fivem:YOUR_FIVEM_ID_HERE group.admin
EOF

    # Create cache and logs directories
    mkdir -p "$install_dir/cache"
    mkdir -p "$install_dir/logs"
    
    log "SUCCESS" "Server configuration files created"
}

# Function to create database tables for FiveM
create_fivem_database() {
    if [[ "$existing_db_configured" == "true" ]]; then
        log "INFO" "Creating FiveM database with existing database credentials"
        
        # Test connection first
        if mysql -h"$existing_db_host" -u"$existing_db_user" -p"$existing_db_password" -e "SELECT 1;" 2>/dev/null; then
            # Create database if it doesn't exist
            mysql -h"$existing_db_host" -u"$existing_db_user" -p"$existing_db_password" -e "CREATE DATABASE IF NOT EXISTS $existing_db_name;" 2>/dev/null
            log "SUCCESS" "FiveM database ready with existing configuration"
        else
            log "ERROR" "Cannot connect to existing database"
            return 1
        fi
    elif [[ "$install_phpmyadmin" == "true" ]] && [[ -n "$rootPasswordMariaDB" ]]; then
        log "INFO" "Creating FiveM database with installed MariaDB"
        
        # Create fivem database
        runCommand "mariadb -u root -p${rootPasswordMariaDB} -e \"CREATE DATABASE IF NOT EXISTS fivem;\"" "Creating FiveM database" 1 0
        log "SUCCESS" "FiveM database created successfully"
    else
        log "INFO" "No database configuration - skipping database creation"
    fi
}

# Function to create installation info file
create_installation_info() {
    local install_dir=$1
    
    log "INFO" "Creating installation information file"
    
    local info_file="$install_dir/installation_info.txt"
    local server_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "Unknown")
    
    cat > "$info_file" << EOF
===============================================
     FIVEM SERVER INSTALLATION COMPLETE
===============================================

Installation Date: $(date)
Installation Directory: $install_dir
Server IP: $server_ip

===============================================
          SERVER INFORMATION
===============================================

FiveM Server Port: 30120
Connection String: connect $server_ip:30120

Configuration Files:
- Server Config: $install_dir/server.cfg
- Permissions: $install_dir/permissions.cfg

Server Commands:
- Start Server: cd $install_dir && ./run.sh +exec server.cfg
- Console Access: Use txAdmin or direct console

===============================================
          DATABASE INFORMATION
===============================================

EOF

    # Add database information based on configuration
    if [[ "$existing_db_configured" == "true" ]]; then
        cat >> "$info_file" << EOF
Database Type: Existing Database
Host: $existing_db_host
Database: $existing_db_name
User: $existing_db_user
Password: [Hidden for security]

Connection String for server.cfg:
set mysql_connection_string "server=$existing_db_host;uid=$existing_db_user;password=$existing_db_password;database=$existing_db_name;port=3306;"
EOF
    elif [[ "$install_phpmyadmin" == "true" ]]; then
        cat >> "$info_file" << EOF
Database Type: MariaDB 11.4 (Installed)
Host: localhost
Database: fivem
User: root
Password: $rootPasswordMariaDB

phpMyAdmin Access:
URL: http://$server_ip/phpmyadmin/
User: root  
Password: $rootPasswordMariaDB

Connection String for server.cfg:
set mysql_connection_string "server=localhost;uid=root;password=$rootPasswordMariaDB;database=fivem;port=3306;"
EOF
    else
        cat >> "$info_file" << EOF
Database: Not configured
Note: You can configure database manually later if needed.
EOF
    fi

    cat >> "$info_file" << EOF

===============================================
          IMPORTANT NOTES
===============================================

1. REQUIRED: Get your license key from https://keymaster.fivem.net/
   Edit $install_dir/server.cfg and add your license key.

2. Configure your server hostname and description in server.cfg

3. Add admin permissions in permissions.cfg using your identifiers

4. If using txAdmin, it will create its own configuration

5. Make sure to open port 30120 (TCP/UDP) in your firewall

===============================================
          NEXT STEPS
===============================================

1. Get your license key and add it to server.cfg
2. Configure server settings in server.cfg  
3. Add admin permissions in permissions.cfg
4. Start your server: cd $install_dir && ./run.sh +exec server.cfg

===============================================
          SUPPORT & DOCUMENTATION
===============================================

FiveM Documentation: https://docs.fivem.net/
FiveM Forum: https://forum.cfx.re/
FiveM Discord: https://discord.gg/fivem

Log file: $LOG_FILE

===============================================
EOF

    chmod 644 "$info_file"
    log "SUCCESS" "Installation information saved to $info_file"
    echo -e "${green}✓ Installation information saved to:${reset} $info_file"
}

# Function to create management scripts
create_management_scripts() {
    local install_dir=$1
    
    log "INFO" "Creating management scripts"
    
    # Create start script
    cat > "$install_dir/start.sh" << EOF
#!/bin/bash
# FiveM Server Starter Script
# Created by FiveM Server Installer v${script_version}

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
    
    # Start the server
    screen -dmS fivem sh $install_dir/run.sh
    
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

    chmod +x "$install_dir/start.sh"
    
    # Create attach script
    cat > "$install_dir/attach.sh" << EOF
#!/bin/bash
# FiveM Server Console Access
# Created by FiveM Server Installer v${script_version}

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
    
    chmod +x "$install_dir/attach.sh"
    
    # Create stop script
    cat > "$install_dir/stop.sh" << EOF
#!/bin/bash
# FiveM Server Stop Script  
# Created by FiveM Server Installer v${script_version}

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
    
    chmod +x "$install_dir/stop.sh"
    
    log "SUCCESS" "Management scripts created"
}

# Function to setup txAdmin if requested
setup_txadmin() {
    local install_dir=$1
    
    if [[ "$txadmin_deployment" == "1" ]]; then
        status "Setting up txAdmin"
        log "INFO" "Configuring txAdmin deployment"
        
        # Check if FiveM run.sh exists
        if [[ ! -f "$install_dir/run.sh" ]]; then
            log "ERROR" "FiveM run.sh not found in $install_dir"
            echo -e "${red}✗ FiveM run.sh not found, txAdmin setup skipped${reset}"
            export TXADMIN_PIN="not_available"
            return 1
        fi
        
        # Start txAdmin in screen session to capture PIN
        log "INFO" "Starting txAdmin in screen session for PIN capture"
        cd "$install_dir"
        
        # Kill any existing screen session
        screen -S fivem -X quit 2>/dev/null || true
        sleep 2
        
        # Start txAdmin
        log "INFO" "Starting screen session with FiveM run.sh"
        screen -dmS fivem sh "$install_dir/run.sh"
        
        # Wait for screen session to be created
        sleep 3
        
        # Check if screen session was created
        local session_created=false
        local attempts=0
        local max_attempts=10
        
        while [ $attempts -lt $max_attempts ]; do
            if screen -list | grep -q "fivem"; then
                session_created=true
                log "INFO" "Screen session 'fivem' created successfully"
                break
            fi
            sleep 1
            attempts=$((attempts + 1))
        done
        
        if [ "$session_created" = false ]; then
            log "ERROR" "Failed to create screen session"
            echo -e "${red}✗ Failed to create screen session for txAdmin${reset}"
            export TXADMIN_PIN="session_failed"
            cd - > /dev/null
            return 1
        fi
        
        # Wait for txAdmin to start and display PIN
        log "INFO" "Waiting for txAdmin to start and display PIN..."
        sleep 15
        
        # Multiple attempts to capture PIN
        local pin=""
        local capture_attempts=0
        local max_capture_attempts=5
        
        while [ $capture_attempts -lt $max_capture_attempts ] && [ -z "$pin" ]; do
            log "INFO" "PIN capture attempt $((capture_attempts + 1))/$max_capture_attempts"
            
            # Capture screen content
            screen -S fivem -X hardcopy /tmp/fivem_screen_$capture_attempts.txt
            
            if [ -f "/tmp/fivem_screen_$capture_attempts.txt" ]; then
                # Debug: Log what we've captured
                log "DEBUG" "Captured screen content (attempt $((capture_attempts + 1))):"
                cat /tmp/fivem_screen_$capture_attempts.txt >> "$LOG_FILE"
                
                # Try multiple PIN extraction methods
                # Method 1: Look for "Use the PIN below to register"
                pin=$(grep -A 3 "Use the PIN below to register" /tmp/fivem_screen_$capture_attempts.txt | grep -oE "[0-9]{4}" | head -1)
                
                # Method 2: Look for boxed PIN format
                if [ -z "$pin" ]; then
                    pin=$(grep -E "┃\s*[0-9]{4}\s*┃" /tmp/fivem_screen_$capture_attempts.txt | grep -oE "[0-9]{4}" | head -1)
                fi
                
                # Method 3: Look for PIN in context
                if [ -z "$pin" ]; then
                    pin=$(grep -i -A 5 -B 5 "pin" /tmp/fivem_screen_$capture_attempts.txt | grep -oE "[0-9]{4}" | head -1)
                fi
                
                # Method 4: Look for any 4-digit number
                if [ -z "$pin" ]; then
                    pin=$(grep -oE "[0-9]{4}" /tmp/fivem_screen_$capture_attempts.txt | head -1)
                fi
                
                # Method 5: Look for txAdmin specific patterns
                if [ -z "$pin" ]; then
                    pin=$(grep -E "(PIN|pin|Pin).*[0-9]{4}" /tmp/fivem_screen_$capture_attempts.txt | grep -oE "[0-9]{4}" | head -1)
                fi
                
                if [[ "$pin" =~ ^[0-9]{4}$ ]]; then
                    log "INFO" "PIN extracted successfully: $pin"
                    break
                fi
            else
                log "WARN" "Failed to capture screen content"
            fi
            
            capture_attempts=$((capture_attempts + 1))
            sleep 5
        done
        
        # Validate and set PIN
        if [[ "$pin" =~ ^[0-9]{4}$ ]]; then
            export TXADMIN_PIN="$pin"
            log "SUCCESS" "PIN extracted successfully: $pin"
            echo -e "${green}✓ txAdmin started successfully${reset}"
            echo -e "${yellow}txAdmin PIN: ${bold}$pin${reset}"
        else
            log "WARN" "Could not extract valid 4-digit PIN after $max_capture_attempts attempts"
            export TXADMIN_PIN="check_manually"
            echo -e "${yellow}⚠ Could not extract PIN automatically${reset}"
            echo -e "${blue}Use 'screen -r fivem' to view the txAdmin console and get the PIN${reset}"
        fi
        
        # Get the server IP address and TxAdmin URL
        local server_ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
        local txadmin="http://${server_ip}:40120"
        echo -e "${blue}Access txAdmin at: $txadmin${reset}"
        
        # Clean up temp files
        rm -f /tmp/fivem_screen_*.txt
        
        cd - > /dev/null
        log "SUCCESS" "txAdmin setup completed"
    fi
}

# Function to setup crontab autostart if requested
setup_crontab_autostart() {
    local install_dir=$1
    
    if [[ "$crontab_autostart" == "1" ]]; then
        status "Setting up Crontab Autostart"
        log "INFO" "Configuring crontab for automatic server startup"
        
        # Create autostart script
        cat > "$install_dir/autostart.sh" << EOF
#!/bin/bash
# FiveM Server Autostart Script
cd "$install_dir"

# Determine the appropriate user to run the server
if [[ "$install_dir" == /home/* ]]; then
    DIR_USER=\$(echo "$install_dir" | cut -d'/' -f3)
    if [[ "\$DIR_USER" != "root" ]] && id "\$DIR_USER" &>/dev/null; then
        su - "\$DIR_USER" -c "cd '$install_dir' && ./run.sh"
    elif [[ "\$DIR_USER" == "FiveM" ]] && id "fivem" &>/dev/null; then
        su - fivem -c "cd '$install_dir' && ./run.sh"
    else
        ./run.sh
    fi
else
    ./run.sh
fi
EOF
        chmod +x "$install_dir/autostart.sh"
        
        # Add to root crontab for system-wide autostart
        (crontab -l 2>/dev/null; echo "@reboot $install_dir/autostart.sh") | crontab -
        
        log "SUCCESS" "Crontab autostart configured"
        echo -e "${green}✓ Server will automatically start on system boot${reset}"
    fi
}

# =============================================================================
# MAIN INSTALLATION FUNCTION  
# =============================================================================

# Function to perform the main FiveM server installation
install_fivem_server() {
    log "INFO" "Starting FiveM server installation"
    
    # Validate installation directory
    if [[ -z "$dir" ]]; then
        log "ERROR" "Installation directory not specified"
        return 1
    fi
    
    # Handle existing directory
    if [[ -d "$dir" ]]; then
        if [[ "$delete_dir" == "1" ]]; then
            log "INFO" "Removing existing directory: $dir"
            runCommand "rm -rf '$dir'" "Removing existing directory" 0 1
        elif [[ "$update_artifacts" == "true" ]]; then
            log "INFO" "Updating existing installation"
        else
            log "ERROR" "Directory already exists: $dir"
            if [[ "${non_interactive}" == "false" ]]; then
                echo -e "${red}Directory already exists: $dir${reset}"
                echo -e "${blue}What would you like to do?${reset}\n"
                
                export OPTIONS=(
                    "Remove existing directory and continue"
                    "Update artifacts only"
                    "Cancel installation"
                )
                
                bashSelect
                case $? in
                    0)
                        runCommand "rm -rf '$dir'" "Removing existing directory" 0 1
                        ;;
                    1)
                        update_artifacts=true
                        ;;
                    2)
                        log "INFO" "Installation cancelled by user"
                        return 1
                        ;;
                esac
            else
                return 1
            fi
        fi
    fi
    
    # Create installation directory
    if [[ ! -d "$dir" ]]; then
        log "INFO" "Creating installation directory: $dir"
        runCommand "mkdir -p '$dir'" "Creating installation directory" 0 1
        
        # Set proper ownership if installing in user directory
        if [[ "$dir" == /home/* ]]; then
            local dir_user=$(echo "$dir" | cut -d'/' -f3)
            if [[ "$dir_user" != "FiveM" ]] && id "$dir_user" &>/dev/null; then
                log "INFO" "Setting ownership for user directory: $dir_user"
                runCommand "chown -R $dir_user:$dir_user '$dir'" "Setting directory ownership" 0 0
            elif [[ "$dir_user" == "FiveM" ]]; then
                # Create FiveM user if it doesn't exist
                if ! id "fivem" &>/dev/null; then
                    log "INFO" "Creating FiveM system user"
                    runCommand "useradd -r -m -d /home/FiveM -s /bin/bash fivem" "Creating FiveM user" 0 0
                fi
                runCommand "chown -R fivem:fivem '$dir'" "Setting FiveM directory ownership" 0 0
            fi
        fi
    fi
    
    # Install server artifacts
    download_server_artifacts "$dir"
    
    # Create configuration files
    create_server_config "$dir"
    
    # Setup database
    create_fivem_database
    
    # Create management scripts
    create_management_scripts "$dir"
    
    # Setup txAdmin if requested
    setup_txadmin "$dir"
    
    # Setup autostart if requested  
    setup_crontab_autostart "$dir"
    
    # Create installation info
    create_installation_info "$dir"
    
    # Start the FiveM server automatically
    if [[ "${non_interactive}" == "false" ]] && [[ "$txadmin_deployment" != "1" ]]; then
        echo -e "\n${cyan}Starting FiveM Server automatically...${reset}"
        log "INFO" "Starting FiveM server"
        
        # Start the server
        "$dir/start.sh" &
        
        # Wait a moment for server to start
        sleep 5
        
        # Check if server started successfully
        if screen -list | grep -q "fivem"; then
            log "SUCCESS" "FiveM server started successfully in screen session"
            echo -e "${green}✓ FiveM server started successfully${reset}"
            echo -e "${blue}Use '$dir/attach.sh' to attach to the server console${reset}"
        else
            log "WARN" "FiveM server may not have started properly"
            echo -e "${yellow}⚠ Server startup status unclear, try '$dir/start.sh' manually${reset}"
        fi
    fi
    
    log "SUCCESS" "FiveM server installation completed successfully"
}

# =============================================================================
# ARGUMENT PARSING AND MAIN EXECUTION
# =============================================================================

# Function to display help
show_help() {
    echo -e "${bold}FiveM Server Installer v${script_version}${reset}"
    echo -e "${blue}Usage: $0 [OPTIONS]${reset}\n"
    
    echo -e "${bold}Installation Options:${reset}"
    echo -e "${green}  -d, --dir <path>${reset}          Installation directory"
    echo -e "${green}  --artifacts <version>${reset}     Specific artifacts version (number or 'latest')"
    echo -e "${green}  --list-artifacts${reset}          List available artifacts versions"
    echo -e "${green}  --update-artifacts${reset}        Update artifacts in existing installation"
    echo -e "${green}  --delete-dir${reset}              Delete existing directory before installation"
    echo -e "\n${bold}Database Options:${reset}"
    echo -e "${green}  --install-phpmyadmin${reset}      Install MariaDB and phpMyAdmin"
    echo -e "${green}  --existing-db${reset}             Configure existing database"
    echo -e "${green}  --db-host <host>${reset}          Database host (for existing db)"
    echo -e "${green}  --db-name <name>${reset}          Database name (for existing db)"  
    echo -e "${green}  --db-user <user>${reset}          Database user (for existing db)"
    echo -e "${green}  --db-password <pass>${reset}      Database password (for existing db)"
    echo -e "\n${bold}Server Options:${reset}"
    echo -e "${green}  --txadmin${reset}                 Enable txAdmin deployment"
    echo -e "${green}  --autostart${reset}               Setup crontab autostart"
    echo -e "${green}  --kill-txadmin${reset}            Kill existing txAdmin processes"
    echo -e "\n${bold}General Options:${reset}"
    echo -e "${green}  --non-interactive${reset}         Run without interactive prompts"
    echo -e "${green}  -h, --help${reset}                Show this help message"
    echo -e "${green}  --version${reset}                 Show version information"
    echo -e "\n${bold}Examples:${reset}"
    echo -e "${yellow}  $0 -d /home/user/FiveM --install-phpmyadmin${reset}"
    echo -e "${yellow}  $0 -d /home/FiveM --existing-db --db-host localhost${reset}"
    echo -e "${yellow}  $0 -d /home/user/FiveM --txadmin --autostart --non-interactive${reset}"
    echo
}

# Function to list available artifacts versions
list_artifacts_versions() {
    echo -e "${bold}Available FiveM Server Artifacts Versions:${reset}\n"
    
    echo -e "${blue}Fetching version information...${reset}"
    
    # Get recommended and latest from API
    local recommended=$(curl -s "https://changelogs-live.fivem.net/api/changelog/versions/linux/server" 2>/dev/null | grep -o '"recommended":"[^"]*' | cut -d'"' -f4)
    local latest=$(curl -s "https://changelogs-live.fivem.net/api/changelog/versions/linux/server" 2>/dev/null | grep -o '"latest":"[^"]*' | cut -d'"' -f4)
    
    # Get recent versions from artifacts page
    local recent_versions=$(curl -s "https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/" 2>/dev/null | grep -o 'href="[0-9]*/"' | grep -o '[0-9]*' | sort -nr | head -10)
    
    echo -e "${green}${bold}Recommended Versions:${reset}"
    if [[ -n "$recommended" ]]; then
        echo -e "${green}  • Recommended: ${bold}$recommended${reset}"
    fi
    if [[ -n "$latest" ]]; then
        echo -e "${green}  • Latest: ${bold}$latest${reset}"
    fi
    
    if [[ -n "$recent_versions" ]]; then
        echo -e "\n${blue}${bold}Recent Versions (last 10):${reset}"
        for version in $recent_versions; do
            if [[ "$version" == "$recommended" ]]; then
                echo -e "${green}  • $version ${bold}(recommended)${reset}"
            elif [[ "$version" == "$latest" ]]; then
                echo -e "${green}  • $version ${bold}(latest)${reset}"
            else
                echo -e "  • $version"
            fi
        done
    fi
    
    echo -e "\n${yellow}${bold}Usage:${reset}"
    echo -e "${yellow}  $0 --artifacts latest${reset}        # Use latest version"
    echo -e "${yellow}  $0 --artifacts $recommended${reset}        # Use specific version"
    echo -e "${yellow}  $0 -d /home/user/FiveM --artifacts 7290${reset}  # Complete example"
    echo
}

# Function to show version
show_version() {
    echo -e "${bold}FiveM Server Installer${reset}"
    echo -e "${blue}Version: ${script_version}${reset}"
    echo -e "${blue}Author: FiveM Community${reset}"
    echo -e "${blue}Repository: https://github.com/fivem-server-installer${reset}"
    echo
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dir)
                dir="$2"
                shift 2
                ;;
            --artifacts)
                artifacts_version="$2"
                shift 2
                ;;
            --list-artifacts)
                list_artifacts_versions
                exit 0
                ;;
            --update-artifacts)
                update_artifacts=true
                shift
                ;;
            --delete-dir)
                delete_dir=1
                shift
                ;;
            --install-phpmyadmin)
                install_phpmyadmin="true"
                shift
                ;;
            --existing-db)
                existing_db_configured=true
                install_phpmyadmin="false"
                shift
                ;;
            --db-host)
                existing_db_host="$2"
                shift 2
                ;;
            --db-name)
                existing_db_name="$2"
                shift 2
                ;;
            --db-user)
                existing_db_user="$2"
                shift 2
                ;;
            --db-password)
                existing_db_password="$2"
                shift 2
                ;;
            --txadmin)
                txadmin_deployment=1
                shift
                ;;
            --autostart)
                crontab_autostart=1
                shift
                ;;
            --kill-txadmin)
                kill_txAdmin=1
                shift
                ;;
            --non-interactive)
                non_interactive=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            *)
                echo -e "${red}Unknown option: $1${reset}"
                echo -e "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Interactive setup for missing parameters
interactive_setup() {
    if [[ "${non_interactive}" == "true" ]]; then
        return 0
    fi
    
    # Welcome message
    clear
    echo -e "\n${cyan}╔══════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║ ${bold}${green}                        FIVEM SERVER INSTALLER                         ${reset}${cyan}║${reset}"
    echo -e "${cyan}║ ${reset}${blue}                            Version: $script_version                            ${reset}${cyan}║${reset}"
    echo -e "${cyan}╚══════════════════════════════════════════════════════════════════════════════╝${reset}\n"
    
    echo -e "${green}Welcome to the FiveM Server Installer!${reset}"
    echo -e "${blue}This script will help you install and configure a FiveM server.${reset}\n"
    
    # Get installation directory if not specified
    if [[ -z "$dir" ]]; then
        # Determine default directory
        get_default_install_dir
        echo -e "${cyan}Installation Directory:${reset}"
        read -p "Enter installation directory (default: $default_dir): " dir
        dir=${dir:-$default_dir}
        log "INFO" "Installation directory set to: $dir"
    fi
    
    # Ask about txAdmin
    if [[ "$txadmin_deployment" == "0" ]]; then
        echo -e "\n${cyan}txAdmin Configuration:${reset}"
        echo -e "${blue}txAdmin provides a web-based management interface for your server.${reset}"
        
        export OPTIONS=(
            "Enable txAdmin (Recommended)"
            "Skip txAdmin setup"
        )
        
        bashSelect
        case $? in
            0)
                txadmin_deployment=1
                log "INFO" "txAdmin enabled"
                ;;
            1)
                log "INFO" "txAdmin disabled"
                ;;
        esac
    fi
    
    # Ask about autostart
    if [[ "$crontab_autostart" == "0" ]]; then
        echo -e "\n${cyan}Autostart Configuration:${reset}"
        echo -e "${blue}Setup automatic server startup on system boot?${reset}"
        
        export OPTIONS=(
            "Enable autostart"
            "Skip autostart setup"
        )
        
        bashSelect
        case $? in
            0)
                crontab_autostart=1
                log "INFO" "Autostart enabled"
                ;;
            1)
                log "INFO" "Autostart disabled"
                ;;
        esac
    fi
}

# Kill existing txAdmin processes if requested
kill_txadmin_processes() {
    if [[ "$kill_txAdmin" == "1" ]]; then
        log "INFO" "Killing existing txAdmin processes"
        pkill -f "txAdmin" 2>/dev/null || true
        pkill -f "fxserver" 2>/dev/null || true
        log "SUCCESS" "Existing processes killed"
    fi
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Gather system information
    gather_system_info
    
    # Kill txAdmin processes if requested
    kill_txadmin_processes
    
    # Interactive setup for missing parameters
    interactive_setup
    
    # Choose artifacts version
    choose_artifacts_version
    
    # Install database if requested
    installPma
    
    # Install FiveM server
    install_fivem_server
    
    # Final summary with detailed information
    clear
    local server_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "Unknown")
    
    echo -e "\n${cyan}╔══════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║ ${bold}${green}                    INSTALLATION COMPLETED SUCCESSFULLY                  ${reset}${cyan}║${reset}"
    echo -e "${cyan}║ ${reset}${blue}                        FiveM Server Installer v${script_version}                        ${reset}${cyan}║${reset}"
    echo -e "${cyan}╚══════════════════════════════════════════════════════════════════════════════╝${reset}\n"

    echo -e "${bold}${yellow}CONNECTION INFORMATION${reset}"
    echo -e "${blue}Please save these important connection details:${reset}\n"
    
    echo -e "${bold}${green}▶ FIVEM SERVER${reset}"
    echo -e "${blue}  • Server IP :${reset} ${bold}$server_ip${reset}"
    echo -e "${blue}  • Server Port :${reset} ${bold}30120${reset}"
    echo -e "${blue}  • Connection String :${reset} ${bold}connect $server_ip:30120${reset}"
    echo -e "${blue}  • Installation Directory :${reset} ${bold}$dir${reset}"
    
    if [[ "$txadmin_deployment" == "1" ]]; then
        echo -e "\n${bold}${green}▶ TXADMIN${reset}"
        echo -e "${blue}  • Access URL :${reset} ${bold}http://$server_ip:40120${reset}"
        echo -e "${blue}  • Port :${reset} ${bold}40120${reset}"
        
        case "$TXADMIN_PIN" in
            "not_available")
                echo -e "${blue}  • Status :${reset} ${red}Failed - FiveM executable not found${reset}"
                echo -e "${blue}  • Note :${reset} ${yellow}Check if FiveM artifacts were downloaded correctly${reset}"
                ;;
            "session_failed")
                echo -e "${blue}  • Status :${reset} ${red}Failed - Could not start screen session${reset}"
                echo -e "${blue}  • Note :${reset} ${yellow}Try starting manually: cd $dir && screen -dmS fivem ./fx txAdmin${reset}"
                ;;
            "check_manually")
                echo -e "${blue}  • PIN Code :${reset} ${yellow}Check manually with: screen -r fivem${reset}"
                echo -e "${blue}  • Status :${reset} ${bold}${green}Running${reset}"
                ;;
            "unknown"|"")
                echo -e "${blue}  • PIN Code :${reset} ${yellow}Not captured${reset}"
                echo -e "${blue}  • Note :${reset} ${yellow}First access will require setup${reset}"
                ;;
            *)
                if [[ "$TXADMIN_PIN" =~ ^[0-9]{4}$ ]]; then
                    echo -e "${blue}  • PIN Code :${reset} ${bold}${yellow}$TXADMIN_PIN${reset}"
                    echo -e "${blue}  • Status :${reset} ${bold}${green}Running${reset}"
                else
                    echo -e "${blue}  • PIN Code :${reset} ${yellow}$TXADMIN_PIN${reset}"
                    echo -e "${blue}  • Status :${reset} ${yellow}Check manually${reset}"
                fi
                ;;
        esac
    fi

    # Database information based on configuration
    if [[ "$existing_db_configured" == "true" ]]; then
        echo -e "\n${bold}${green}▶ DATABASE (EXISTING)${reset}"
        echo -e "${blue}  • Host/IP :${reset} ${bold}$existing_db_host${reset}"
        echo -e "${blue}  • Database :${reset} ${bold}$existing_db_name${reset}"
        echo -e "${blue}  • User :${reset} ${bold}$existing_db_user${reset}"
        echo -e "${blue}  • Password :${reset} ${bold}[Hidden for security]${reset}"
        echo -e "${blue}  • Connection String :${reset} ${bold}server=$existing_db_host;uid=$existing_db_user;password=***;database=$existing_db_name;port=3306;${reset}"
    elif [[ "$install_phpmyadmin" == "true" ]] && [[ -n "$rootPasswordMariaDB" ]]; then
        echo -e "\n${bold}${green}▶ MARIADB/MYSQL${reset}"
        echo -e "${blue}  • Host/IP :${reset} ${bold}localhost${reset}"
        echo -e "${blue}  • Port :${reset} ${bold}3306${reset}"
        echo -e "${blue}  • Database :${reset} ${bold}fivem${reset}"
        echo -e "${blue}  • User :${reset} ${bold}root${reset}"
        echo -e "${blue}  • Password :${reset} ${bold}$rootPasswordMariaDB${reset}"
        echo -e "${blue}  • Remote Access :${reset} ${bold}Enabled${reset}"

        echo -e "\n${bold}${green}▶ PHPMYADMIN${reset}"
        echo -e "${blue}  • Access URL :${reset} ${bold}http://$server_ip/phpmyadmin/${reset}"
        echo -e "${blue}  • User :${reset} ${bold}root${reset}"
        echo -e "${blue}  • Password :${reset} ${bold}$rootPasswordMariaDB${reset}"
        
        echo -e "\n${bold}${green}▶ DATABASE CONNECTION STRING${reset}"
        echo -e "${blue}  For server.cfg :${reset}"
        echo -e "${bold}  set mysql_connection_string \"server=localhost;uid=root;password=$rootPasswordMariaDB;database=fivem;port=3306;\"${reset}"
    else
        echo -e "\n${bold}${green}▶ DATABASE${reset}"
        echo -e "${blue}  • Status :${reset} ${yellow}Not configured${reset}"
        echo -e "${blue}  • Note :${reset} ${yellow}You can configure database manually later if needed${reset}"
    fi

    echo -e "\n${bold}${yellow}SYSTEM INFORMATION${reset}"
    echo -e "${blue}  • Server IP :${reset} ${bold}$server_ip${reset}"
    echo -e "${blue}  • Installation Date :${reset} ${bold}$(date)${reset}"
    echo -e "${blue}  • Log File :${reset} ${bold}$LOG_FILE${reset}"
    echo -e "${blue}  • Installation Info :${reset} ${bold}$dir/installation_info.txt${reset}"
    
    if [[ "$crontab_autostart" == "1" ]]; then
        echo -e "${blue}  • Autostart :${reset} ${bold}Enabled (will start on boot)${reset}"
    else
        echo -e "${blue}  • Autostart :${reset} ${yellow}Disabled${reset}"
    fi
    
    # Check if server is running
    local server_running=false
    local server_info=""
    
    # Check for screen session first (txAdmin)
    if screen -list | grep -q "fivem"; then
        server_running=true
        server_info="Running in screen session 'fivem'"
    # Check for background process
    elif pgrep -f "fx.*server" > /dev/null; then
        server_running=true
        local server_pid=$(pgrep -f "fx.*server" | head -1)
        server_info="Running (PID: $server_pid)"
    fi
    
    if [ "$server_running" = true ]; then
        echo -e "${blue}  • Server Status :${reset} ${bold}${green}Running${reset}"
        echo -e "${blue}  • Server Info :${reset} ${bold}$server_info${reset}"
    else
        echo -e "${blue}  • Server Status :${reset} ${yellow}Stopped${reset}"
    fi

    echo -e "\n${bold}${cyan}SERVER MANAGEMENT COMMANDS${reset}"
    
    # Check server status for appropriate commands
    if screen -list | grep -q "fivem"; then
        echo -e "${blue}• Attach to server console: ${bold}screen -r fivem${reset}"
        echo -e "${blue}• Stop server: ${bold}$dir/stop.sh${reset}"
        echo -e "${blue}• Restart server: ${bold}screen -S fivem -X quit && $dir/start.sh${reset}"
    elif pgrep -f "fx.*server" > /dev/null; then
        echo -e "${blue}• Stop server: ${bold}$dir/stop.sh${reset}"
        echo -e "${blue}• Restart server: ${bold}$dir/stop.sh && $dir/start.sh${reset}"
        echo -e "${blue}• View server logs: ${bold}tail -f $dir/server.log${reset}"
    else
        echo -e "${blue}• Start server: ${bold}$dir/start.sh${reset}"
    fi
    
    echo -e "${blue}• Edit configuration: ${bold}nano $dir/server.cfg${reset}"
    echo -e "${blue}• View installation logs: ${bold}tail -f $LOG_FILE${reset}"

    echo -e "\n${bold}${cyan}NEXT STEPS${reset}"
    echo -e "${blue}1. ${bold}REQUIRED:${reset} Get your license key from ${bold}https://keymaster.fivem.net/${reset}"
    echo -e "${blue}2. Edit your server configuration: ${bold}nano $dir/server.cfg${reset}"
    echo -e "${blue}3. Add your license key to server.cfg"
    echo -e "${blue}4. Configure server settings (hostname, description, etc.)"
    echo -e "${blue}5. Add admin permissions in permissions.cfg"
    if ! screen -list | grep -q "fivem" && ! pgrep -f "fx.*server" > /dev/null; then
        echo -e "${blue}6. Start your server: ${bold}cd $dir && ./run.sh${reset}"
    fi

    echo -e "\n${bold}${cyan}IMPORTANT NOTES${reset}"
    echo -e "${blue}• Make sure to open port 30120 (TCP/UDP) in your firewall"
    if [[ "$txadmin_deployment" == "1" ]]; then
        echo -e "${blue}• Make sure to open port 40120 (TCP) for txAdmin access"
    fi
    echo -e "${blue}• Save all passwords and connection information in a secure location"
    echo -e "${blue}• Check the installation info file for complete details"

    echo -e "\n${bold}${cyan}SUPPORT & DOCUMENTATION${reset}"
    echo -e "${blue}• FiveM Documentation: ${bold}https://docs.fivem.net/${reset}"
    echo -e "${blue}• FiveM Forum: ${bold}https://forum.cfx.re/${reset}"
    echo -e "${blue}• FiveM Discord: ${bold}https://discord.gg/fivem${reset}"

    echo -e "\n${green}${bold}✓ FiveM Server installation completed successfully!${reset}"
    echo -e "${yellow}Thank you for using the FiveM Server Installer${reset}\n"
    
    cleanup_and_exit 0 "${green}Installation completed successfully!${reset}"
}

# Execute main function with all arguments
main "$@" 
