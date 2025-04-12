#!/bin/bash -eu

#copy fuzzer code to goipp directory
mkdir -p $SRC/goipp/fuzzer
cp $SRC/fuzzing/projects/goipp/fuzzer/fuzz_decode_bytes.go $SRC/goipp/fuzzer/

#prepare corpus directory
mkdir -p $WORK/corpus
cp $SRC/fuzzing/projects/goipp/seeds/* $WORK/corpus/

#compress corpus into zip file
cd $WORK
zip -r $OUT/fuzz_decode_bytes_seed_corpus.zip corpus/

cd $SRC/goipp
go mod tidy

go install github.com/AdamKorcz/go-118-fuzz-build@latest
go get github.com/AdamKorcz/go-118-fuzz-build/testing

#build fuzz target 
compile_native_go_fuzzer github.com/OpenPrinting/goipp/fuzzer FuzzDecodeBytes fuzz_decode_bytes


