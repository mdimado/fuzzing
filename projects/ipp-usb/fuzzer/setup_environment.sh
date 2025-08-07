#!/bin/bash

# setup_environment.sh - One-time setup for ipp-usb fuzzing environment

set -e

echo "Setting up ipp-usb fuzzing environment..."

# Build the IPP over USB simulator
cd simulator/
./build_simulator.sh
cd ..

# Build the AFL++ harness
cd fuzzer/
make clean
make ipp_usb_harness
chmod +x fuzz_ipp_usb.sh
cd ..

echo "Environment setup complete!"
echo "Make sure usbip kernel modules are available:"
echo "  sudo modprobe usbip_core"
echo "  sudo modprobe vhci_hcd"