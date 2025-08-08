#!/bin/bash -eu

# oss_fuzz_build.sh for ipp-usb with static linking

set -e

echo "Building ipp-usb fuzzer with static dependencies..."

# Set Go build flags for static linking
export CGO_ENABLED=1
export CGO_CFLAGS="$CFLAGS"
export CGO_LDFLAGS="$CFLAGS"

# Find static libraries
AVAHI_COMMON_STATIC=$(find /usr/lib -name "libavahi-common.a" 2>/dev/null | head -1)
AVAHI_CLIENT_STATIC=$(find /usr/lib -name "libavahi-client.a" 2>/dev/null | head -1)
USB_STATIC=$(find /usr/lib -name "libusb-1.0.a" 2>/dev/null | head -1)

echo "Found static libraries:"
echo "  Avahi Common: $AVAHI_COMMON_STATIC"
echo "  Avahi Client: $AVAHI_CLIENT_STATIC"
echo "  USB: $USB_STATIC"

# Set up pkg-config to prefer static libraries
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG="pkg-config --static"

# Build ipp-usb with static linking
cd "${SRC}/ipp-usb"

# Create a custom build script that forces static linking
cat > build_static.sh << 'EOF'
#!/bin/bash
set -e

# Get pkg-config flags for static linking
AVAHI_CFLAGS=$(pkg-config --cflags --static avahi-client avahi-common 2>/dev/null || echo "")
AVAHI_LIBS=$(pkg-config --libs --static avahi-client avahi-common 2>/dev/null || echo "-lavahi-client -lavahi-common")
USB_CFLAGS=$(pkg-config --cflags --static libusb-1.0 2>/dev/null || echo "")
USB_LIBS=$(pkg-config --libs --static libusb-1.0 2>/dev/null || echo "-lusb-1.0")

# Combine all flags
export CGO_CFLAGS="$CGO_CFLAGS $AVAHI_CFLAGS $USB_CFLAGS"
export CGO_LDFLAGS="$CGO_LDFLAGS $AVAHI_LIBS $USB_LIBS -static-libgcc"

echo "CGO_CFLAGS: $CGO_CFLAGS"
echo "CGO_LDFLAGS: $CGO_LDFLAGS"

# Build with static linking
go build -buildmode=pie -ldflags="-linkmode external -extldflags '-static'" -o "${OUT}/ipp-usb" .
EOF

chmod +x build_static.sh
./build_static.sh

# Build the IPP over USB simulator (this shouldn't need avahi)
cd "${SRC}/fuzzing/projects/ipp-usb/simulator"
go build -buildmode=pie -ldflags="-linkmode external -extldflags '-static'" -o "${OUT}/ipp-printer" ipp_printer.go USBIP.go

# Build LibFuzzer harness with static curl
cd "${SRC}/fuzzing/projects/ipp-usb/fuzzer"

# Get curl static linking flags
CURL_CFLAGS=$(pkg-config --cflags --static libcurl 2>/dev/null || echo "")
CURL_LIBS=$(pkg-config --libs --static libcurl 2>/dev/null || echo "-lcurl -lssl -lcrypto -lz")

echo "Building libfuzzer harness with static linking..."
$CC $CFLAGS $CURL_CFLAGS \
    -o "${OUT}/ipp_usb_libfuzzer" ipp_usb_libfuzzer.c \
    $LIB_FUZZING_ENGINE $CURL_LIBS

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

# Verify static linking
echo "Checking ipp-usb dependencies:"
ldd "${OUT}/ipp-usb" || echo "Static binary (good!)"
echo "Checking libfuzzer harness dependencies:"
ldd "${OUT}/ipp_usb_libfuzzer" || echo "Static binary (good!)"