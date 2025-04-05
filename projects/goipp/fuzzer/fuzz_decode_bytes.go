package goipp

import (
	"github.com/OpenPrinting/goipp"
)

func FuzzDecodeBytes(data []byte) int {
	var m goipp.Message
	if err := m.DecodeBytes(data); err != nil {
		return 0
	}
	return 1
}
