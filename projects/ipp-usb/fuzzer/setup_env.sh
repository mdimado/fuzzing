#!/bin/bash
# Simplified environment setup for USBIP-based fuzzing
# The main fuzzer now handles USBIP setup directly

set -e

# Function to cleanup processes on exit
cleanup() {
    echo "Cleaning up..."
    pkill -f "ipp-usb" || true
    # Detach USBIP devices
    usbip detach -p 00 || true
    sleep 1
}

# Set trap for cleanup
trap cleanup EXIT

# Load USBIP kernel modules (may fail in container, that's OK)
echo "Loading USBIP kernel modules..."
modprobe usbip_core 2>/dev/null || echo "usbip_core module load failed (may be OK in container)"
modprobe vhci_hcd 2>/dev/null || echo "vhci_hcd module load failed (may be OK in container)"

# Copy ipp-usb binary to /tmp if not already there
if [ ! -f "/tmp/ipp-usb" ]; then
    if [ -f "/out/ipp-usb" ]; then
        cp /out/ipp-usb /tmp/ipp-usb
    elif [ -f "./ipp-usb" ]; then
        cp ./ipp-usb /tmp/ipp-usb
    else
        echo "ipp-usb binary not found"
        exit 1
    fi
fi

chmod +x /tmp/ipp-usb

echo "Environment setup complete for USBIP fuzzing"
echo "The fuzzer will handle USBIP device creation and ipp-usb startup directly"
sleep 2

# Load USBIP kernel modules (may fail in container, that's OK)
echo "Loading USBIP kernel modules..."
modprobe usbip_core 2>/dev/null || echo "usbip_core module load failed (may be OK in container)"
modprobe vhci_hcd 2>/dev/null || echo "vhci_hcd module load failed (may be OK in container)"

# Wait a bit more for modules to initialize
sleep 1

# List and attach the virtual device
echo "Attaching USBIP virtual device..."
usbip list -r 127.0.0.1 || echo "USBIP list failed, continuing..."
usbip attach -r 127.0.0.1 -b 1-1 || echo "USBIP attach failed, continuing..."

# Wait for device attachment
sleep 2

# Find available port for ipp-usb
IPP_PORT=60000
while netstat -ln | grep -q ":$IPP_PORT "; do
    IPP_PORT=$((IPP_PORT + 1))
    if [ $IPP_PORT -gt 65535 ]; then
        echo "No available ports found"
        exit 1
    fi
done

# Start ipp-usb daemon
echo "Starting ipp-usb daemon..."
export IPP_USB_PORT=$IPP_PORT

# Build ipp-usb if not already built
if [ ! -f "/tmp/ipp-usb" ]; then
    if [ -f "/out/ipp-usb" ]; then
        cp /out/ipp-usb /tmp/ipp-usb
    else
        # Try to build from source
        cd $SRC/ipp-usb 2>/dev/null || cd /tmp
        if [ -f "go.mod" ]; then
            CGO_ENABLED=1 go build -o /tmp/ipp-usb .
        else
            echo "ipp-usb binary not found and cannot build"
            exit 1
        fi
    fi
fi

chmod +x /tmp/ipp-usb
cd /tmp

# Run ipp-usb in standalone mode
./ipp-usb standalone &
IPP_USB_PID=$!

# Wait for ipp-usb to initialize and find devices
echo "Waiting for ipp-usb to initialize..."
sleep 5

# Try to find the actual port ipp-usb is using
for i in {1..10}; do
    # Check netstat for ipp-usb listening ports in the range 60000-65535
    ACTUAL_PORT=$(netstat -tlnp 2>/dev/null | grep ipp-usb | grep -o ':[0-9]*' | grep -o '[0-9]*' | head -1)
    if [ -n "$ACTUAL_PORT" ] && [ "$ACTUAL_PORT" -ge 60000 ] && [ "$ACTUAL_PORT" -le 65535 ]; then
        IPP_PORT=$ACTUAL_PORT
        break
    fi
    sleep 1
done

echo "IPP_PORT=$IPP_PORT"
echo "Setup complete. ipp-usb should be listening on port $IPP_PORT"

# Test basic connectivity
timeout 5 curl -s "http://localhost:$IPP_PORT/ipp/print" >/dev/null 2>&1 || echo "Initial connectivity test failed (this may be normal)"

# Keep the setup running for fuzzing
# The cleanup trap will handle termination
wait