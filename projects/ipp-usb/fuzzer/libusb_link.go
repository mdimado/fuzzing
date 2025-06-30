//go:build cgo
// +build cgo

package fuzzer

/*
#cgo CFLAGS: -I/usr/include/libusb-1.0
#cgo LDFLAGS: -L/usr/lib/x86_64-linux-gnu -lusb-1.0
*/
import "C"
