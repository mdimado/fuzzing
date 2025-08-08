#!/bin/bash

# setup_environment.sh - Setup for ipp-usb fuzzing (container-friendly)

set -e

echo "Setting up ipp-usb fuzzing environment (container mode)..."

# Source environment variables
if [ -f "${OUT}/fuzz_env.sh" ]; then
    source "${OUT}/fuzz_env.sh"
fi

# In container, we're already root, so no sudo needed
NO_SUDO=${NO_SUDO:-0}

SUDO_CMD=""
if [ "$NO_SUDO" = "0" ]; then
    SUDO_CMD="sudo"
fi

# Check if we're in a container (common indicators)
if [ -f /.dockerenv ] || [ "$NO_SUDO" = "1" ]; then
    echo "Running in container mode (no sudo)"
    SUDO_CMD=""
fi

# Load required kernel modules (may fail in containers - that's ok)
echo "Loading kernel modules..."
modprobe usbip_core 2>/dev/null || echo "usbip_core module load failed (may not be available)"
modprobe vhci_hcd 2>/dev/null || echo "vhci_hcd module load failed (may not be available)"

# Start the IPP over USB simulator in background
echo "Starting IPP over USB simulator..."
${SUDO_CMD} "${SIMULATOR_BIN}" &
SIMULATOR_PID=$!
echo "Simulator started with PID: $SIMULATOR_PID"

# Wait for simulator to start
sleep 5

# Try to attach the virtual device (may fail in containers without USB/IP support)
echo "Attempting to attach virtual USB device..."
${SUDO_CMD} usbip attach -r 127.0.0.1 -b 1-1 2>/dev/null || {
    echo "USB/IP attach failed - this is expected in some container environments"
    echo "Continuing with network-only mode..."
}

# Wait a bit more
sleep 2

# Start ipp-usb daemon
echo "Starting ipp-usb daemon..."
${SUDO_CMD} "${IPP_USB_BIN}" -debug &
IPP_USB_PID=$!
echo "ipp-usb started with PID: $IPP_USB_PID"

# Wait for services to fully start
sleep 8

# Test if ipp-usb is responding (find the actual port it's using)
echo "Testing ipp-usb connectivity..."
for port in 60000 8080 631 8631; do
    if netcat -z localhost $port 2>/dev/null; then
        echo "Found ipp-usb listening on port $port"
        echo "export IPP_USB_PORT=$port" >> "${OUT}/runtime_env.sh"
        break
    fi
done

echo "Setup complete!"
echo "Simulator PID: $SIMULATOR_PID"
echo "ipp-usb PID: $IPP_USB_PID"

# Save PIDs for cleanup
echo "$SIMULATOR_PID" > "${OUT}/simulator.pid"
echo "$IPP_USB_PID" > "${OUT}/ippusb.pid"