# Fuzzing Harness for ipp-usb

This directory contains fuzzers for the [`ipp-usb`](https://github.com/OpenPrinting/ipp-usb) project.

## Fuzzers

* `FuzzIppAttrsGetStrings`:  
  Fuzzes the logic that extracts string values from IPP attributes using `ippAttrs.getStrings()`. The input is a newline-separated string containing an attribute name and its value.

### TODO:

* After successfully building and running the fuzzers using OSS-Fuzz locally, update this README with step-by-step instructions for local setup and usage.