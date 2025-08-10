#!/bin/bash

# Setup script for ipp-usb fuzzing environment
set -e

echo "Setting up ipp-usb fuzzing environment..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for a port to be available
wait_for_port() {
    local host=$1
    local port=$2
    local timeout=${3:-30}
    
    echo "Waiting for $host:$port to be available..."
    for i in $(seq 1 $timeout); do
        if nc -z $host $port 2>/dev/null; then
            echo "Port $host:$port is available"
            return 0
        fi
        sleep 1
    done
    echo "Timeout waiting for $host:$port"
    return 1
}

# Check required tools
if ! command_exists usbip; then
    echo "Error: usbip not found"
    exit 1
fi

if ! command_exists modprobe; then
    echo "Error: modprobe not found"
    exit 1
fi

# Load USBIP kernel modules
echo "Loading USBIP kernel modules..."
modprobe usbip_core || echo "Warning: Could not load usbip_core module"
modprobe vhci_hcd || echo "Warning: Could not load vhci_hcd module"

# Wait a moment for modules to initialize
sleep 2

# Check if mfp-proxy exists
if [ ! -f "/out/mfp-proxy" ]; then
    echo "Error: mfp-proxy not found at /out/mfp-proxy"
    exit 1
fi

# Start mfp-proxy in background
echo "Starting mfp-proxy..."
/out/mfp-proxy -v -U --ipp=/ipp/print=ipp://localhost:631/printers/TestPrinter &
PROXY_PID=$!

# Store PID for cleanup
echo $PROXY_PID > /tmp/mfp-proxy.pid

# Wait for proxy to start
sleep 3

# Try to list available USBIP devices
echo "Checking available USBIP devices..."
usbip list -r 127.0.0.1 || echo "Warning: Could not list USBIP devices"

# Attach virtual device
echo "Attaching virtual USB device..."
usbip attach -r 127.0.0.1 -b 1-1 || echo "Warning: Could not attach virtual device"

# Wait for device attachment
sleep 2

# Check if ipp-usb exists
if [ ! -f "/out/ipp-usb" ]; then
    echo "Error: ipp-usb not found at /out/ipp-usb"
    exit 1
fi

echo "Environment setup completed"
echo "You can now run ipp-usb with: /out/ipp-usb standalone"