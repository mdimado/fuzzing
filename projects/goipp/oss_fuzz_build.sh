#!/bin/bash -eu

# Set Go workspace
cd $SRC/goipp

# Copy your fuzz target into the goipp package if it's not already there
# (Optional depending on your setup)
# cp $SRC/openprinting/fuzzing/goipp/fuzz_decode_bytes.go .

# Build the fuzzer
go install github.com/AdamKorcz/go-118-fuzz-build@latest
compile_go_fuzzer github.com/OpenPrinting/goipp FuzzDecodeBytes fuzzer_goipp_decodebytes

# Create the seed corpus zip
zip -j "$OUT/fuzzer_goipp_decodebytes_seed_corpus.zip" "$SRC/openprinting/fuzzing/goipp/seeds/"*
