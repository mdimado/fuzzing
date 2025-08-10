#!/bin/bash

# Cleanup script for ipp-usb fuzzing environment
echo "Cleaning up ipp-usb fuzzing environment..."

# Kill ipp-usb processes
pkill -f "ipp-usb" || true

# Kill mfp-proxy processes
if [ -f "/tmp/mfp-proxy.pid" ]; then
    PID=$(cat /tmp/mfp-proxy.pid)
    kill $PID 2>/dev/null || true
    rm -f /tmp/mfp-proxy.pid
fi
pkill -f "mfp-proxy" || true

# Detach USBIP devices
usbip detach -p 00 2>/dev/null || true
usbip detach -p 01 2>/dev/null || true

# Wait for processes to terminate
sleep 2

# Remove USBIP modules (optional, might fail in containers)
rmmod vhci_hcd 2>/dev/null || true
rmmod usbip_core 2>/dev/null || true

echo "Cleanup completed"