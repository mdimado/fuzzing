#!/bin/bash

# cleanup.sh - Cleanup script for ipp-usb fuzzing (container-friendly)

set -e

echo "Cleaning up ipp-usb fuzzing environment..."

# Source environment variables
if [ -f "${OUT}/fuzz_env.sh" ]; then
    source "${OUT}/fuzz_env.sh"
fi

NO_SUDO=${NO_SUDO:-0}
SUDO_CMD=""
if [ "$NO_SUDO" = "0" ]; then
    SUDO_CMD="sudo"
fi

if [ -f /.dockerenv ] || [ "$NO_SUDO" = "1" ]; then
    SUDO_CMD=""
fi

# Kill processes using saved PIDs first
if [ -f "${OUT}/ippusb.pid" ]; then
    IPP_USB_PID=$(cat "${OUT}/ippusb.pid")
    echo "Killing ipp-usb process (PID: $IPP_USB_PID)..."
    kill $IPP_USB_PID 2>/dev/null || true
    rm -f "${OUT}/ippusb.pid"
fi

if [ -f "${OUT}/simulator.pid" ]; then
    SIMULATOR_PID=$(cat "${OUT}/simulator.pid")
    echo "Killing simulator process (PID: $SIMULATOR_PID)..."
    kill $SIMULATOR_PID 2>/dev/null || true
    rm -f "${OUT}/simulator.pid"
fi

# Kill any remaining processes
echo "Stopping any remaining ipp-usb processes..."
${SUDO_CMD} pkill -f ipp-usb 2>/dev/null || true

echo "Stopping any remaining simulator processes..."
${SUDO_CMD} pkill -f ipp-printer 2>/dev/null || true

# Detach any attached USB/IP devices
echo "Detaching USB/IP devices..."
${SUDO_CMD} usbip detach -p 00 2>/dev/null || true
${SUDO_CMD} usbip detach -p 01 2>/dev/null || true

# Wait for processes to fully terminate
sleep 2

# Remove temporary files
echo "Cleaning temporary files..."
rm -f /tmp/fuzz_input_* 2>/dev/null || true
rm -f /tmp/ipp_usb_* 2>/dev/null || true
rm -f "${OUT}/runtime_env.sh" 2>/dev/null || true

echo "Cleanup complete!"