#!/bin/bash -eu

# Copy the fuzzer code to the goipp package directory
mkdir -p $SRC/goipp/fuzzer
cp $SRC/fuzzing/projects/goipp/fuzzer/fuzz_decode_bytes.go $SRC/goipp/fuzzer/

# Prepare corpus directory
mkdir -p $WORK/corpus
cp $SRC/fuzzing/projects/goipp/seeds/* $WORK/corpus/

# Compress corpus into a zip file
cd $WORK
zip -r $OUT/fuzz_decode_bytes_seed_corpus.zip corpus/

# Build the fuzzer with Go114 fuzzing engine
cd $SRC/goipp
go mod tidy

# Build the fuzz target 
compile_go_fuzzer github.com/OpenPrinting/goipp/fuzzer FuzzDecodeBytes fuzz_decode_bytes


