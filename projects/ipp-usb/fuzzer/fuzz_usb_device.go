package fuzzer

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"testing"
	"time"
)

// FuzzUSBDeviceSide tests ipp-usb's tolerance to malformed USB device responses
func FuzzUSBDeviceSide(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		log.Printf("DEBUG: Starting fuzz iteration with %d bytes", len(data))

		// Skip very small inputs
		if len(data) < 20 {
			log.Printf("DEBUG: Skipping small input (%d bytes)", len(data))
			return
		}

		// Limit data size to prevent resource exhaustion
		if len(data) > 32*1024 {
			data = data[:32*1024]
			log.Printf("DEBUG: Truncated input to 32KB")
		}

		// Create timeout context
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		log.Printf("DEBUG: About to start testUSBDeviceFuzzing")
		// Test with controlled environment
		testUSBDeviceFuzzing(ctx, t, data)
		log.Printf("DEBUG: Completed testUSBDeviceFuzzing")
	})
}

func testUSBDeviceFuzzing(ctx context.Context, t *testing.T, fuzzData []byte) {
	log.Printf("DEBUG: testUSBDeviceFuzzing started")

	// Create virtual USB device that will send fuzzed responses
	device := NewVirtualUSBDevice(fuzzData)
	log.Printf("DEBUG: Created virtual USB device")

	// Create a cancelable context for this function
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Start USB/IP server for the virtual device
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Printf("DEBUG: Cannot create listener: %v", err)
		t.Skip("Cannot create listener:", err)
		return
	}
	defer listener.Close()

	port := listener.Addr().(*net.TCPAddr).Port
	log.Printf("DEBUG: USB/IP server listening on port %d", port)

	// Start the virtual device server
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		log.Printf("DEBUG: Starting virtual device server")
		device.Serve(ctx, listener)
		log.Printf("DEBUG: Virtual device server stopped")
	}()

	// Give the server time to start
	log.Printf("DEBUG: Waiting for server to start...")
	time.Sleep(50 * time.Millisecond)

	// Start ipp-usb daemon pointing to our virtual device
	log.Printf("DEBUG: About to start ipp-usb daemon")
	ippusbCmd := startIPPUSBDaemon(ctx, t, port)
	if ippusbCmd == nil {
		log.Printf("DEBUG: Failed to start ipp-usb daemon")
		cancel()
		wg.Wait()
		return
	}
	defer func() {
		log.Printf("DEBUG: Killing ipp-usb process")
		ippusbCmd.Process.Kill()
	}()

	log.Printf("DEBUG: ipp-usb daemon started with PID %d", ippusbCmd.Process.Pid)

	// Give ipp-usb time to discover and connect to our virtual device
	log.Printf("DEBUG: Waiting for ipp-usb to discover device...")
	time.Sleep(2 * time.Second)

	// Send test HTTP requests to ipp-usb to trigger USB communication
	log.Printf("DEBUG: About to send test HTTP requests")
	testHTTPRequests(ctx, t)
	log.Printf("DEBUG: Completed test HTTP requests")

	// Cleanup
	log.Printf("DEBUG: Starting cleanup")
	cancel()
	wg.Wait()
	log.Printf("DEBUG: testUSBDeviceFuzzing completed")
}

// VirtualUSBDevice simulates a USB printer that responds with fuzzed data
type VirtualUSBDevice struct {
	fuzzData []byte
	mu       sync.Mutex
}

func NewVirtualUSBDevice(fuzzData []byte) *VirtualUSBDevice {
	return &VirtualUSBDevice{
		fuzzData: fuzzData,
	}
}

func (d *VirtualUSBDevice) Serve(ctx context.Context, listener net.Listener) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("DEBUG: Virtual device server panic: %v", r)
		}
	}()

	log.Printf("DEBUG: Virtual device server running")
	connCount := 0

	for {
		select {
		case <-ctx.Done():
			log.Printf("DEBUG: Virtual device server context cancelled")
			return
		default:
		}

		// Set accept timeout to avoid hanging
		if tcpListener, ok := listener.(*net.TCPListener); ok {
			tcpListener.SetDeadline(time.Now().Add(100 * time.Millisecond))
		}

		conn, err := listener.Accept()
		if err != nil {
			// Check if it's just a timeout
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue // Continue listening
			}

			select {
			case <-ctx.Done():
				log.Printf("DEBUG: Virtual device server stopping due to context")
				return
			default:
				log.Printf("DEBUG: Accept error: %v", err)
				continue
			}
		}

		connCount++
		log.Printf("DEBUG: Virtual device accepted connection %d from %s", connCount, conn.RemoteAddr())
		go d.handleUSBIPConnection(ctx, conn, connCount)
	}
}

