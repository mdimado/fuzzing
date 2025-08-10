#!/bin/bash -eu

# OSS-Fuzz build script for ipp-usb
cd $SRC/ipp-usb

echo "Building ipp-usb fuzzers..."

# Update go.mod to use a newer Go version that supports fuzzing
go mod edit -go=1.18

# Enable module mode and allow module updates
export GO111MODULE=on
go mod tidy

# Compile fuzzers using Go's built-in fuzzing support for libFuzzer
# This creates libFuzzer-compatible binaries from Go fuzz functions

# Build the main HTTP fuzzer
compile_native_go_fuzzer . FuzzHTTPInterface fuzz_ipp_usb_http

# Build the IPP message fuzzer  
compile_native_go_fuzzer . FuzzIPPMessage fuzz_ipp_usb_message

# Build the USB descriptor fuzzer
compile_native_go_fuzzer . FuzzUSBDescriptor fuzz_ipp_usb_descriptor

# Copy seed corpora if they exist
echo "Copying seed corpora..."
if [ -d "fuzzer/seeds" ]; then
    if [ -d "fuzzer/seeds/fuzz_ipp_usb_http_seed_corpus" ]; then
        cp -r fuzzer/seeds/fuzz_ipp_usb_http_seed_corpus $OUT/
    fi
    if [ -d "fuzzer/seeds/fuzz_ipp_usb_message_seed_corpus" ]; then
        cp -r fuzzer/seeds/fuzz_ipp_usb_message_seed_corpus $OUT/
    fi
    if [ -d "fuzzer/seeds/fuzz_ipp_usb_descriptor_seed_corpus" ]; then
        cp -r fuzzer/seeds/fuzz_ipp_usb_descriptor_seed_corpus $OUT/
    fi
fi

# Copy auxiliary files if they exist
echo "Copying auxiliary files..."
if [ -f "fuzzer/setup_environment.sh" ]; then
    cp fuzzer/setup_environment.sh $OUT/
    chmod +x $OUT/setup_environment.sh
fi
if [ -f "fuzzer/cleanup.sh" ]; then
    cp fuzzer/cleanup.sh $OUT/
    chmod +x $OUT/cleanup.sh
fi

echo "ipp-usb fuzzers built successfully"