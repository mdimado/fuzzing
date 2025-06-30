#!/bin/bash -eu

# Copy fuzzer files
mkdir -p $SRC/ipp-usb/fuzzer
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_ipp_sanitization.go $SRC/ipp-usb/fuzzer/
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/libusb_link.go $SRC/ipp-usb/fuzzer/

# Prepare seed corpus
mkdir -p $WORK/ipp_sanitization_seed_corpus
cp $SRC/fuzzing/projects/ipp-usb/seeds/ipp_sanitization_seed_corpus/* $WORK/ipp_sanitization_seed_corpus/
cd $WORK
zip -r $OUT/FuzzIPPSanitization_seed_corpus.zip ipp_sanitization_seed_corpus/

# Build fuzzer manually
cd $SRC/ipp-usb/fuzzer

go mod init fuzzers || true
go mod tidy

export CGO_ENABLED=1
export CGO_CFLAGS="-I/usr/include/libusb-1.0"
export CGO_LDFLAGS="-L/usr/lib/x86_64-linux-gnu -lusb-1.0"

# Build the fuzzer binary manually
go test -c -o fuzz_ipp_sanitization.test -tags fuzz -coverpkg=./... .

# Move to $OUT as required by OSS-Fuzz
cp fuzz_ipp_sanitization.test $OUT/fuzz_ipp_sanitization
