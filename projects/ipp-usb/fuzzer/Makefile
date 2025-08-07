# Makefile for ipp-usb fuzzing

CC ?= afl-clang-fast
CFLAGS ?= -O2 -g
LDFLAGS ?=

# AFL++ specific flags
AFL_CFLAGS = -fsanitize=address -fsanitize-coverage=trace-pc-guard

.PHONY: all clean ipp_usb_harness

all: ipp_usb_harness

ipp_usb_harness: ipp_usb_harness.c
	$(CC) $(CFLAGS) $(AFL_CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f ipp_usb_harness
	rm -f /tmp/fuzz_input_*