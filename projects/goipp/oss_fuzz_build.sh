#!/bin/bash -eu

# Change to the goipp source directory (already cloned in Dockerfile)
cd $SRC/goipp

# Install go-118-fuzz-build if not already present
go install github.com/AdamKorcz/go-118-fuzz-build@latest

# Build the fuzz target (go-fuzz compatible)
compile_go_fuzzer github.com/OpenPrinting/goipp FuzzDecodeBytes fuzzer_goipp_decodebytes

# Zip the seed corpus if it exists
if [ -d "$SRC/fuzzing/projects/goipp/seeds" ]; then
    zip -j "$OUT/fuzzer_goipp_decodebytes_seed_corpus.zip" "$SRC/fuzzing/projects/goipp/seeds/"* || echo "No seeds found"
fi
