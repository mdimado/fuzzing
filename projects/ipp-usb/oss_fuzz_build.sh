#!/bin/bash -eu

# Save the original compilers
export CC_ORIG=$CC
export CXX_ORIG=$CXX

# Clear the environment variables to use default compilers for Go builds
unset CC
unset CXX

# Build the Go components normally
mkdir -p $SRC/ipp-usb/fuzz
cp $SRC/fuzzing/projects/ipp-usb/emulator/*.go $SRC/ipp-usb/fuzz/

cd $SRC/ipp-usb/fuzz
go build -o $OUT/ipp_usb_emulator *.go

cd $SRC/ipp-usb
go build -o $OUT/ipp-usb

# Restore the original compilers for the C++ wrapper
export CC=$CC_ORIG
export CXX=$CXX_ORIG

# Copy the fuzz_target.sh to the output directory, it will be called by the wrapper
cp $SRC/fuzzing/projects/ipp-usb/fuzz_target.sh $OUT/
chmod +x $OUT/fuzz_target.sh

# Compile the C++ wrapper with AFL++ instrumentation
# We'll use the AFL++-specific CXX which is set by the OSS-Fuzz build system.
$CXX $CXXFLAGS -o $OUT/fuzz_target $SRC/fuzzing/projects/ipp-usb/fuzz_wrapper.cc


#copy seeds
cp -r $SRC/fuzzing/projects/ipp-usb/seeds $WORK/ipp_usb_seeds

# Zip the seed corpus 
cd $WORK
zip -r $OUT/fuzz_target_seed_corpus.zip ipp_usb_seeds/