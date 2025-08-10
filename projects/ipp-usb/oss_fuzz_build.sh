#!/bin/bash -eu

# OSS-Fuzz build script for ipp-usb  
cd $SRC/ipp-usb

echo "Building ipp-usb fuzzers..."

# Use readonly mode to respect existing vendor directory
export GOFLAGS="-mod=readonly"

# Find the correct fuzzer path
if [ -d "./fuzzer" ]; then
    FUZZER_PATH="./fuzzer"
elif [ -d "/src/fuzzing/projects/ipp-usb/fuzzer" ]; then
    FUZZER_PATH="/src/fuzzing/projects/ipp-usb/fuzzer"
else
    # Put fuzzer in current directory
    FUZZER_PATH="."
fi

# Build fuzzers using compile_native_go_fuzzer
compile_native_go_fuzzer $FUZZER_PATH FuzzHTTPInterface fuzz_ipp_usb_http
compile_native_go_fuzzer $FUZZER_PATH FuzzIPPMessage fuzz_ipp_usb_message
compile_native_go_fuzzer $FUZZER_PATH FuzzUSBDescriptor fuzz_ipp_usb_descriptor

echo "ipp-usb fuzzers built successfully"