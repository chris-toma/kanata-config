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

# Check if kanata is installed
if ! command -v kanata &> /dev/null; then
    print_error "Kanata is not installed or not in PATH"
    print_error "Please install Kanata first: https://github.com/jtroo/kanata"
    exit 1
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
