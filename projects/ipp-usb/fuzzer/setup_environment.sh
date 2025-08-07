#!/bin/bash

# setup_environment.sh - Setup for ipp-usb fuzzing environment

set -e

echo "Setting up ipp-usb fuzzing environment..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're in OSS-Fuzz environment
if [ -d "/out" ] && [ ! -w "/proc/sys/vm/mmap_rnd_bits" ]; then
    echo "Detected OSS-Fuzz environment - skipping system setup"
    
    # In OSS-Fuzz, we can't run system services or load kernel modules
    # Just check if our binaries exist
    if [ -f "${SCRIPT_DIR}/ipp-usb" ]; then
        echo "Found ipp-usb binary"
    else
        echo "Warning: ipp-usb binary not found"
    fi
    
    if [ -f "${SCRIPT_DIR}/ipp-printer" ]; then
        echo "Found ipp-printer simulator"
    else
        echo "Warning: ipp-printer simulator not found"
    fi
    
    echo "OSS-Fuzz setup complete (limited environment)"
    exit 0
fi

# Full setup for local testing environment
echo "Setting up full environment (local testing)..."

# Check if running as root for USB/IP operations
if [ "$EUID" -ne 0 ]; then
    echo "Warning: Not running as root - some operations may fail"
fi

# Try to load kernel modules (ignore failures in restricted environments)
echo "Loading kernel modules..."
modprobe usbip_core 2>/dev/null || echo "Warning: Could not load usbip_core module"
modprobe vhci_hcd 2>/dev/null || echo "Warning: Could not load vhci_hcd module"

# Build the IPP over USB simulator if needed
if [ -d "${SCRIPT_DIR}/../simulator" ]; then
    echo "Building simulator..."
    cd "${SCRIPT_DIR}/../simulator"
    if [ -f "ipp_printer.go" ] && [ -f "USBIP.go" ]; then
        go build -o "${SCRIPT_DIR}/ipp-printer" ipp_printer.go USBIP.go || {
            echo "Warning: Failed to build simulator"
        }
    fi
elif [ -f "${SCRIPT_DIR}/ipp-printer" ]; then
    echo "Using pre-built simulator"
else
    echo "Warning: No simulator found"
fi

# Start the IPP over USB simulator (background process)
if [ -f "${SCRIPT_DIR}/ipp-printer" ]; then
    echo "Starting IPP over USB simulator..."
    "${SCRIPT_DIR}/ipp-printer" &
    SIMULATOR_PID=$!
    echo "Simulator started with PID: $SIMULATOR_PID"
    sleep 3
    
    # Try to attach the virtual device (ignore failures)
    echo "Attempting to attach virtual USB device..."
    usbip attach -r 127.0.0.1 -b 1-1 2>/dev/null || {
        echo "Warning: Could not attach virtual USB device"
    }
else
    echo "Warning: Simulator not available"
fi

# Start ipp-usb daemon if available
if [ -f "${SCRIPT_DIR}/ipp-usb" ]; then
    echo "Starting ipp-usb daemon..."
    "${SCRIPT_DIR}/ipp-usb" -debug &
    IPP_USB_PID=$!
    echo "ipp-usb started with PID: $IPP_USB_PID"
    sleep 5
else
    echo "Warning: ipp-usb binary not found"
fi

echo "Setup complete!"
echo "Note: In restricted environments, some services may not start properly"