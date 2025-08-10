//go:build gofuzz
// +build gofuzz

package main

import (
    "bytes"
    "fmt"
    "io"
    "net/http"
    "os"
    "os/exec"
    "os/signal"
    "sync"
    "syscall"
    "time"
)

var (
    daemonStarted bool
    daemonMutex   sync.Mutex
    mfpProxyCmd   *exec.Cmd
    ippUsbCmd     *exec.Cmd
)

func init() {
    startDaemons()

    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    go func() {
        <-c
        cleanupDaemons()
        os.Exit(0)
    }()
}

func startDaemons() {
    daemonMutex.Lock()
    defer daemonMutex.Unlock()

    if daemonStarted {
        return
    }

    mfpProxyCmd = exec.Command("./mfp-proxy", "-v", "-U",
        "--ipp=/ipp/print=ipp://localhost:631/printers/TestPrinter")
    mfpProxyCmd.Stdout = nil
    mfpProxyCmd.Stderr = nil
    if err := mfpProxyCmd.Start(); err != nil {
        fmt.Printf("Failed to start mfp-proxy: %v\n", err)
        return
    }

    time.Sleep(2 * time.Second)

    ippUsbCmd = exec.Command("./ipp-usb", "standalone")
    ippUsbCmd.Stdout = nil
    ippUsbCmd.Stderr = nil
    if err := ippUsbCmd.Start(); err != nil {
        fmt.Printf("Failed to start ipp-usb: %v\n", err)
        return
    }

    time.Sleep(3 * time.Second)
    daemonStarted = true
}

func cleanupDaemons() {
    if mfpProxyCmd != nil && mfpProxyCmd.Process != nil {
        mfpProxyCmd.Process.Kill()
    }
    if ippUsbCmd != nil && ippUsbCmd.Process != nil {
        ippUsbCmd.Process.Kill()
    }
}

func Fuzz(data []byte) int {
    if len(data) < 10 || !daemonStarted {
        return -1
    }

    client := &http.Client{Timeout: 2 * time.Second}

    endpoints := []string{
        "http://localhost:60000/ipp/print",
        "http://localhost:60000/eSCL/ScannerCapabilities",
        "http://localhost:60000/",
    }

    for _, endpoint := range endpoints {
        req, err := http.NewRequest("POST", endpoint, bytes.NewReader(data))
        if err != nil {
            continue
        }
        req.Header.Set("Content-Type", "application/ipp")
        resp, err := client.Do(req)
        if err != nil {
            continue
        }
        io.Copy(io.Discard, resp.Body)
        resp.Body.Close()
    }
    return 1
}
