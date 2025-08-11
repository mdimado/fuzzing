#!/bin/bash -eu

# Build ipp-usb binary first (required for fuzzing)
cd $SRC/ipp-usb
make
cp ipp-usb $OUT/

mkdir -p $SRC/ipp-usb/fuzzer
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_usb_device_side.go $SRC/ipp-usb/fuzzer/
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_http_client_side.go $SRC/ipp-usb/fuzzer/

# Build USB device simulator helper
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/usb_device_simulator.go $SRC/ipp-usb/fuzzer/
cd $SRC/ipp-usb/fuzzer
go build -o $OUT/usb-device-simulator usb_device_simulator.go

# Create seed corpus archives
# USB/IPP binary seeds
mkdir -p $WORK/usb_ipp_seed_corpus
if [ -d "$SRC/fuzzing/projects/ipp-usb/seeds" ]; then
    find $SRC/fuzzing/projects/ipp-usb/seeds -name "*.bin" -exec cp {} $WORK/usb_ipp_seed_corpus/ \;
fi
cd $WORK
if [ "$(ls -A usb_ipp_seed_corpus)" ]; then
    zip -r $OUT/fuzz_usb_device_side_seed_corpus.zip usb_ipp_seed_corpus/
fi

# HTTP seeds  
mkdir -p $WORK/http_seed_corpus
if [ -d "$SRC/fuzzing/projects/ipp-usb/seeds" ]; then
    find $SRC/fuzzing/projects/ipp-usb/seeds -name "*.txt" -exec cp {} $WORK/http_seed_corpus/ \;
fi
if [ "$(ls -A http_seed_corpus)" ]; then
    zip -r $OUT/fuzz_http_client_side_seed_corpus.zip http_seed_corpus/
fi

# build dependencies and fuzzers
cd $SRC/ipp-usb
go mod tidy
go install github.com/AdamKorcz/go-118-fuzz-build@latest
go get github.com/AdamKorcz/go-118-fuzz-build/testing

compile_native_go_fuzzer ./fuzzer FuzzUSBDeviceSide fuzz_usb_device_side
compile_native_go_fuzzer ./fuzzer FuzzHTTPClientSide fuzz_http_client_side