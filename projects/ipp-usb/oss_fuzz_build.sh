#!/bin/bash -eu

apt-get update && apt-get install -y \
    libusb-1.0-0-dev \
    libavahi-client-dev \
    libavahi-common-dev \
    pkg-config

cd $SRC/ipp-usb
make clean
export CGO_ENABLED=1
export CGO_LDFLAGS="-static"
go build -ldflags "-extldflags '-static'" -o $OUT/ipp-usb

cd $SRC/go-mfp
export CC=$SRC/go-mfp/build/bin/clang
export CXX=$SRC/go-mfp/build/bin/clang++
export CFLAGS="$CFLAGS -fsanitize=fuzzer-no-link"
export CXXFLAGS="$CXXFLAGS -fsanitize=fuzzer-no-link"
make
cp mfp-proxy $OUT/

cd $SRC/fuzzing/projects/ipp-usb/fuzzer
compile_go_fuzzer . Fuzz fuzz_ipp_usb_http

cp -r $SRC/fuzzing/projects/ipp-usb/seeds/* $OUT/
