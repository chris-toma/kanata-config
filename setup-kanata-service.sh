#!/bin/bash

# Script to set up Kanata as a systemd service
# This script checks if the service already exists and only creates it if it doesn't

set -e

# Configuration
CONFIG_FILE="configV1.kbd"
SERVICE_NAME="kanata.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_DIR="/etc/kanata"
CONFIG_PATH="${CONFIG_DIR}/${CONFIG_FILE}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Function to detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Function to install kanata from GitHub releases
install_kanata_from_github() {
    print_status "Installing Kanata from GitHub releases..."
    
    # Check for required tools and install if missing
    if ! command -v curl &> /dev/null; then
        print_status "Installing curl..."
        apt update && apt install -y curl
    fi
    
    if ! command -v wget &> /dev/null; then
        print_status "Installing wget..."
        apt update && apt install -y wget
    fi
    
    # Verify tools are now available
    if ! command -v curl &> /dev/null || ! command -v wget &> /dev/null; then
        print_error "Failed to install required tools (curl/wget)"
        return 1
    fi
    
    # Detect architecture
    local arch=$(uname -m)
    case "$arch" in
        "x86_64")
            arch="x86_64"
            ;;
        "aarch64"|"arm64")
            arch="aarch64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    # Get latest release info
    local latest_release=$(curl -s https://api.github.com/repos/jtroo/kanata/releases/latest)
    local download_url=$(echo "$latest_release" | grep "browser_download_url.*linux-${arch}" | cut -d '"' -f 4)
    
    if [[ -z "$download_url" ]]; then
        print_error "Could not find download URL for architecture: $arch"
        return 1
    fi
    
    print_status "Downloading Kanata from: $download_url"
    
    # Download and install
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    if ! wget -q "$download_url" -O kanata.tar.gz; then
        print_error "Failed to download Kanata"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! tar -xzf kanata.tar.gz; then
        print_error "Failed to extract Kanata archive"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Find the kanata binary in the extracted files
    local kanata_binary=$(find . -name "kanata" -type f -executable | head -1)
    
    if [[ -z "$kanata_binary" ]]; then
        print_error "Could not find kanata binary in archive"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Install to /usr/bin
    print_status "Installing kanata to /usr/bin/"
    cp "$kanata_binary" /usr/bin/kanata
    chmod +x /usr/bin/kanata
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    print_status "Kanata installed successfully from GitHub!"
    return 0
}

# Function to install kanata
install_kanata() {
    local distro=$(detect_distro)
    
    print_status "Kanata not found. Attempting to install..."
    
    case "$distro" in
        "ubuntu"|"debian")
            print_status "Detected Ubuntu/Debian. Installing kanata..."
            
            # Get Ubuntu version for better compatibility
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                if [[ "$ID" == "ubuntu" ]]; then
                    print_status "Ubuntu version: $VERSION"
                fi
            fi
            
            # Update package lists
            print_status "Updating package lists..."
            apt update
            
            # Try to install kanata from official repos first
            if apt install -y kanata; then
                print_status "Kanata installed from official repositories"
            else
                print_warning "Kanata not available in official repositories"
                print_status "Adding kanata PPA (Personal Package Archive)..."
                
                # Add kanata PPA if available
                if command -v add-apt-repository &> /dev/null; then
                    add-apt-repository -y ppa:jtroo/kanata 2>/dev/null || true
                    apt update
                else
                    print_status "Installing software-properties-common for add-apt-repository..."
                    apt install -y software-properties-common
                    add-apt-repository -y ppa:jtroo/kanata 2>/dev/null || true
                    apt update
                fi
                
                if apt install -y kanata; then
                    print_status "Kanata installed from PPA"
                else
                    print_warning "PPA installation failed, trying GitHub releases..."
                    install_kanata_from_github
                    return $?
                fi
            fi
            ;;
        "fedora"|"rhel"|"centos")
            print_status "Detected Fedora/RHEL/CentOS. Installing kanata..."
            if command -v dnf &> /dev/null; then
                dnf install -y kanata
            elif command -v yum &> /dev/null; then
                yum install -y kanata
            else
                print_error "Neither dnf nor yum found"
                return 1
            fi
            ;;
        "arch"|"manjaro")
            print_status "Detected Arch/Manjaro. Installing kanata..."
            pacman -S --noconfirm kanata
            ;;
        "opensuse"|"sles")
            print_status "Detected openSUSE/SLES. Installing kanata..."
            zypper install -y kanata
            ;;
        *)
            print_warning "Unsupported distribution: $distro"
            print_status "Attempting to install from GitHub releases..."
            install_kanata_from_github
            return $?
            ;;
    esac
    
    # Verify installation
    if command -v kanata &> /dev/null; then
        print_status "Kanata successfully installed via package manager!"
        return 0
    else
        print_warning "Package manager installation failed, trying GitHub releases..."
        install_kanata_from_github
        return $?
    fi
}

# Check if kanata is installed, install if not
if ! command -v kanata &> /dev/null; then
    if ! install_kanata; then
        print_error "Failed to install Kanata. Please install manually."
        exit 1
    fi
fi

# Check if the service already exists
if systemctl list-unit-files | grep -q "${SERVICE_NAME}"; then
    print_warning "Service ${SERVICE_NAME} already exists"
    print_warning "Skipping service creation"
    exit 0
fi

# Create config directory if it doesn't exist
if [[ ! -d "$CONFIG_DIR" ]]; then
    print_status "Creating config directory: $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
fi

# Copy config file to system location
if [[ -f "$CONFIG_FILE" ]]; then
    print_status "Copying config file to $CONFIG_PATH"
    cp "$CONFIG_FILE" "$CONFIG_PATH"
    chmod 644 "$CONFIG_PATH"
else
    print_error "Config file $CONFIG_FILE not found in current directory"
    exit 1
fi

# Create the systemd service file
print_status "Creating systemd service file: $SERVICE_PATH"

cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Kanata Service
Requires=local-fs.target
After=local-fs.target

[Service]
ExecStartPre=/usr/bin/modprobe uinput
ExecStart=/usr/bin/kanata -c $CONFIG_PATH
Restart=no

[Install]
WantedBy=sysinit.target
EOF

# Set proper permissions
chmod 644 "$SERVICE_PATH"

# Reload systemd daemon
print_status "Reloading systemd daemon"
systemctl daemon-reload

# Enable the service
print_status "Enabling kanata service"
systemctl enable "$SERVICE_NAME"

print_status "Kanata service has been successfully set up!"
print_status "Service file: $SERVICE_PATH"
print_status "Config file: $CONFIG_PATH"
print_status ""
print_status "To start the service now, run:"
print_status "  systemctl start $SERVICE_NAME"
print_status ""
print_status "To check service status, run:"
print_status "  systemctl status $SERVICE_NAME"
print_status ""
print_status "The service will start automatically on boot."
