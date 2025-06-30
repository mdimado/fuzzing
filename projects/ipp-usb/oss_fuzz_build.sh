#!/bin/bash -eu

mkdir -p $SRC/ipp-usb/fuzzer

cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_ipp_sanitization.go $SRC/ipp-usb/fuzzer/
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/libusb_link.go $SRC/ipp-usb/fuzzer/


# Prepare the seed corpus
mkdir -p $WORK/ipp_sanitization_seed_corpus
cp $SRC/fuzzing/projects/ipp-usb/seeds/ipp_sanitization_seed_corpus/* $WORK/ipp_sanitization_seed_corpus/
cd $WORK
zip -r $OUT/FuzzIPPSanitization_seed_corpus.zip ipp_sanitization_seed_corpus/


cd $SRC/ipp-usb
go mod tidy
go install github.com/AdamKorcz/go-118-fuzz-build@latest
go get github.com/AdamKorcz/go-118-fuzz-build/testing

export CGO_ENABLED=1
export CGO_CFLAGS="$(pkg-config --cflags libusb-1.0)"
export CGO_LDFLAGS="$(pkg-config --libs libusb-1.0)"

# Compile fuzzers
cd fuzzer

# Set CGO flags explicitly again here
export CGO_ENABLED=1
export CGO_CFLAGS="-I/usr/include/libusb-1.0"
export CGO_LDFLAGS="-L/usr/lib/x86_64-linux-gnu -lusb-1.0"

# Build binary manually
go test -c -o $OUT/fuzz_ipp_sanitization.test -coverpkg=./... .

# Rename to match OSS-Fuzz expectations
cp $OUT/fuzz_ipp_sanitization.test $OUT/fuzz_ipp_sanitization

