package fuzz

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/OpenPrinting/ipp-usb/usb"
)

func FuzzConfLoadInternal(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		if len(data) == 0 {
			t.Skip()
		}

		tmpDir, err := os.MkdirTemp("", "ipp-usb-fuzz")
		if err != nil {
			t.Skip()
		}
		defer os.RemoveAll(tmpDir)

		confFile := filepath.Join(tmpDir, "ipp-usb.conf")
		err = os.WriteFile(confFile, data, 0644)
		if err != nil {
			t.Skip()
		}

		// Backup and reset config
		origConf := usb.ExportedConf
		defer func() { usb.ExportedConf = origConf }()
		usb.ExportedConf = usb.Configuration{
			HTTPMinPort:        60000,
			HTTPMaxPort:        65535,
			DNSSdEnable:        true,
			LoopbackOnly:       true,
			IPV6Enable:         true,
			ConfAuthUID:        nil,
			LogDevice:          usb.ExportedLogDebug,
			LogMain:            usb.ExportedLogDebug,
			LogConsole:         usb.ExportedLogDebug,
			LogMaxFileSize:     256 * 1024,
			LogMaxBackupFiles:  5,
			LogAllPrinterAttrs: false,
			ColorConsole:       true,
		}

		defer func() {
			if r := recover(); r != nil {
				t.Errorf("panic: %v", r)
			}
		}()

		_ = usb.ExportedConfLoadInternal(confFile)
	})
}
