package fuzzer

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// FuzzHTTPClientSide tests ipp-usb's tolerance to malformed HTTP client requests
func FuzzHTTPClientSide(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		// Skip very small inputs
		if len(data) < 10 {
			return
		}

		// Limit data size
		if len(data) > 64*1024 {
			data = data[:64*1024]
		}

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		testHTTPClientFuzzing(ctx, t, data)
	})
}

func testHTTPClientFuzzing(ctx context.Context, t *testing.T, fuzzData []byte) {
	// Start a stable USB device simulator (could be mfp-proxy or simple mock)
	deviceSim := startUSBDeviceSimulator(ctx, t)
	if deviceSim == nil {
		return
	}
	defer deviceSim.Process.Kill()

	// Give device time to start
	time.Sleep(100 * time.Millisecond)

	// Start ipp-usb daemon
	ippusbCmd := startIPPUSBForClientTesting(ctx, t)
	if ippusbCmd == nil {
		return
	}
	defer ippusbCmd.Process.Kill()

	// Give ipp-usb time to start and discover devices
	time.Sleep(3 * time.Second)

	// Find ipp-usb HTTP endpoint
	endpoint := findIPPUSBEndpoint(ctx)
	if endpoint == "" {
		t.Skip("Cannot find ipp-usb HTTP endpoint")
		return
	}

	// Send fuzzed HTTP requests
	sendFuzzedHTTPRequests(ctx, t, endpoint, fuzzData)
}

func startUSBDeviceSimulator(ctx context.Context, t *testing.T) *exec.Cmd {
	// Try to start mfp-proxy as a stable device backend
	// This assumes mfp-proxy is available
	cmd := exec.CommandContext(ctx, "mfp-proxy", "-device=virtual-printer")
	err := cmd.Start()
	if err != nil {
		// Fallback: start our own simple device simulator
		return startSimpleDeviceSimulator(ctx, t)
	}
	return cmd
}

func startSimpleDeviceSimulator(ctx context.Context, t *testing.T) *exec.Cmd {
	// Create a simple stable USB device that responds predictably
	// This would need to be implemented as a separate helper program
	// For now, we'll skip if mfp-proxy is not available
	t.Skip("USB device simulator not available")
	return nil
}

func startIPPUSBForClientTesting(ctx context.Context, t *testing.T) *exec.Cmd {
	cmd := exec.CommandContext(ctx, "ipp-usb", "-verbose")
	err := cmd.Start()
	if err != nil {
		t.Skip("Cannot start ipp-usb:", err)
		return nil
	}
	return cmd
}

func findIPPUSBEndpoint(ctx context.Context) string {
	// ipp-usb typically listens on ports 60000+
	client := &http.Client{Timeout: 500 * time.Millisecond}

	for port := 60000; port <= 60010; port++ {
		select {
		case <-ctx.Done():
			return ""
		default:
		}

		url := fmt.Sprintf("http://127.0.0.1:%d", port)

		// Try a simple GET request
		req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		resp.Body.Close()

		// Found a responsive endpoint
		return url
	}

	return ""
}

func sendFuzzedHTTPRequests(ctx context.Context, t *testing.T, endpoint string, fuzzData []byte) {
	client := &http.Client{
		Timeout: 2 * time.Second,
		// Don't follow redirects to catch redirect handling bugs
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}

	// Test various fuzzing scenarios
	testScenarios := []struct {
		name string
		test func(context.Context, *http.Client, string, []byte)
	}{
		{"malformed_ipp_requests", testMalformedIPPRequests},
		{"malformed_headers", testMalformedHeaders},
		{"oversized_requests", testOversizedRequests},
		{"invalid_methods", testInvalidMethods},
		{"malformed_urls", testMalformedURLs},
		{"content_type_attacks", testContentTypeAttacks},
		{"chunked_encoding", testChunkedEncoding},
	}

	for _, scenario := range testScenarios {
		select {
		case <-ctx.Done():
			return
		default:
		}

		func() {
			defer func() {
				if r := recover(); r != nil {
					// Log panic but continue with other tests
					t.Logf("Panic in scenario %s: %v", scenario.name, r)
				}
			}()

			scenario.test(ctx, client, endpoint, fuzzData)
		}()
	}
}

func testMalformedIPPRequests(ctx context.Context, client *http.Client, endpoint string, fuzzData []byte) {
	paths := []string{"/ipp/print", "/ipp/scan", "/"}

	for _, path := range paths {
		select {
		case <-ctx.Done():
			return
		default:
		}

		url := endpoint + path

		// Create IPP request with fuzzed data
		ippHeader := []byte{
			0x02, 0x00, // IPP version
			0x00, 0x0B, // operation (Get-Printer-Attributes)
			0x00, 0x00, 0x00, 0x01, // request-id
		}

		// Combine header with fuzzed data
		requestBody := append(ippHeader, fuzzData...)
		if len(requestBody) > 32*1024 {
			requestBody = requestBody[:32*1024]
		}

		req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(requestBody))
		if err != nil {
			continue
		}

		req.Header.Set("Content-Type", "application/ipp")

		resp, err := client.Do(req)
		if err != nil {
			continue // Expected for some malformed requests
		}

		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
}

