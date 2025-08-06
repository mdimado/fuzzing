#!/bin/bash
set -e

# Read fuzzing input from file argument
FUZZ_INPUT_FILE="$3"

# Configuration
EMULATOR_PORT=3240
IPPUSB_PORT=60000
TEST_TIMEOUT=5

# Cleanup function
cleanup() {
    kill $EMULATOR_PID $IPPUSB_PID 2>/dev/null || true
    # rm -f "$FUZZ_INPUT_FILE" /tmp/fuzz_config_$$.json /tmp/ippusb_$$.conf
}
trap cleanup EXIT

# Determine fuzzing mode from input
determine_fuzz_mode() {
    local input_file="$1"
    local size=$(wc -c < "$input_file")
    
    # Simple heuristic based on input size and content
    if [ $size -lt 100 ]; then
        echo "usb_descriptor"
    elif [ $size -lt 500 ]; then
        echo "usbip_packet"  
    elif grep -q "POST\|GET\|HTTP" "$input_file" 2>/dev/null; then
        echo "http_request"
    else
        echo "ipp_data"
    fi
}

# Generate emulator config
generate_config() {
    local mode="$1"
    local config_file="/tmp/fuzz_config_$$.json"
    
    # Extract some randomness from fuzz input for device IDs
    local vendor_id="03F0"
    local product_id="1234"
    
    if [ -f "$FUZZ_INPUT_FILE" ]; then
        vendor_id=$(od -An -tx2 -N2 "$FUZZ_INPUT_FILE" 2>/dev/null | tr -d ' ' | head -c4 || echo "03F0")
        product_id=$(od -An -tx2 -j2 -N2 "$FUZZ_INPUT_FILE" 2>/dev/null | tr -d ' ' | head -c4 || echo "1234")
    fi
    
    cat > "$config_file" << EOF
{
    "ipp_server_url": "http://localhost:$IPPUSB_PORT/ipp/print",
    "device_name": "AFL Fuzz Printer",
    "vendor_id": "0x$vendor_id",
    "product_id": "0x$product_id", 
    "manufacturer": "AFLCorp",
    "product": "FuzzPrinter",
    "serial": "AFL001",
    "listen_ip": "127.0.0.1",
    "listen_port": $EMULATOR_PORT,
    "debug": false,
    "fuzz_mode": "$mode",
    "fuzz_input_file": "$FUZZ_INPUT_FILE"
}
EOF
    echo "$config_file"
}

# Start emulator
start_emulator() {
    local config_file="$1"
    timeout $TEST_TIMEOUT $OUT/ipp_usb_emulator "$config_file" >/dev/null 2>&1 &
    EMULATOR_PID=$!
    
    # Wait for startup
    for i in {1..20}; do
        if nc -z 127.0.0.1 $EMULATOR_PORT 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Start ipp-usb  
start_ippusb() {
    # Create minimal config
    cat > /tmp/ippusb_$$.conf << EOF
[main]
LogLevel = error
LogDestination = stderr

[http]  
HTTPMinPort = $IPPUSB_PORT
HTTPMaxPort = $((IPPUSB_PORT + 10))
EOF
    
    timeout $TEST_TIMEOUT $OUT/ipp-usb -debug -c /tmp/ippusb_$$.conf >/dev/null 2>&1 &
    IPPUSB_PID=$!
    sleep 0.5
    
    return 0
}

# Send fuzzed data based on mode
send_fuzzed_data() {
    local mode="$1"
    local input_file="$2"
    
    case "$mode" in
        "usb_descriptor"|"usbip_packet")
            # Send raw data to emulator port
            timeout 2 nc 127.0.0.1 $EMULATOR_PORT < "$input_file" 2>/dev/null || true
            ;;
        "http_request")
            # Send HTTP data to ipp-usb
            if nc -z 127.0.0.1 $IPPUSB_PORT 2>/dev/null; then
                timeout 2 nc 127.0.0.1 $IPPUSB_PORT < "$input_file" 2>/dev/null || true
            fi
            ;;
        "ipp_data")
            # Send as IPP POST request
            if nc -z 127.0.0.1 $IPPUSB_PORT 2>/dev/null; then
                {
                    echo "POST /ipp/print HTTP/1.1"
                    echo "Host: localhost:$IPPUSB_PORT"
                    echo "Content-Type: application/ipp"
                    echo "Content-Length: $(wc -c < "$input_file")"
                    echo ""
                    cat "$input_file"
                } | timeout 2 nc 127.0.0.1 $IPPUSB_PORT 2>/dev/null || true
            fi
            ;;
    esac
}

# Main fuzzing logic
main() {
    local fuzz_mode=$(determine_fuzz_mode "$FUZZ_INPUT_FILE")
    local config_file=$(generate_config "$fuzz_mode")
    
    # Start components
    if ! start_emulator "$config_file"; then
        exit 0  # Not a crash, just couldn't start
    fi
    
    if ! start_ippusb; then
        exit 0  # Not a crash, just couldn't start  
    fi
    
    # Send fuzzed data
    send_fuzzed_data "$fuzz_mode" "$FUZZ_INPUT_FILE"
    
    # Wait a bit for processing
    sleep 0.5
    
    # Check if processes are still alive (crashes detected by exit codes)
    if ! kill -0 $IPPUSB_PID 2>/dev/null; then
        echo "ipp-usb crashed!" >&2
        exit 1
    fi
    
    if ! kill -0 $EMULATOR_PID 2>/dev/null; then
        echo "emulator crashed!" >&2  
        exit 1
    fi
    
    # Success - no crash detected
    exit 0
}

# Run the fuzzer
main