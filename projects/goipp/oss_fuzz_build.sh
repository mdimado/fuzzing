#!/bin/bash -eu

# Navigate to the base goipp directory
cd $SRC/goipp

# Copy the fuzzer code from your fuzzing repo to the target directory
mkdir -p $SRC/goipp/fuzzer/
cp $SRC/fuzzing/projects/goipp/fuzzer/fuzz_decode_bytes.go $SRC/goipp/fuzzer/

# Copy the seeds
mkdir -p $SRC/goipp/seeds/
cp $SRC/fuzzing/projects/goipp/seeds/* $SRC/goipp/seeds/ || echo "No seeds found, continuing anyway"

# Create the seed corpus archive
zip -j $OUT/fuzz_decode_bytes_seed_corpus.zip $SRC/fuzzing/projects/goipp/seeds/* || echo "Could not create seed corpus, continuing build"

# Ensure dependencies are up to date
go mod tidy

# Compile the fuzzer using the existing Go fuzzer
compile_go_fuzzer github.com/OpenPrinting/goipp/fuzzer FuzzDecodeBytes fuzz_decode_bytes

