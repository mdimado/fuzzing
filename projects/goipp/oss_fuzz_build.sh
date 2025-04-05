#!/bin/bash -eu

# Build script for OSS-Fuzz to build goipp fuzzer

# Copy the fuzzer code into the goipp project
mkdir -p $SRC/goipp/fuzzer/
cp $SRC/fuzzing/projects/goipp/fuzzer/fuzz_decode_bytes.go $SRC/goipp/fuzzer/

# Copy seeds into the project
mkdir -p $SRC/goipp/seeds/
cp $SRC/fuzzing/projects/goipp/seeds/* $SRC/goipp/seeds/

# Navigate to project directory
cd $SRC/goipp

# Create seed corpus archive
zip -j $OUT/fuzz_decode_bytes_seed_corpus.zip seeds/*

# Compile the fuzzer using Go-fuzz
compile_go_fuzzer github.com/OpenPrinting/goipp/fuzzer FuzzDecodeBytes fuzz_decode_bytes