func (d *VirtualUSBDevice) handleUSBIPConnection(ctx context.Context, conn net.Conn, connId int) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("DEBUG: Connection %d panic: %v", connId, r)
		}
		conn.Close()
		log.Printf("DEBUG: Connection %d closed", connId)
	}()

	log.Printf("DEBUG: Handling connection %d", connId)
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	buffer := make([]byte, 4096)
	messageCount := 0

	for {
		select {
		case <-ctx.Done():
			log.Printf("DEBUG: Connection %d context cancelled", connId)
			return
		default:
		}

		n, err := conn.Read(buffer)
		if err != nil {
			log.Printf("DEBUG: Connection %d read error: %v", connId, err)
			return
		}

		messageCount++
		log.Printf("DEBUG: Connection %d received message %d (%d bytes)", connId, messageCount, n)

		if n >= 8 {
			d.handleUSBIPMessage(conn, buffer[:n], connId, messageCount)
		}
	}
}

func (d *VirtualUSBDevice) handleUSBIPMessage(conn net.Conn, data []byte, connId, msgId int) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("DEBUG: Message handling panic (conn %d, msg %d): %v", connId, msgId, r)
		}
	}()

	if len(data) < 8 {
		log.Printf("DEBUG: Message too short (%d bytes) on conn %d", len(data), connId)
		return
	}

	// Parse USB/IP command
	command := uint16(data[2])<<8 | uint16(data[3])
	log.Printf("DEBUG: Connection %d message %d: command=0x%04x", connId, msgId, command)

	switch command {
	case 0x8005: // OP_REQ_DEVLIST
		log.Printf("DEBUG: Sending device list response")
		d.sendDeviceList(conn)
	case 0x8003: // OP_REQ_IMPORT
		log.Printf("DEBUG: Sending import response")
		d.sendImportResponse(conn)
	case 0x0001: // USBIP_CMD_SUBMIT
		log.Printf("DEBUG: Sending fuzzed submit response")
		d.sendFuzzedSubmitResponse(conn, data)
	default:
		log.Printf("DEBUG: Sending fuzzed response for unknown command 0x%04x", command)
		d.sendFuzzedResponse(conn, data)
	}
}

func (d *VirtualUSBDevice) sendDeviceList(conn net.Conn) {
	// Send device list with our virtual printer
	response := make([]byte, 312)

	// USB/IP header
	response[0], response[1] = 0x01, 0x11 // version
	response[2], response[3] = 0x80, 0x05 // command
	response[7] = 0x01                    // number of devices

	// Device entry
	copy(response[8:], []byte("1-1.4\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"))
	response[40] = 0x01 // busnum
	response[41] = 0x04 // devnum
	response[42] = 0x01 // speed

	// Device descriptor with printer class
	response[44] = 0x12 // bLength
	response[45] = 0x01 // bDescriptorType
	response[52] = 0x07 // bDeviceClass (printer)
	response[54] = 0x03 // bDeviceProtocol (IPP)

	n, err := conn.Write(response)
	log.Printf("DEBUG: Sent device list response (%d bytes, error: %v)", n, err)
}

func (d *VirtualUSBDevice) sendImportResponse(conn net.Conn) {
	// Send successful import response
	response := make([]byte, 320)
	response[0], response[1] = 0x01, 0x11
	response[2], response[3] = 0x80, 0x03
	// Status = 0 (success)

	n, err := conn.Write(response)
	log.Printf("DEBUG: Sent import response (%d bytes, error: %v)", n, err)
}

func (d *VirtualUSBDevice) sendFuzzedSubmitResponse(conn net.Conn, requestData []byte) {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Extract sequence number from request
	var seqnum uint32
	if len(requestData) >= 8 {
		seqnum = uint32(requestData[4])<<24 | uint32(requestData[5])<<16 |
			uint32(requestData[6])<<8 | uint32(requestData[7])
	}

	// Create response with fuzzed data
	maxFuzzLen := 2048
	fuzzLen := len(d.fuzzData)
	if fuzzLen > maxFuzzLen {
		fuzzLen = maxFuzzLen
	}

	response := make([]byte, 48+fuzzLen)

	// USB/IP RET_SUBMIT header
	response[0], response[1] = 0x01, 0x11 // version
	response[2], response[3] = 0x00, 0x03 // command USBIP_RET_SUBMIT

	// Echo sequence number
	response[4] = byte(seqnum >> 24)
	response[5] = byte(seqnum >> 16)
	response[6] = byte(seqnum >> 8)
	response[7] = byte(seqnum)

	// Status (sometimes inject errors based on fuzz data)
	if len(d.fuzzData) > 0 && d.fuzzData[0]%10 == 0 {
		response[8] = 0xFF // Inject USB error occasionally
	}

	// Actual length
	response[24] = byte(fuzzLen >> 24)
	response[25] = byte(fuzzLen >> 16)
	response[26] = byte(fuzzLen >> 8)
	response[27] = byte(fuzzLen)

	// Copy fuzzed payload
	if fuzzLen > 0 {
		copy(response[48:], d.fuzzData[:fuzzLen])
	}

	n, err := conn.Write(response)
	log.Printf("DEBUG: Sent fuzzed submit response (%d bytes total, %d fuzzed payload, error: %v)",
		n, fuzzLen, err)
}

