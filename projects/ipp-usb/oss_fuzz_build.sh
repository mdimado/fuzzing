#!/bin/bash -eu

# OSS-Fuzz build script for ipp-usb
cd $SRC/fuzzing/projects/ipp-usb

echo "Building ipp-usb fuzzers..."

# Build the main HTTP fuzzer
go-fuzz-build -libfuzzer -func FuzzHTTPInterface -o fuzz_ipp_usb_http.a ./fuzzer
$CXX $CXXFLAGS $LIB_FUZZING_ENGINE fuzz_ipp_usb_http.a -o $OUT/fuzz_ipp_usb_http

# Build the IPP message fuzzer
go-fuzz-build -libfuzzer -func FuzzIPPMessage -o fuzz_ipp_usb_message.a ./fuzzer  
$CXX $CXXFLAGS $LIB_FUZZING_ENGINE fuzz_ipp_usb_message.a -o $OUT/fuzz_ipp_usb_message

# Build the USB descriptor fuzzer
go-fuzz-build -libfuzzer -func FuzzUSBDescriptor -o fuzz_ipp_usb_descriptor.a ./fuzzer
$CXX $CXXFLAGS $LIB_FUZZING_ENGINE fuzz_ipp_usb_descriptor.a -o $OUT/fuzz_ipp_usb_descriptor

# Copy seed corpora
echo "Copying seed corpora..."
cp -r seeds/fuzz_ipp_usb_http_seed_corpus $OUT/
cp -r seeds/fuzz_ipp_usb_message_seed_corpus $OUT/
cp -r seeds/fuzz_ipp_usb_descriptor_seed_corpus $OUT/

# Copy auxiliary files
echo "Copying auxiliary files..."
cp setup_environment.sh $OUT/
cp cleanup.sh $OUT/
chmod +x $OUT/setup_environment.sh $OUT/cleanup.sh

echo "ipp-usb fuzzers built successfully"