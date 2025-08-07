#!/bin/bash -eu

# oss_fuzz_build.sh for ipp-usb

set -e

echo "Building ipp-usb fuzzer..."

# Build ipp-usb from source
cd "${SRC}/ipp-usb"
go build -buildmode=pie -o "${OUT}/ipp-usb" ./cmd/ipp-usb

# Build the IPP over USB simulator
cd "${SRC}/fuzzing/projects/ipp-usb/simulator"
go build -buildmode=pie -o "${OUT}/ipp-printer" ipp_printer.go USBIP.go

# Build AFL++ harness for black-box fuzzing
cd "${SRC}/fuzzing/projects/ipp-usb/fuzzer"

# Use AFL++ compiler for the harness
export CC=afl-clang-fast
export CXX=afl-clang-fast++

# Build the harness with AFL++ instrumentation
$CC $CFLAGS -fsanitize=address -fsanitize-coverage=trace-pc-guard \
    -o "${OUT}/ipp_usb_harness" ipp_usb_harness.c

# Also create a libFuzzer version as fallback
$CXX $CXXFLAGS -std=c++11 \
    -o "${OUT}/ipp_usb_libfuzzer" ipp_usb_harness.c $LIB_FUZZING_ENGINE || true

# Copy scripts and make them executable
cp fuzz_ipp_usb.sh "${OUT}/"
cp setup_environment.sh "${OUT}/"
cp cleanup.sh "${OUT}/"
chmod +x "${OUT}"/fuzz_ipp_usb.sh
chmod +x "${OUT}"/setup_environment.sh
chmod +x "${OUT}"/cleanup.sh

# Set environment variable for scripts to find each other
echo "export FUZZER_DIR=\"${OUT}\"" >> "${OUT}/fuzz_env.sh"
echo "export IPP_USB_BIN=\"${OUT}/ipp-usb\"" >> "${OUT}/fuzz_env.sh"
echo "export SIMULATOR_BIN=\"${OUT}/ipp-printer\"" >> "${OUT}/fuzz_env.sh"

# Copy seed corpus
if [ -d "${SRC}/fuzzing/projects/ipp-usb/seeds" ]; then
    cp -r "${SRC}/fuzzing/projects/ipp-usb/seeds"/* "${OUT}/" || true
fi

# Create a simple runner script for OSS-Fuzz
cat > "${OUT}/run_fuzzer.sh" << 'EOF'
#!/bin/bash
source "${OUT}/fuzz_env.sh"
export AFL_SKIP_CPUFREQ=1
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1

# Setup environment
"${OUT}/setup_environment.sh"

# Run AFL++ fuzzer
afl-fuzz -i "${OUT}/ipp_usb_seed_corpus" \
         -o findings \
         -t 10000 \
         -- "${OUT}/ipp_usb_harness"
EOF

chmod +x "${OUT}/run_fuzzer.sh"

echo "ipp-usb fuzzer build complete!"