#!/bin/bash
set -eu

echo "Building ipp-usb for AFL++ fuzzing..."

# Build ipp-usb with sanitizers
cd $SRC/ipp-usb
export CGO_ENABLED=1
export CC="$CC"
export CXX="$CXX" 
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CXXFLAGS"

# Build ipp-usb binary
go build -a -ldflags '-extldflags "-static"' -o $OUT/ipp-usb ./cmd/ipp-usb

# Build the emulator
cd $SRC/fuzzing/projects/ipp-usb/emulator
go build -o $OUT/ipp_usb_emulator .

# Copy the fuzzing wrapper script
cp $SRC/fuzzing/projects/ipp-usb/fuzz_ipp_usb.sh $OUT/
chmod +x $OUT/fuzz_ipp_usb.sh

# Copy testcases for AFL++
cp -r $SRC/fuzzing/projects/ipp-usb/testcases $OUT/

# Create AFL++ wrapper that reads from stdin
cat > $OUT/fuzz_target << 'EOF'
#!/bin/bash
exec $OUT/fuzz_ipp_usb.sh
EOF
chmod +x $OUT/fuzz_target

echo "Build completed successfully"