func testMalformedHeaders(ctx context.Context, client *http.Client, endpoint string, fuzzData []byte) {
	url := endpoint + "/ipp/print"

	// Basic IPP request body
	basicIPP := []byte{0x02, 0x00, 0x00, 0x0B, 0x00, 0x00, 0x00, 0x01}

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(basicIPP))
	if err != nil {
		return
	}

	// Add fuzzed headers
	if len(fuzzData) > 10 {
		// Create potentially problematic header names and values
		headerName := createFuzzedHeaderName(fuzzData[:5])
		headerValue := createFuzzedHeaderValue(fuzzData[5:])

		req.Header.Set(headerName, headerValue)
	}

	// Add more standard but fuzzed headers
	if len(fuzzData) > 20 {
		req.Header.Set("Content-Type", string(fuzzData[10:20]))
		req.Header.Set("User-Agent", string(fuzzData[15:25]))
	}

	resp, err := client.Do(req)
	if err != nil {
		return
	}

	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
}

func testOversizedRequests(ctx context.Context, client *http.Client, endpoint string, fuzzData []byte) {
	url := endpoint + "/ipp/print"

	// Create oversized request body by repeating fuzz data
	oversizedBody := make([]byte, 0, 1024*1024) // 1MB
	for len(oversizedBody) < cap(oversizedBody) && len(oversizedBody) < 1024*1024 {
		remaining := cap(oversizedBody) - len(oversizedBody)
		if len(fuzzData) <= remaining {
			oversizedBody = append(oversizedBody, fuzzData...)
		} else {
			oversizedBody = append(oversizedBody, fuzzData[:remaining]...)
			break
		}
	}

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(oversizedBody))
	if err != nil {
		return
	}

	req.Header.Set("Content-Type", "application/ipp")

	resp, err := client.Do(req)
	if err != nil {
		return // Expected for oversized requests
	}

	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
}

func testInvalidMethods(ctx context.Context, client *http.Client, endpoint string, fuzzData []byte) {
	// Test with invalid HTTP methods
	invalidMethods := []string{"FUZZ", "INVALID", string(fuzzData[:min(10, len(fuzzData))])}

	for _, method := range invalidMethods {
		select {
		case <-ctx.Done():
			return
		default:
		}

		// Clean method to avoid non-printable chars causing issues
		cleanMethod := strings.Map(func(r rune) rune {
			if r >= 32 && r <= 126 { // printable ASCII
				return r
			}
			return -1 // remove non-printable
		}, method)

		if cleanMethod == "" {
			continue
		}

		req, err := http.NewRequestWithContext(ctx, cleanMethod, endpoint, bytes.NewReader(fuzzData))
		if err != nil {
			continue
		}

		resp, err := client.Do(req)
		if err != nil {
			continue
		}

		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
}

func testMalformedURLs(ctx context.Context, client *http.Client, endpoint string, fuzzData []byte) {
	// Create malformed URLs
	basePaths := []string{"/ipp/print", "/ipp/scan", "/admin"}

	for _, basePath := range basePaths {
		select {
		case <-ctx.Done():
			return
		default:
		}

		// Add fuzzed query parameters
		fuzzedPath := basePath + "?" + string(fuzzData[:min(100, len(fuzzData))])
		url := endpoint + fuzzedPath

		req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
		if err != nil {
			continue // Expected for malformed URLs
		}

		resp, err := client.Do(req)
		if err != nil {
			continue
		}

		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
}

func testContentTypeAttacks(ctx context.Context, client *http.Client, endpoint string, fuzzData []byte) {
	url := endpoint + "/ipp/print"

	// Test various Content-Type attacks
	contentTypes := []string{
		string(fuzzData[:min(50, len(fuzzData))]),
		"application/ipp; " + string(fuzzData[:min(100, len(fuzzData))]),
		strings.Repeat("A", 10000),    // Very long content type
		"application/ipp\x00\x01\x02", // With null bytes
	}

	for _, ct := range contentTypes {
		select {
		case <-ctx.Done():
			return
		default:
		}

		req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(fuzzData))
		if err != nil {
			continue
		}

		req.Header.Set("Content-Type", ct)

		resp, err := client.Do(req)
		if err != nil {
			continue
		}

		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
}

func testChunkedEncoding(ctx context.Context, client *http.Client, endpoint string, fuzzData []byte) {
	url := endpoint + "/ipp/print"

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(fuzzData))
	if err != nil {
		return
	}

	req.Header.Set("Content-Type", "application/ipp")
	req.Header.Set("Transfer-Encoding", "chunked")
	req.TransferEncoding = []string{"chunked"}

	resp, err := client.Do(req)
	if err != nil {
		return
	}

	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
}

func createFuzzedHeaderName(data []byte) string {
	// Create potentially problematic header name
	name := string(data)
	// Ensure it's not empty and doesn't contain invalid chars that would break HTTP
	name = strings.Map(func(r rune) rune {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			return r
		}
		return 'X' // Replace invalid chars
	}, name)

	if name == "" {
		name = "X-Fuzz"
	}
	return name
}

func createFuzzedHeaderValue(data []byte) string {
	// Create potentially problematic header value
	value := string(data)
	// Remove characters that would break HTTP parsing
	value = strings.Map(func(r rune) rune {
		if r == '\r' || r == '\n' {
			return -1 // Remove CR/LF
		}
		if r < 32 && r != '\t' {
			return -1 // Remove control chars except tab
		}
		return r
	}, value)

	return value
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
