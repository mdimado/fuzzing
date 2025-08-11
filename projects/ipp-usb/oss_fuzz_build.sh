#!/bin/bash -eu

PROJECT_NAME="$1"

if [[ "$PROJECT_NAME" != "ipp-usb" ]]; then
    echo "Error: This script is for ipp-usb project only"
    exit 1
fi

echo "Building $PROJECT_NAME fuzzers"

# Create a combined fuzzer directory that will work with OSS-Fuzz
mkdir -p $OUT/fuzzer_workspace
cd $OUT/fuzzer_workspace

# Create a minimal Go module for our fuzzers
cat > go.mod << 'EOF'
module ipp-usb-fuzzer

go 1.18

require (
	github.com/OpenPrinting/ipp-usb v0.0.0-20241201000000-000000000000
	github.com/OpenPrinting/go-mfp v0.0.0-20241201000000-000000000000
)

replace github.com/OpenPrinting/ipp-usb => ../../ipp-usb
replace github.com/OpenPrinting/go-mfp => ../../go-mfp
EOF

# Copy fuzzer files
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_usb_layer.go .
cp $SRC/fuzzing/projects/ipp-usb/fuzzer/fuzz_http_client.go .

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

# Return to fuzzer workspace
cd $OUT/fuzzer_workspace

# Initialize go module
go mod tidy || echo "Warning: go mod tidy failed, continuing..."

# Install required dependencies for native Go 1.18 fuzzing
export CGO_ENABLED=1
export GO111MODULE=on

# Build USB layer fuzzer (primary approach)
echo "Building ipp-usb USB layer fuzzer"
if ! compile_native_go_fuzzer . FuzzUSBLayer fuzz_usb_layer; then
    echo "Warning: USB layer fuzzer build failed"
fi

# Build HTTP client fuzzer (complementary approach) 
echo "Building ipp-usb HTTP client fuzzer"
if ! compile_native_go_fuzzer . FuzzHTTPClient fuzz_http_client; then
    echo "Warning: HTTP client fuzzer build failed"
fi

echo "Fuzzers built successfully"
