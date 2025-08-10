#!/bin/bash -eu

set -x

# Create a Go module in ipp-usb for the fuzzer
cd $SRC/ipp-usb

# Initialize go.mod if it doesn't exist or add necessary dependencies
if ! grep -q "github.com/OpenPrinting/go-mfp" go.mod 2>/dev/null; then
    # Add go-mfp as a local dependency
    go mod edit -replace=github.com/OpenPrinting/go-mfp=$SRC/go-mfp
fi

# Copy fuzzer source files
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/*.go $SRC/ipp-usb/
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/setup_env.sh $SRC/

# Generate seed corpus if generation script exists
if [ -f "$SRC/ipp-usb/seed_generation.go" ]; then
    cd $SRC/ipp-usb
    go run seed_generation.go
fi

# Make setup script executable
chmod +x $SRC/setup_env.sh

# Build go-mfp proxy (still useful for reference/backup)
cd $SRC/go-mfp
export CC=$SRC/go-mfp/build/bin/clang
export CXX=$SRC/go-mfp/build/bin/clang++
export CFLAGS="$CFLAGS -fsanitize=fuzzer-no-link"
export CXXFLAGS="$CXXFLAGS -fsanitize=fuzzer-no-link"
make

# Build ipp-usb binary for the fuzzer to use
cd $SRC/ipp-usb
export CGO_ENABLED=1

# Ensure go-mfp dependencies are available
go mod tidy || true
go mod download || true

# Build standalone ipp-usb binary
go build -o ipp-usb .

# Compile the USBIP data injection fuzzer
compile_go_fuzzer . FuzzUSBIPData fuzz_usbip_data

# Copy seed corpus
cp -r $SRC/fuzzing/projects/ipp-usb/seeds/* $OUT/

# Copy the setup script, binaries to output
cp $SRC/setup_env.sh $OUT/
cp $SRC/go-mfp/cmd/mfp-proxy/mfp-proxy $OUT/ || true
cp $SRC/ipp-usb/ipp-usb $OUT/