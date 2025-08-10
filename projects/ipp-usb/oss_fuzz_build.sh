#!/bin/bash -eu

# OSS-Fuzz build script for ipp-usb
cd $SRC/ipp-usb

echo "Building ipp-usb fuzzers..."

# Simply use readonly mode to respect existing vendor directory
export GOFLAGS="-mod=readonly"

# Build fuzzers directly with the existing setup
compile_native_go_fuzzer . FuzzHTTPInterface fuzz_ipp_usb_http
compile_native_go_fuzzer . FuzzIPPMessage fuzz_ipp_usb_message  
compile_native_go_fuzzer . FuzzUSBDescriptor fuzz_ipp_usb_descriptor

# Copy seed corpora if they exist
if [ -d "testdata" ]; then
    cp -r testdata $OUT/ 2>/dev/null || true
fi

echo "ipp-usb fuzzers built successfully"