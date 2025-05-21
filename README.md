# FiveM Server Installer

![FiveM Logo](https://avatars.githubusercontent.com/u/54678068?s=200&v=4)

A comprehensive bash script for easily installing and managing FiveM servers on Linux. This enhanced installer provides an improved user experience with better logging, custom installation paths, and more configuration options.

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Features

- **Easy Installation**: Set up a FiveM server with just one command
- **Enhanced Logging**: Detailed logs for easy troubleshooting
- **Custom Installation Paths**: Choose where to install your server
- **TxAdmin Integration**: Deploy with TxAdmin or use cfx-server-data
- **Auto-start Option**: Configure crontab for automatic startup
- **Database Support**: Optional MariaDB/MySQL and phpMyAdmin installation
- **User-friendly Interface**: Clear menu options and guidance
- **Automatic Updates**: Keep your FiveM server up to date easily

## Quick Start

Run the installer with a single command:

```bash
bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh)
```

> **Note**: This script requires root permissions to install properly.

## Installation Options

### Interactive Mode

By default, the script runs in interactive mode, guiding you through the installation process with menus:

1. Choose between installing a new server or updating an existing one
2. Select installation path (defaults to `/home/FiveM` or user's home directory)
3. Choose deployment type (TxAdmin or cfx-server-data)
4. Select FiveM version (latest, recommended, or custom)
5. Configure optional features like auto-start and database

### Non-Interactive Mode

For automated installations, you can use various command line options:

```bash
bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh) \
    --non-interactive \
    --dir /path/to/install \
    --crontab \
    --version latest
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help message |
| `--non-interactive` | Skip all prompts, using default values or provided options |
| `-v, --version <URL\|latest>` | Choose artifacts version (default: latest) |
| `-u, --update <path>` | Update the artifacts in the specified directory |
| `--no-txadmin` | Use cfx-server-data instead of TxAdmin |
| `-c, --crontab` | Enable automatic startup via crontab |
| `--kill-port` | Forcefully stop any process on the TxAdmin port (40120) |
| `--delete-dir` | Forcefully delete the installation directory if it exists |
| `-d, --dir <path>` | Specify a custom installation path |

### phpMyAdmin Options

| Option | Description |
|--------|-------------|
| `-p, --phpmyadmin` | Install MariaDB/MySQL and phpMyAdmin |
| `--security` | Use security mode for phpMyAdmin (requires user and password) |
| `--simple` | Use simple mode for phpMyAdmin installation |
| `--db_user <name>` | Specify database username |
| `--db_password <password>` | Set database password |
| `--generate_password` | Generate a secure password automatically |
| `--reset_password` | Reset the database password if it exists |
| `--remove_db` | Remove and reinstall MySQL/MariaDB |
| `--remove_pma` | Remove and reinstall phpMyAdmin |

## Usage Examples

### Basic Installation (Interactive)

```bash
bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh)
```

### Custom Installation Path

```bash
bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh) -d /opt/my-fivem-server
```

### Update Existing Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh) -u /path/to/fivem
```

### Automated Installation with phpMyAdmin

```bash
bash <(curl -s https://raw.githubusercontent.com/Dolyyyy/fiveminstaller/refs/heads/main/setup.sh) \
    --non-interactive \
    --phpmyadmin \
    --simple
```

## After Installation

After successful installation, the script will:

1. Start the TxAdmin interface automatically
2. Provide a PIN for initial access (valid for 5 minutes)
3. Show the URL for the web interface
4. Create scripts for managing the server:
   - `start.sh`: Start the FiveM server
   - `stop.sh`: Stop the FiveM server
   - `attach.sh`: Access the live console
5. Save all installation information to `installation_info.txt`

## Troubleshooting

All installation logs are saved to `/tmp/fivem_install.log` for troubleshooting.

Common issues:

- **Port 40120 already in use**: Use `--kill-port` to forcefully stop processes on that port
- **Directory already exists**: Use `--delete-dir` to remove existing installation
- **Installation fails**: Check the logs for detailed error messages

## System Requirements

- **OS**: Ubuntu/Debian-based Linux distribution
- **RAM**: 4+ GB recommended (2GB minimum)
- **CPU**: 2+ cores recommended
- **Storage**: 4+ GB free space
- **Network**: Static IP recommended
- **Root access** or sudo privileges

## Credentials

- Original script by [Twe3x](https://github.com/Twe3x/fivem-installer)
- Enhanced by [Dolyyyy](https://github.com/Dolyyyy)
- phpMyAdmin installer by [JulianGransee](https://github.com/JulianGransee/PHPMyAdminInstaller)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
