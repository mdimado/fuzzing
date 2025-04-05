package goipp

import (
	"testing"

	"github.com/OpenPrinting/goipp"
)

func FuzzDecodeBytes(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		var m goipp.Message
		if err := m.DecodeBytes(data); err != nil {
			t.Skip()
		}
	})
}
