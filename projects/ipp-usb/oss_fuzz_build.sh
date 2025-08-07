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

# Build harnesses
cd "${SRC}/fuzzing/projects/ipp-usb/fuzzer"

echo "Building libFuzzer harness..."
# Build libFuzzer version (OSS-Fuzz standard)
$CXX $CXXFLAGS $LIB_FUZZING_ENGINE \
    -o "${OUT}/ipp_usb_libfuzzer" ipp_usb_harness_libfuzzer.c

echo "Building AFL++ harness..."
# Build AFL++ version (without libFuzzer flags)
# Remove fuzzer-specific flags and add AFL++ instrumentation
CLEAN_CFLAGS=$(echo "$CFLAGS" | sed 's/-fsanitize=fuzzer[^ ]*//g' | sed 's/-fsanitize-coverage=trace-pc-guard//g')
clang $CLEAN_CFLAGS -fsanitize=address -fsanitize-coverage=trace-pc-guard \
    -o "${OUT}/ipp_usb_afl" ipp_usb_harness_afl.c

# Copy scripts and make them executable
cp fuzz_ipp_usb.sh "${OUT}/"
cp setup_environment.sh "${OUT}/"
cp cleanup.sh "${OUT}/"
chmod +x "${OUT}"/fuzz_ipp_usb.sh
chmod +x "${OUT}"/setup_environment.sh
chmod +x "${OUT}"/cleanup.sh

# Set environment variable for scripts to find each other
echo "export FUZZER_DIR=\"${OUT}\"" > "${OUT}/fuzz_env.sh"
echo "export IPP_USB_BIN=\"${OUT}/ipp-usb\"" >> "${OUT}/fuzz_env.sh"
echo "export SIMULATOR_BIN=\"${OUT}/ipp-printer\"" >> "${OUT}/fuzz_env.sh"

# Copy seed corpus
mkdir -p "${OUT}/ipp_usb_seed_corpus"
if [ -d "${SRC}/fuzzing/projects/ipp-usb/seeds" ]; then
    cp -r "${SRC}/fuzzing/projects/ipp-usb/seeds"/* "${OUT}/ipp_usb_seed_corpus/" || true
fi

# Create OSS-Fuzz compatible runner (uses libFuzzer by default)
cat > "${OUT}/run_fuzzer.sh" << 'EOF'
#!/bin/bash
source "${OUT}/fuzz_env.sh"

# Setup environment
"${OUT}/setup_environment.sh"

# Run libFuzzer (OSS-Fuzz standard)
"${OUT}/ipp_usb_libfuzzer" "${OUT}/ipp_usb_seed_corpus" -max_total_time=3600
EOF

chmod +x "${OUT}/run_fuzzer.sh"

# Create AFL++ runner script as alternative
cat > "${OUT}/run_afl.sh" << 'EOF'
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
         -- "${OUT}/ipp_usb_afl"
EOF

chmod +x "${OUT}/run_afl.sh"

echo "ipp-usb fuzzer build complete!"
echo "Built both libFuzzer (${OUT}/ipp_usb_libfuzzer) and AFL++ (${OUT}/ipp_usb_afl) versions"