#!/bin/bash -eu

# Change to the goipp source directory
cd $SRC/goipp

# Install go-118-fuzz-build
go install github.com/AdamKorcz/go-118-fuzz-build@latest

cd $SRC/fuzzing/projects/goipp/fuzzer
go mod init goipp-fuzz
go get github.com/OpenPrinting/goipp

# Build the fuzz target
compile_go_fuzzer github.com/mdimado/fuzzing/projects/goipp/fuzzer FuzzDecodeBytes fuzzer_goipp_decodebytes

# Zip the seed corpus (check if it exists)
if [ -d "$SRC/fuzzing/projects/goipp/seeds" ]; then
    zip -j "$OUT/fuzzer_goipp_decodebytes_seed_corpus.zip" "$SRC/fuzzing/projects/goipp/seeds/"* || echo "No seeds found"
fi
