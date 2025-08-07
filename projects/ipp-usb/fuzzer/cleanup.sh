#!/bin/bash

# cleanup.sh - Cleanup script for ipp-usb fuzzing

set -e

echo "Cleaning up ipp-usb fuzzing environment..."

# Kill any running ipp-usb processes
echo "Stopping ipp-usb processes..."
sudo pkill -f ipp-usb || true

# Kill any running simulator processes
echo "Stopping simulator processes..."
sudo pkill -f ipp-printer || true

# Detach any attached USB/IP devices
echo "Detaching USB/IP devices..."
sudo usbip detach -p 00 || true
sudo usbip detach -p 01 || true

# Wait a moment for processes to fully terminate
sleep 2

# Remove any temporary files
echo "Cleaning temporary files..."
rm -f /tmp/fuzz_input_* || true
rm -f /tmp/ipp_usb_* || true

# Optional: Unload kernel modules (commented out as they might be used by other processes)
# sudo modprobe -r vhci_hcd || true
# sudo modprobe -r usbip_core || true

echo "Cleanup complete!"