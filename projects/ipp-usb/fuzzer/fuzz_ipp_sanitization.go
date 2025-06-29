package usb

import (
	"bytes"
	"io"
	"net/http"
	"testing"
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

		transport := &UsbTransport{
			log: NewLogger(),
		}
		transport.log.ToNowhere()

		// Testing the sanitization function
		transport.sanitizeIppResponse(1, resp)
	})
}
