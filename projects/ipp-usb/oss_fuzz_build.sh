#!/bin/bash -eu

mkdir -p $SRC/ipp-usb/fuzzer

cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_ipp_sanitization.go $SRC/ipp-usb/fuzzer/

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
export CGO_LDFLAGS="-lusb-1.0"
export CGO_CFLAGS="-I/usr/include/libusb-1.0"

# Compile fuzzers
compile_native_go_fuzzer ./fuzzer FuzzIPPSanitization fuzz_ipp_sanitization
