package fuzzer

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os/exec"
	"sync"
	"testing"
	"time"
)

// FuzzUSBDeviceSide tests ipp-usb's tolerance to malformed USB device responses
func FuzzUSBDeviceSide(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		// Skip very small inputs
		if len(data) < 20 {
			return
		}

		// Limit data size to prevent resource exhaustion
		if len(data) > 32*1024 {
			data = data[:32*1024]
		}

		// Create timeout context
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		// Test with controlled environment
		testUSBDeviceFuzzing(ctx, t, data)
	})
}

func testUSBDeviceFuzzing(ctx context.Context, t *testing.T, fuzzData []byte) {
	// Create virtual USB device that will send fuzzed responses
	device := NewVirtualUSBDevice(fuzzData)

	// Create a cancelable context for this function
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Start USB/IP server for the virtual device
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Skip("Cannot create listener:", err)
		return
	}
	defer listener.Close()

	port := listener.Addr().(*net.TCPAddr).Port

	// Start the virtual device server
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		device.Serve(ctx, listener)
	}()

	// Give the server time to start
	time.Sleep(50 * time.Millisecond)

	// Start ipp-usb daemon pointing to our virtual device
	ippusbCmd := startIPPUSBDaemon(ctx, t, port)
	if ippusbCmd == nil {
		cancel()
		wg.Wait()
		return
	}
	defer ippusbCmd.Process.Kill()

	// Give ipp-usb time to discover and connect to our virtual device
	time.Sleep(2 * time.Second)

	// Send test HTTP requests to ipp-usb to trigger USB communication
	testHTTPRequests(ctx, t)

	// Cleanup
	cancel()
	wg.Wait()
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
			// Handle panics gracefully
		}
	}()

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		conn, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				continue
			}
		}

		go d.handleUSBIPConnection(ctx, conn)
	}
}

func (d *VirtualUSBDevice) handleUSBIPConnection(ctx context.Context, conn net.Conn) {
	defer func() {
		if r := recover(); r != nil {
			// Handle connection panics
		}
		conn.Close()
	}()

	conn.SetDeadline(time.Now().Add(5 * time.Second))
	buffer := make([]byte, 4096)

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		n, err := conn.Read(buffer)
		if err != nil {
			return
		}

		if n >= 8 {
			d.handleUSBIPMessage(conn, buffer[:n])
		}
	}
}

func (d *VirtualUSBDevice) handleUSBIPMessage(conn net.Conn, data []byte) {
	defer func() {
		if r := recover(); r != nil {
			// Handle message processing panics
		}
	}()

	if len(data) < 8 {
		return
	}

	// Parse USB/IP command
	command := uint16(data[2])<<8 | uint16(data[3])

	switch command {
	case 0x8005: // OP_REQ_DEVLIST
		d.sendDeviceList(conn)
	case 0x8003: // OP_REQ_IMPORT
		d.sendImportResponse(conn)
	case 0x0001: // USBIP_CMD_SUBMIT
		d.sendFuzzedSubmitResponse(conn, data)
	default:
		// Send fuzzed response for unknown commands
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

	conn.Write(response)
}

func (d *VirtualUSBDevice) sendImportResponse(conn net.Conn) {
	// Send successful import response
	response := make([]byte, 320)
	response[0], response[1] = 0x01, 0x11
	response[2], response[3] = 0x80, 0x03
	// Status = 0 (success)

	conn.Write(response)
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

	conn.Write(response)
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
		conn.Write(fuzzData[:respLen])
	}
}

func startIPPUSBDaemon(ctx context.Context, t *testing.T, usbipPort int) *exec.Cmd {
	// Try to start ipp-usb daemon
	// This assumes ipp-usb is installed and available in PATH
	cmd := exec.CommandContext(ctx, "ipp-usb",
		"-verbose",
		"-debug",
		fmt.Sprintf("-usbip-port=%d", usbipPort))

	err := cmd.Start()
	if err != nil {
		t.Skip("Cannot start ipp-usb daemon (not installed?):", err)
		return nil
	}

	return cmd
}

func testHTTPRequests(ctx context.Context, t *testing.T) {
	// Send some basic IPP requests to ipp-usb to trigger USB communication
	client := &http.Client{Timeout: 2 * time.Second}

	// Try to find ipp-usb HTTP endpoint (usually on port 60000+)
	testPorts := []int{60000, 60001, 60002}

	for _, port := range testPorts {
		select {
		case <-ctx.Done():
			return
		default:
		}

		url := fmt.Sprintf("http://127.0.0.1:%d/ipp/print", port)

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
			continue
		}
		req.Header.Set("Content-Type", "application/ipp")

		resp, err := client.Do(req)
		if err != nil {
			continue // Try next port
		}

		// Read and discard response
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()

		// Found working port, send a few more requests
		for i := 0; i < 3; i++ {
			select {
			case <-ctx.Done():
				return
			default:
			}

			req2, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(ippRequest))
			req2.Header.Set("Content-Type", "application/ipp")

			resp2, err := client.Do(req2)
			if err != nil {
				break
			}
			io.Copy(io.Discard, resp2.Body)
			resp2.Body.Close()
		}
		break
	}
}
