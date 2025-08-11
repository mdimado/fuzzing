#!/bin/bash -eu

# Clone and build go-mfp (provides mfp-proxy and USB/IP endpoints)
# git clone https://github.com/OpenPrinting/go-mfp.git $SRC/go-mfp
cd $SRC/go-mfp
go build -o $OUT/mfp-proxy ./cmd/mfp-proxy

# Build ipp-usb binary (required for fuzzing)
cd $SRC/ipp-usb
make clean
# Add pkg-config flags to link Avahi libraries statically if possible
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
make LDFLAGS="-static-libgcc -L/usr/lib/x86_64-linux-gnu" CFLAGS="-O2"
cp ipp-usb $OUT/

# Create a wrapper script that sets LD_LIBRARY_PATH
cat > $OUT/ipp-usb-wrapper << 'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
exec /out/ipp-usb "$@"
EOF
chmod +x $OUT/ipp-usb-wrapper

mkdir -p $SRC/ipp-usb/fuzzer
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_usb_device.go $SRC/ipp-usb/fuzzer/
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_http_client.go $SRC/ipp-usb/fuzzer/

# Create seed corpus archives
# USB/IPP binary seeds
mkdir -p $WORK/usb_ipp_seed_corpus
if [ -d "$SRC/fuzzing/projects/ipp-usb/seeds" ]; then
    find $SRC/fuzzing/projects/ipp-usb/seeds -name "*.bin" -exec cp {} $WORK/usb_ipp_seed_corpus/ \;
fi
cd $WORK
if [ "$(ls -A usb_ipp_seed_corpus)" ]; then
    zip -r $OUT/fuzz_usb_device_side_seed_corpus.zip usb_ipp_seed_corpus/
fi

# HTTP seeds  
mkdir -p $WORK/http_seed_corpus
if [ -d "$SRC/fuzzing/projects/ipp-usb/seeds" ]; then
    find $SRC/fuzzing/projects/ipp-usb/seeds -name "*.txt" -exec cp {} $WORK/http_seed_corpus/ \;
fi
if [ "$(ls -A http_seed_corpus)" ]; then
    zip -r $OUT/fuzz_http_client_side_seed_corpus.zip http_seed_corpus/
fi

# build dependencies and fuzzers
cd $SRC/ipp-usb
go mod tidy
go install github.com/AdamKorcz/go-118-fuzz-build@latest
go get github.com/AdamKorcz/go-118-fuzz-build/testing

compile_native_go_fuzzer ./fuzzer FuzzUSBDeviceSide fuzz_usb_device_side
compile_native_go_fuzzer ./fuzzer FuzzHTTPClientSide fuzz_http_client_side