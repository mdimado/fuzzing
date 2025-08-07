#!/bin/bash

# fuzz_ipp_usb.sh - AFL++ wrapper for ipp-usb fuzzing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IPP_USB_BIN="${IPP_USB_BIN:-/usr/local/bin/ipp-usb}"
SIMULATOR_BIN="${SCRIPT_DIR}/../simulator/ipp-printer"
CONFIG_FILE="${SCRIPT_DIR}/../simulator/ipp_usb_config.json"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    pkill -f ipp-usb || true
    pkill -f ipp-printer || true
    sudo usbip detach -p 00 || true
    sleep 2
}

# Setup function
setup() {
    echo "Setting up environment..."
    
    # Load required kernel modules
    sudo modprobe usbip_core || true
    sudo modprobe vhci_hcd || true
    
    # Start the IPP over USB simulator
    sudo "${SIMULATOR_BIN}" &
    SIMULATOR_PID=$!
    sleep 3
    
    # Attach the virtual device
    sudo usbip attach -r 127.0.0.1 -b 1-1
    sleep 2
    
    # Start ipp-usb daemon
    sudo "${IPP_USB_BIN}" -debug &
    IPP_USB_PID=$!
    sleep 5
    
    echo "Setup complete. Simulator PID: $SIMULATOR_PID, ipp-usb PID: $IPP_USB_PID"
}

# Fuzzing function
fuzz_with_input() {
    local input_file="$1"
    
    if [ ! -f "$input_file" ]; then
        echo "Input file not found: $input_file"
        return 1
    fi
    
    # Send fuzzed data via HTTP to ipp-usb
    # ipp-usb typically runs on localhost with a specific port
    # You'll need to determine the exact endpoint
    curl -X POST \
         -H "Content-Type: application/ipp" \
         -d @"$input_file" \
         --max-time 10 \
         --connect-timeout 5 \
         "http://localhost:60000/ipp/print" 2>/dev/null || true
}

# Main execution
main() {
    trap cleanup EXIT
    
    if [ "$#" -ne 1 ]; then
        echo "Usage: $0 <input_file>"
        exit 1
    fi
    
    local input_file="$1"
    
    setup
    fuzz_with_input "$input_file"
    cleanup
}

# Run only if called directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi