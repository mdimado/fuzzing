//go:build cgo
// +build cgo

package fuzzer

/*
#cgo LDFLAGS: -lusb-1.0
*/
import "C"
