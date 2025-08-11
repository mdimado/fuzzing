#!/bin/bash -eu

mkdir -p $SRC/ipp-usb/fuzzer
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_usb_layer.go $SRC/ipp-usb/fuzzer/
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_http_client.go $SRC/ipp-usb/fuzzer/

# Create seed corpus archives
# USB/IPP binary seeds
mkdir -p $WORK/usb_ipp_seed_corpus
if [ -d "$SRC/fuzzing/projects/ipp-usb/seeds" ]; then
    find $SRC/fuzzing/projects/ipp-usb/seeds -name "*.bin" -exec cp {} $WORK/usb_ipp_seed_corpus/ \;
fi
cd $WORK
if [ "$(ls -A usb_ipp_seed_corpus)" ]; then
    zip -r $OUT/fuzz_usb_layer_seed_corpus.zip usb_ipp_seed_corpus/
fi

# HTTP seeds  
mkdir -p $WORK/http_seed_corpus
if [ -d "$SRC/fuzzing/projects/ipp-usb/seeds" ]; then
    find $SRC/fuzzing/projects/ipp-usb/seeds -name "*.txt" -exec cp {} $WORK/http_seed_corpus/ \;
fi
if [ "$(ls -A http_seed_corpus)" ]; then
    zip -r $OUT/fuzz_http_client_seed_corpus.zip http_seed_corpus/
fi

# build dependencies and fuzzers
cd $SRC/ipp-usb
go mod tidy
go install github.com/AdamKorcz/go-118-fuzz-build@latest
go get github.com/AdamKorcz/go-118-fuzz-build/testing

compile_native_go_fuzzer ./fuzzer FuzzUSBLayer fuzz_usb_layer
compile_native_go_fuzzer ./fuzzer FuzzHTTPClient fuzz_http_client