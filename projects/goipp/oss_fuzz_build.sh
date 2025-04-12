#!/bin/bash -eu
# Inside /src/fuzzing/projects/goipp/oss_fuzz_build.sh

# Copy goipp source into expected Go path
mkdir -p $GOPATH/src/github.com/OpenPrinting/
cp -r $SRC/goipp $GOPATH/src/github.com/OpenPrinting/

# Copy fuzzer into that module
cp $SRC/fuzzing/projects/goipp/fuzz_decode_bytes.go $GOPATH/src/github.com/OpenPrinting/goipp/

# Compile the fuzzer
compile_go_fuzzer github.com/OpenPrinting/goipp FuzzDecodeBytes fuzzer_goipp_decodebytes
