#!/bin/bash -eu

# oss_fuzz_build.sh for ipp-usb with static linking

set -e

echo "Building ipp-usb fuzzer with static dependencies..."

# Install additional static libraries that might be missing
apt-get update && apt-get install -y libudev-dev || true

# Set Go build flags for static linking
export CGO_ENABLED=1

# Build ipp-usb with mixed static/dynamic linking (safer approach)
cd "${SRC}/ipp-usb"

# Check what static libraries are actually available
echo "Checking available static libraries:"
find /usr/lib -name "libavahi*.a" 2>/dev/null || echo "No avahi static libs"
find /usr/lib -name "libusb*.a" 2>/dev/null || echo "No USB static libs"  
find /usr/lib -name "libudev*.a" 2>/dev/null || echo "No udev static libs"

# Try a more conservative approach - avoid full static linking
# Instead, bundle dependencies that are available as static libraries
export CGO_CFLAGS="$CFLAGS $(pkg-config --cflags libusb-1.0 avahi-client avahi-common 2>/dev/null || echo '-I/usr/include/libusb-1.0')"

# For CGO_LDFLAGS, only use libraries that we know have static versions available
# Avoid udev which doesn't have static libraries in most distributions
CGO_LIBS=""

# Add avahi libraries if static versions exist
if [ -f "/usr/lib/x86_64-linux-gnu/libavahi-common.a" ]; then
    CGO_LIBS="$CGO_LIBS /usr/lib/x86_64-linux-gnu/libavahi-common.a"
else
    CGO_LIBS="$CGO_LIBS -lavahi-common"
fi

if [ -f "/usr/lib/x86_64-linux-gnu/libavahi-client.a" ]; then
    CGO_LIBS="$CGO_LIBS /usr/lib/x86_64-linux-gnu/libavahi-client.a"  
else
    CGO_LIBS="$CGO_LIBS -lavahi-client"
fi

# Add USB library
if [ -f "/usr/lib/x86_64-linux-gnu/libusb-1.0.a" ]; then
    CGO_LIBS="$CGO_LIBS /usr/lib/x86_64-linux-gnu/libusb-1.0.a"
else
    CGO_LIBS="$CGO_LIBS -lusb-1.0"
fi

# Add system libraries that should be dynamically linked
CGO_LIBS="$CGO_LIBS -ludev -pthread -ldbus-1"

export CGO_LDFLAGS="$CFLAGS $CGO_LIBS"

echo "CGO_CFLAGS: $CGO_CFLAGS"
echo "CGO_LDFLAGS: $CGO_LDFLAGS"

# Build without forcing full static linking (this was causing the udev issue)
go build -buildmode=pie -o "${OUT}/ipp-usb" .

# Build the IPP over USB simulator (this shouldn't need avahi)
cd "${SRC}/fuzzing/projects/ipp-usb/simulator"
go build -buildmode=pie -ldflags="-linkmode external -extldflags '-static'" -o "${OUT}/ipp-printer" ipp_printer.go USBIP.go

# Build LibFuzzer harness 
cd "${SRC}/fuzzing/projects/ipp-usb/fuzzer"

echo "Building libfuzzer harness..."
$CC $CFLAGS \
    -o "${OUT}/ipp_usb_libfuzzer" ipp_usb_libfuzzer.c \
    $LIB_FUZZING_ENGINE -lcurl

# Copy scripts and make them executable
cp fuzz_ipp_usb.sh "${OUT}/"
cp setup_environment.sh "${OUT}/"
cp cleanup.sh "${OUT}/"
chmod +x "${OUT}"/fuzz_ipp_usb.sh
chmod +x "${OUT}"/setup_environment.sh
chmod +x "${OUT}"/cleanup.sh

# Create environment setup for container (no sudo needed)
cat > "${OUT}/fuzz_env.sh" << EOF
export FUZZER_DIR="${OUT}"
export IPP_USB_BIN="${OUT}/ipp-usb"
export SIMULATOR_BIN="${OUT}/ipp-printer"
export NO_SUDO=1
EOF

# Copy seed corpus
if [ -d "${SRC}/fuzzing/projects/ipp-usb/seeds" ]; then
    cp -r "${SRC}/fuzzing/projects/ipp-usb/seeds"/* "${OUT}/" 2>/dev/null || true
fi

echo "ipp-usb fuzzer build complete!"

# Verify linking - check dependencies but don't fail if ldd shows dependencies
echo "Checking ipp-usb dependencies:"
ldd "${OUT}/ipp-usb" 2>&1 || echo "ldd check completed"
echo "Checking libfuzzer harness dependencies:" 
ldd "${OUT}/ipp_usb_libfuzzer" 2>&1 || echo "ldd check completed"

# Test if binaries can run
echo "Testing ipp-usb binary:"
"${OUT}/ipp-usb" --help 2>&1 || echo "ipp-usb help test completed"