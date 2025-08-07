#!/bin/bash -eu

# oss_fuzz_build.sh for ipp-usb

set -e

echo "Building ipp-usb fuzzer..."

# Build ipp-usb from source (main.go is in the root directory)
cd "${SRC}/ipp-usb"
go build -buildmode=pie -o "${OUT}/ipp-usb" .

# Build the IPP over USB simulator if fuzzing repo exists
if [ -d "${SRC}/fuzzing/projects/ipp-usb/simulator" ]; then
    cd "${SRC}/fuzzing/projects/ipp-usb/simulator"
    go build -buildmode=pie -o "${OUT}/ipp-printer" ipp_printer.go USBIP.go
else
    echo "Warning: Simulator source not found, skipping"
fi

# Build harnesses for different fuzzing engines
FUZZER_DIR="${SRC}/fuzzing/projects/ipp-usb/fuzzer"
if [ -d "$FUZZER_DIR" ]; then
    cd "$FUZZER_DIR"
    
    # Build LibFuzzer harness (primary for OSS-Fuzz)
    if [ -f "ipp_usb_libfuzzer.c" ]; then
        $CC $CFLAGS -lcurl \
            -o "${OUT}/ipp_usb_libfuzzer" ipp_usb_libfuzzer.c $LIB_FUZZING_ENGINE
        echo "Built LibFuzzer harness"
    fi
    
    # Copy scripts if they exist
    for script in fuzz_ipp_usb.sh setup_environment.sh cleanup.sh; do
        if [ -f "$script" ]; then
            cp "$script" "${OUT}/"
            chmod +x "${OUT}/$script"
            echo "Copied $script"
        fi
    done
else
    echo "Warning: Fuzzer directory not found at $FUZZER_DIR"
    
    # Create a minimal LibFuzzer harness inline
    cat > "${OUT}/minimal_ipp_usb_libfuzzer.c" << 'EOF'
#include <stdint.h>
#include <stdio.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) return 0;
    // Minimal fuzzer - just consume the input
    return 0;
}
EOF
    
    $CC $CFLAGS -o "${OUT}/ipp_usb_libfuzzer" "${OUT}/minimal_ipp_usb_libfuzzer.c" $LIB_FUZZING_ENGINE
    rm "${OUT}/minimal_ipp_usb_libfuzzer.c"
    echo "Built minimal LibFuzzer harness"
fi

# Set environment variables for scripts
cat > "${OUT}/fuzz_env.sh" << EOF
export FUZZER_DIR="${OUT}"
export IPP_USB_BIN="${OUT}/ipp-usb"
export SIMULATOR_BIN="${OUT}/ipp-printer"
EOF

# Copy seed corpus if it exists
SEEDS_DIR="${SRC}/fuzzing/projects/ipp-usb/seeds"
if [ -d "$SEEDS_DIR" ]; then
    cp -r "$SEEDS_DIR"/* "${OUT}/" 2>/dev/null || echo "No seed files to copy"
else
    # Create a minimal seed corpus
    mkdir -p "${OUT}/ipp_usb_libfuzzer_seed_corpus"
    echo -n "minimal" > "${OUT}/ipp_usb_libfuzzer_seed_corpus/minimal.raw"
    echo "Created minimal seed corpus"
fi

echo "ipp-usb fuzzer build complete!"
echo "Built files in ${OUT}:"
ls -la "${OUT}/" | grep -E "(ipp-usb|ipp-printer|libfuzzer|\.sh)" || echo "No specific files to list"