#!/bin/bash -eu

# Copy emulator and fuzz target
mkdir -p $SRC/ipp-usb/fuzz
cp $SRC/fuzzing/projects/ipp-usb/emulator/*.go $SRC/ipp-usb/fuzz/
cp $SRC/fuzzing/projects/ipp-usb/fuzz_target.sh $SRC/ipp-usb/fuzz/

# Build emulator binary (assumes you have a main package in emulator/)
cd $SRC/ipp-usb/fuzz
go build -o $OUT/ipp_usb_emulator emulator.go ipp_printer.go

# Build ipp-usb (native Go binary)
cd $SRC/ipp-usb
go build -o $OUT/ipp-usb

# Copy and compile the fuzz target script
chmod +x $SRC/ipp-usb/fuzz/fuzz_target.sh
cp $SRC/ipp-usb/fuzz/fuzz_target.sh $OUT/fuzz_target

# Set executable for OSS-Fuzz
chmod +x $OUT/fuzz_target
