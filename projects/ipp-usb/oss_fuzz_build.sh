#!/bin/bash -eu

# OSS-Fuzz build script for ipp-usb  
cd $SRC/ipp-usb

echo "Building ipp-usb fuzzers..."

# Use readonly mode to respect existing vendor directory
export GOFLAGS="-mod=readonly"

# Build fuzzers using compile_native_go_fuzzer
compile_native_go_fuzzer ./fuzzer FuzzHTTPInterface fuzz_ipp_usb_http
compile_native_go_fuzzer ./fuzzer FuzzIPPMessage fuzz_ipp_usb_message
compile_native_go_fuzzer ./fuzzer FuzzUSBDescriptor fuzz_ipp_usb_descriptor

echo "ipp-usb fuzzers built successfully"