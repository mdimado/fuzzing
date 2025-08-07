#!/bin/bash
set -e
echo "Building IPP over USB simulator..."
go build -o ipp-printer ipp_printer.go USBIP.go
echo "Simulator built successfully: ./ipp-printer"