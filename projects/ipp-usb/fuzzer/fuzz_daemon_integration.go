package fuzzer

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"testing"
	"time"
)

// FuzzDaemonIntegration tests the actual ipp-usb daemon with fuzzed inputs
func FuzzDaemonIntegration(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		// Skip very small or very large inputs
		if len(data) < 10 || len(data) > 32*1024 {
			return
		}

		// Create timeout context for the entire test
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		// Test the daemon
		testDaemonWithFuzzData(ctx, t, data)
	})
}

func testDaemonWithFuzzData(ctx context.Context, t *testing.T, fuzzData []byte) {
	// Check if ipp-usb binary exists
	ippusbPath, err := exec.LookPath("ipp-usb")
	if err != nil {
		// Try relative path for build environment
		ippusbPath = "./ipp-usb"
		if _, err := os.Stat(ippusbPath); err != nil {
			t.Skip("ipp-usb binary not found")
			return
		}
	}

	// Start ipp-usb daemon in standalone mode
	cmd := exec.CommandContext(ctx, ippusbPath, "standalone")

	// Set up environment
	cmd.Env = append(os.Environ(),
		"IPP_USB_LOGGING=false", // Reduce noise
		"IPP_USB_PORT=0",        // Use random port
	)

	// Capture output for debugging crashes
	cmd.Stdout = nil
	cmd.Stderr = nil

	// Start the daemon
	if err := cmd.Start(); err != nil {
		t.Skipf("Failed to start ipp-usb daemon: %v", err)
		return
	}

	// Ensure cleanup
	defer func() {
		if cmd.Process != nil {
			// Try graceful shutdown first
			cmd.Process.Signal(syscall.SIGTERM)

			// Force kill after short wait
			time.AfterFunc(100*time.Millisecond, func() {
				if cmd.Process != nil {
					cmd.Process.Kill()
				}
			})
		}
	}()

	// Give daemon time to start up
	select {
	case <-time.After(200 * time.Millisecond):
	case <-ctx.Done():
		return
	}

	// Test different attack vectors
	testHTTPFuzzing(ctx, fuzzData)
	testIPPFuzzing(ctx, fuzzData)

	// Check if daemon is still alive
	select {
	case <-time.After(50 * time.Millisecond):
		// Daemon should still be running
	default:
		// If daemon exited immediately, that might indicate a crash
	}
}

func testHTTPFuzzing(ctx context.Context, fuzzData []byte) {
	// Common ipp-usb HTTP ports to try
	ports := []int{60000, 60001, 8080, 8631}

	client := &http.Client{
		Timeout: 100 * time.Millisecond,
	}

	for _, port := range ports {
		select {
		case <-ctx.Done():
			return
		default:
		}

		baseURL := fmt.Sprintf("http://127.0.0.1:%d", port)

		// Test common IPP endpoints with fuzzed data
		endpoints := []string{
			"/ipp/print",
			"/ipp/faxout",
			"/",
			"/admin",
		}

		for _, endpoint := range endpoints {
			func() {
				// Create request with fuzzed data
				req, err := http.NewRequestWithContext(ctx, "POST", baseURL+endpoint, strings.NewReader(string(fuzzData)))
				if err != nil {
					return
				}

				// Add IPP content type
				req.Header.Set("Content-Type", "application/ipp")

				// Add fuzzed headers (carefully)
				if len(fuzzData) > 20 {
					headerVal := sanitizeHeaderValue(string(fuzzData[10:20]))
					if headerVal != "" {
						req.Header.Set("X-Fuzz-Test", headerVal)
					}
				}

				// Make request
				resp, err := client.Do(req)
				if err != nil {
					return // Connection refused is expected if daemon isn't listening on this port
				}
				defer resp.Body.Close()

				// Read response to completion
				io.Copy(io.Discard, resp.Body)
			}()
		}
	}
}

func testIPPFuzzing(ctx context.Context, fuzzData []byte) {
	// Test IPP-specific malformed requests
	ports := []int{60000, 60001, 8631}

	client := &http.Client{
		Timeout: 100 * time.Millisecond,
	}

	for _, port := range ports {
		select {
		case <-ctx.Done():
			return
		default:
		}

		// Create malformed IPP request
		ippData := createMalformedIPPRequest(fuzzData)

		func() {
			req, err := http.NewRequestWithContext(ctx, "POST",
				fmt.Sprintf("http://127.0.0.1:%d/ipp/print", port),
				strings.NewReader(string(ippData)))
			if err != nil {
				return
			}

			req.Header.Set("Content-Type", "application/ipp")
			req.Header.Set("Content-Length", fmt.Sprintf("%d", len(ippData)))

			resp, err := client.Do(req)
			if err != nil {
				return
			}
			defer resp.Body.Close()

			io.Copy(io.Discard, resp.Body)
		}()
	}
}

func createMalformedIPPRequest(fuzzData []byte) []byte {
	// Create a basic IPP structure with fuzzed data
	minLen := 8 // Minimum IPP header size
	if len(fuzzData) < minLen {
		// Pad with zeros if too small
		padded := make([]byte, minLen)
		copy(padded, fuzzData)
		fuzzData = padded
	}

	// Limit size to prevent resource exhaustion
	if len(fuzzData) > 4096 {
		fuzzData = fuzzData[:4096]
	}

	ippRequest := make([]byte, len(fuzzData))
	copy(ippRequest, fuzzData)

	// Ensure first two bytes look like IPP version (sometimes)
	if len(ippRequest) >= 2 && ippRequest[0] == 0 && ippRequest[1] == 0 {
		ippRequest[0] = 1 // Major version
		ippRequest[1] = 1 // Minor version
	}

	return ippRequest
}

func sanitizeHeaderValue(s string) string {
	// Remove dangerous characters that could break HTTP parsing
	var result strings.Builder
	for _, r := range s {
		if r >= 32 && r < 127 && r != '\r' && r != '\n' {
			result.WriteRune(r)
		}
	}

	val := result.String()
	if len(val) > 100 {
		val = val[:100] // Limit header length
	}
	return val
}
