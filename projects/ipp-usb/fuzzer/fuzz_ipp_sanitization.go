package fuzzer

import (
	"bytes"
	"io"
	"net/http"
	"testing"

	usb "github.com/mdimado/ipp-usb-fuzzing"
)

func FuzzIPPSanitization(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		// mock HTTP response with IPP content
		resp := &http.Response{
			Header:        make(http.Header),
			Body:          io.NopCloser(bytes.NewReader(data)),
			ContentLength: int64(len(data)),
		}
		resp.Header.Set("Content-Type", "application/ipp")

		transport := usb.NewUsbTransportForTesting()
		transport.Log().ToNowhere()

		// Testing the sanitization function
		transport.SanitizeIppResponse(1, resp)
	})
}
