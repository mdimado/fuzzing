#!/bin/bash -eu

# AFL++ is an engine that uses a C/C++ compiler wrapper,
# but our target is a bash script which runs Go binaries.
# We must build the Go binaries normally, without AFL++ instrumentation,
# since the Go toolchain doesn't understand AFL++'s
# linker symbols.

# Save the original compilers
export CC_ORIG=$CC
export CXX_ORIG=$CXX

# Clear the environment variables to use default compilers for Go builds
# You might need to set them to something like 'clang' or 'g++' if
# the default is not available
unset CC
unset CXX

# Build the Go components normally
mkdir -p $SRC/ipp-usb/fuzz
cp $SRC/fuzzing/projects/ipp-usb/emulator/*.go $SRC/ipp-usb/fuzz/
cp $SRC/fuzzing/projects/ipp-usb/fuzz_target.sh $SRC/ipp-usb/fuzz/

cd $SRC/ipp-usb/fuzz
go build -o $OUT/ipp_usb_emulator *.go

cd $SRC/ipp-usb
go build -o $OUT/ipp-usb

# Copy and make the fuzz_target.sh executable
chmod +x $SRC/ipp-usb/fuzz/fuzz_target.sh
cp $SRC/ipp-usb/fuzz/fuzz_target.sh $OUT/fuzz_target
chmod +x $OUT/fuzz_target

# Restore the original compilers for the next steps if any (or just for good practice)
export CC=$CC_ORIG
export CXX=$CXX_ORIG