func (d *VirtualUSBDevice) sendFuzzedResponse(conn net.Conn, requestData []byte) {
	// Send completely fuzzed response for unknown messages
	d.mu.Lock()
	fuzzData := d.fuzzData
	d.mu.Unlock()

	maxLen := 1024
	respLen := len(fuzzData)
	if respLen > maxLen {
		respLen = maxLen
	}

	if respLen > 0 {
		n, err := conn.Write(fuzzData[:respLen])
		log.Printf("DEBUG: Sent raw fuzzed response (%d bytes, error: %v)", n, err)
	}
}

func startIPPUSBDaemon(ctx context.Context, t *testing.T, usbipPort int) *exec.Cmd {
	log.Printf("DEBUG: Attempting to start ipp-usb daemon on USB/IP port %d", usbipPort)

	// Check if ipp-usb exists in different locations, prefer wrapper script
	possiblePaths := []string{"/out/ipp-usb-wrapper", "ipp-usb", "/out/ipp-usb", "/usr/local/bin/ipp-usb", "/usr/bin/ipp-usb"}
	var ippusbPath string

	for _, path := range possiblePaths {
		if _, err := os.Stat(path); err == nil {
			ippusbPath = path
			break
		}
		log.Printf("DEBUG: ipp-usb not found at %s", path)
	}

	if ippusbPath == "" {
		log.Printf("DEBUG: ipp-usb binary not found in any location")
		t.Skip("ipp-usb binary not found")
		return nil
	}

	log.Printf("DEBUG: Found ipp-usb at %s", ippusbPath)

	// Try to start ipp-usb daemon
	cmd := exec.CommandContext(ctx, ippusbPath,
		"-verbose",
		"-debug",
		fmt.Sprintf("-usbip-port=%d", usbipPort))

	// Set LD_LIBRARY_PATH in case wrapper script is not used
	cmd.Env = append(os.Environ(), "LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu")

	// Capture output for debugging
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	log.Printf("DEBUG: Starting command: %s %v", ippusbPath, cmd.Args[1:])
	err := cmd.Start()
	if err != nil {
		log.Printf("DEBUG: Failed to start ipp-usb: %v", err)
		t.Skip("Cannot start ipp-usb daemon:", err)
		return nil
	}

	log.Printf("DEBUG: ipp-usb daemon started successfully with PID %d", cmd.Process.Pid)
	return cmd
}

func testHTTPRequests(ctx context.Context, t *testing.T) {
	log.Printf("DEBUG: Starting HTTP requests test")

	// Send some basic IPP requests to ipp-usb to trigger USB communication
	client := &http.Client{Timeout: 2 * time.Second}

	// Try to find ipp-usb HTTP endpoint (usually on port 60000+)
	testPorts := []int{60000, 60001, 60002, 8080, 80}
	foundPort := -1

	for _, port := range testPorts {
		select {
		case <-ctx.Done():
			log.Printf("DEBUG: HTTP test cancelled by context")
			return
		default:
		}

		url := fmt.Sprintf("http://127.0.0.1:%d/ipp/print", port)
		log.Printf("DEBUG: Trying HTTP endpoint %s", url)

		// Create a simple IPP Get-Printer-Attributes request
		ippRequest := []byte{
			0x02, 0x00, // IPP version 2.0
			0x00, 0x0B, // Get-Printer-Attributes operation
			0x00, 0x00, 0x00, 0x01, // request-id
			0x01,             // begin-attribute-group-tag
			0x47, 0x00, 0x12, // charset attribute
		}

		req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(ippRequest))
		if err != nil {
			log.Printf("DEBUG: Failed to create request for %s: %v", url, err)
			continue
		}
		req.Header.Set("Content-Type", "application/ipp")

		resp, err := client.Do(req)
		if err != nil {
			log.Printf("DEBUG: HTTP request to port %d failed: %v", port, err)
			continue // Try next port
		}

		log.Printf("DEBUG: HTTP request to port %d succeeded (status: %s)", port, resp.Status)
		foundPort = port

		// Read and discard response
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		log.Printf("DEBUG: Received %d bytes response", len(body))

		// Found working port, send a few more requests
		for i := 0; i < 3; i++ {
			select {
			case <-ctx.Done():
				log.Printf("DEBUG: Additional HTTP requests cancelled")
				return
			default:
			}

			log.Printf("DEBUG: Sending additional request %d to port %d", i+1, port)
			req2, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(ippRequest))
			req2.Header.Set("Content-Type", "application/ipp")

			resp2, err := client.Do(req2)
			if err != nil {
				log.Printf("DEBUG: Additional request %d failed: %v", i+1, err)
				break
			}
			body2, _ := io.ReadAll(resp2.Body)
			resp2.Body.Close()
			log.Printf("DEBUG: Additional request %d succeeded (%d bytes)", i+1, len(body2))
		}
		break
	}

	if foundPort == -1 {
		log.Printf("DEBUG: No working HTTP endpoints found on any port")
	} else {
		log.Printf("DEBUG: HTTP requests completed using port %d", foundPort)
	}
}
