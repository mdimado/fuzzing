package fuzzer

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"time"
)

var (
	daemonStarted bool
	daemonMutex   sync.Mutex
	proxyStarted  bool
	proxyMutex    sync.Mutex
)

// FuzzHTTPInterface fuzzes ipp-usb through HTTP interface
func FuzzHTTPInterface(data []byte) int {
	if len(data) < 10 {
		return 0
	}

	// Ensure daemon is running
	if !ensureDaemonRunning() {
		return 0
	}

	// Try to send HTTP request to ipp-usb
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Create HTTP request with fuzzed data
	req, err := http.NewRequestWithContext(ctx, "POST", "http://localhost:60000/ipp/print", bytes.NewReader(data))
	if err != nil {
		return 0
	}

	req.Header.Set("Content-Type", "application/ipp")
	req.Header.Set("Content-Length", fmt.Sprintf("%d", len(data)))

	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		return 0
	}
	defer resp.Body.Close()

	// Read response to trigger processing
	io.Copy(io.Discard, resp.Body)

	return 1
}

// FuzzIPPMessage fuzzes IPP message parsing
func FuzzIPPMessage(data []byte) int {
	if len(data) < 8 {
		return 0
	}

	// Ensure daemon is running
	if !ensureDaemonRunning() {
		return 0
	}

	// Send raw IPP data
	conn, err := net.DialTimeout("tcp", "localhost:60000", 5*time.Second)
	if err != nil {
		return 0
	}
	defer conn.Close()

	// Set timeouts
	conn.SetDeadline(time.Now().Add(5 * time.Second))

	// Send fuzzed IPP data
	_, err = conn.Write(data)
	if err != nil {
		return 0
	}

	// Read response
	buffer := make([]byte, 4096)
	conn.Read(buffer)

	return 1
}

// FuzzUSBDescriptor fuzzes USB descriptor handling
func FuzzUSBDescriptor(data []byte) int {
	if len(data) < 18 { // Minimum USB descriptor size
		return 0
	}

	// This would require integration with the USBIP virtual device
	// For now, we'll simulate descriptor processing

	// Ensure proxy is running
	if !ensureProxyRunning() {
		return 0
	}

	// In a real implementation, this would feed the descriptor data
	// to the USBIP virtual device simulation
	return processUSBDescriptor(data)
}

func ensureDaemonRunning() bool {
	daemonMutex.Lock()
	defer daemonMutex.Unlock()

	if daemonStarted {
		return true
	}

	// Setup environment first
	if !setupEnvironment() {
		return false
	}

	// Start ipp-usb daemon
	cmd := exec.Command("/out/ipp-usb", "standalone")
	cmd.Env = append(os.Environ(),
		"IPPUSB_LOG_LEVEL=error", // Reduce logging noise
		"IPPUSB_QUIRKS_DISABLE=true",
	)

	if err := cmd.Start(); err != nil {
		return false
	}

	// Wait for daemon to be ready
	for i := 0; i < 50; i++ {
		if isPortOpen("localhost:60000") {
			daemonStarted = true
			return true
		}
		time.Sleep(100 * time.Millisecond)
	}

	return false
}

func ensureProxyRunning() bool {
	proxyMutex.Lock()
	defer proxyMutex.Unlock()

	if proxyStarted {
		return true
	}

	// Start mfp-proxy
	cmd := exec.Command("/out/mfp-proxy", "-v", "-U", "--ipp=/ipp/print=ipp://localhost:631/printers/TestPrinter")
	if err := cmd.Start(); err != nil {
		return false
	}

	// Wait for proxy to be ready
	time.Sleep(2 * time.Second)
	proxyStarted = true
	return true
}

func setupEnvironment() bool {
	// Load USBIP kernel modules
	exec.Command("modprobe", "usbip_core").Run()
	exec.Command("modprobe", "vhci_hcd").Run()

	// Give modules time to load
	time.Sleep(1 * time.Second)

	// Ensure proxy is running
	if !ensureProxyRunning() {
		return false
	}

	// Attach virtual device
	time.Sleep(1 * time.Second)
	if err := exec.Command("usbip", "attach", "-r", "127.0.0.1", "-b", "1-1").Run(); err != nil {
		// Try to list devices first
		exec.Command("usbip", "list", "-r", "127.0.0.1").Run()
		time.Sleep(500 * time.Millisecond)
		// Retry attach
		exec.Command("usbip", "attach", "-r", "127.0.0.1", "-b", "1-1").Run()
	}

	return true
}

func isPortOpen(address string) bool {
	conn, err := net.DialTimeout("tcp", address, 1*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func processUSBDescriptor(data []byte) int {
	// Basic USB descriptor validation
	if len(data) < 18 {
		return 0
	}

	// Check if it looks like a USB device descriptor
	if data[0] < 18 || data[1] != 0x01 {
		return 0
	}

	// Simulate descriptor processing
	// In a real implementation, this would feed the descriptor
	// to the virtual USBIP device
	return 1
}
