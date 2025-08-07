#!/bin/bash -eu

# oss_fuzz_build.sh for ipp-usb

set -e

echo "Building ipp-usb fuzzer..."

# Build ipp-usb from source (main.go is in the root directory)
cd "${SRC}/ipp-usb"
go build -buildmode=pie -o "${OUT}/ipp-usb" .

# Build the IPP over USB simulator
cd "${SRC}/fuzzing/projects/ipp-usb/simulator"
go build -buildmode=pie -o "${OUT}/ipp-printer" ipp_printer.go USBIP.go

# Build harnesses for different fuzzing engines
cd "${SRC}/fuzzing/projects/ipp-usb/fuzzer"

# Build LibFuzzer harness (primary for OSS-Fuzz)
# Use C compiler for .c files, not C++
$CC $CFLAGS -lcurl \
    -o "${OUT}/ipp_usb_libfuzzer" ipp_usb_libfuzzer.c $LIB_FUZZING_ENGINE

# Build AFL++ harness as alternative (optional - ignore errors)
if [ -f "ipp_usb_afl.c" ]; then
    $CC $CFLAGS -lcurl \
        -o "${OUT}/ipp_usb_afl" ipp_usb_afl.c 2>/dev/null || echo "AFL++ harness build skipped"
fi

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