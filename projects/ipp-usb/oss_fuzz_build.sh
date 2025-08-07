#!/bin/bash

# oss_fuzz_build.sh for ipp-usb

set -e

# Build ipp-usb from source
cd "${SRC}/ipp-usb"
go build -o "${OUT}/ipp-usb" ./cmd/ipp-usb

# Build the IPP over USB simulator
cd "${SRC}/openprinting-fuzzing/projects/ipp-usb/simulator"
go build -o "${OUT}/ipp-printer" ipp_printer.go USBIP.go

# Build the AFL++ harness
cd "${SRC}/openprinting-fuzzing/projects/ipp-usb/fuzzer"
$CC $CFLAGS -o "${OUT}/ipp_usb_harness" ipp_usb_harness.c $LIB_FUZZING_ENGINE

# Copy scripts and configuration
cp fuzz_ipp_usb.sh "${OUT}/"
cp setup_environment.sh "${OUT}/"
cp cleanup.sh "${OUT}/"

# Copy seed corpus
cp -r ../seeds/* "${OUT}/"

# Make scripts executable
chmod +x "${OUT}"/fuzz_ipp_usb.sh
chmod +x "${OUT}"/setup_environment.sh
chmod +x "${OUT}"/cleanup.sh