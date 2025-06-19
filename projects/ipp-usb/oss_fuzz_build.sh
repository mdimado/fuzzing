#!/bin/bash -eu

# Copy fuzzers into the source directory
mkdir -p $SRC/ipp-usb/fuzzer
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/*.go $SRC/ipp-usb/fuzzer/


# use local ipp-usb instead of remote
cp $SRC/fuzzing/projects/ipp-usb/ipp-usb-local/go.mod $SRC/ipp-usb/go.mod || true
cp $SRC/fuzzing/projects/ipp-usb/ipp-usb-local/go.sum $SRC/ipp-usb/go.sum || true
cd $SRC/ipp-usb
go mod edit -replace=github.com/OpenPrinting/ipp-usb=$SRC/ipp-usb
go mod tidy


# Prepare seed corpus
mkdir -p $WORK/ipp_attrs_seed_corpus
cp $SRC/fuzzing/projects/ipp-usb/seeds/ipp_attrs_seed_corpus/* $WORK/ipp_attrs_seed_corpus/
cd $WORK
zip -r $OUT/fuzz_ipp_attrs_get_strings_seed_corpus.zip ipp_attrs_seed_corpus/

# Build dependencies and compile the fuzzers
cd $SRC/ipp-usb

go install github.com/AdamKorcz/go-118-fuzz-build@latest
go get github.com/AdamKorcz/go-118-fuzz-build/testing

# Compile fuzzers
compile_native_go_fuzzer ./fuzzer FuzzIppAttrsGetStrings fuzz_ipp_attrs_get_strings