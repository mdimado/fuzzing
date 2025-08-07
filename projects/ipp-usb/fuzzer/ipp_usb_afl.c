// ipp_usb_afl.c - AFL++ harness for ipp-usb (stdin-based)

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <curl/curl.h>
#include <signal.h>

#define MAX_INPUT_SIZE 65536
#define IPP_USB_PORT 60000

static int setup_done = 0;
static CURL *curl_handle = NULL;

// [Same setup_environment and send_fuzzed_request functions as above]

int main(int argc, char **argv) {
    // Setup signal handlers
    signal(SIGINT, cleanup_environment);
    signal(SIGTERM, cleanup_environment);
    atexit(cleanup_environment);
    
    // One-time setup
    if (setup_environment() != 0) {
        fprintf(stderr, "Failed to setup environment\n");
        return 1;
    }
    
    char *input_data = malloc(MAX_INPUT_SIZE);
    if (!input_data) {
        return 1;
    }
    
    size_t input_size = fread(input_data, 1, MAX_INPUT_SIZE, stdin);
    if (input_size == 0) {
        free(input_data);
        return 1;
    }
    
    // Send the fuzzed data directly via HTTP
    int result = send_fuzzed_request((const uint8_t*)input_data, input_size);
    
    free(input_data);
    return result;
}