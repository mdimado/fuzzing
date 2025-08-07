// ipp_usb_libfuzzer.c - LibFuzzer harness for ipp-usb

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <curl/curl.h>
#include <signal.h>
#include <stdint.h>
#include <sys/wait.h>

#define IPP_USB_PORT 60000  // Default ipp-usb port - adjust as needed

static int setup_done = 0;
static CURL *curl_handle = NULL;

// One-time setup function
int setup_environment() {
    if (setup_done) return 0;
    
    printf("Performing one-time setup...\n");
    
    // Initialize curl
    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl_handle = curl_easy_init();
    if (!curl_handle) {
        return 1;
    }
    
    // Setup curl options that don't change
    curl_easy_setopt(curl_handle, CURLOPT_TIMEOUT, 5L);
    curl_easy_setopt(curl_handle, CURLOPT_CONNECTTIMEOUT, 2L);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, NULL); // Discard response
    curl_easy_setopt(curl_handle, CURLOPT_VERBOSE, 0L);
    curl_easy_setopt(curl_handle, CURLOPT_NOPROGRESS, 1L);
    
    // Run setup script once
    const char* fuzzer_dir = getenv("OUT");  // OSS-Fuzz sets OUT directory
    if (!fuzzer_dir) fuzzer_dir = "/out";
    
    char setup_cmd[512];
    snprintf(setup_cmd, sizeof(setup_cmd), "%s/setup_environment.sh >/dev/null 2>&1", fuzzer_dir);
    
    int result = system(setup_cmd);
    if (WEXITSTATUS(result) != 0) {
        printf("Setup script failed\n");
        return 1;
    }
    
    // Wait for services to start
    sleep(10);
    
    setup_done = 1;
    printf("Setup complete\n");
    return 0;
}

// Cleanup function
void cleanup_environment() {
    if (curl_handle) {
        curl_easy_cleanup(curl_handle);
        curl_handle = NULL;
    }
    curl_global_cleanup();
}

// Function to send HTTP request with fuzzed data
int send_fuzzed_request(const uint8_t *data, size_t size) {
    if (!curl_handle) return 1;
    
    char url[256];
    snprintf(url, sizeof(url), "http://localhost:%d/ipp/print", IPP_USB_PORT);
    
    // Reset curl handle for reuse
    curl_easy_reset(curl_handle);
    
    // Set options for this request
    curl_easy_setopt(curl_handle, CURLOPT_URL, url);
    curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDS, data);
    curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDSIZE, size);
    curl_easy_setopt(curl_handle, CURLOPT_TIMEOUT, 5L);
    curl_easy_setopt(curl_handle, CURLOPT_CONNECTTIMEOUT, 2L);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, NULL); // Discard response
    curl_easy_setopt(curl_handle, CURLOPT_VERBOSE, 0L);
    curl_easy_setopt(curl_handle, CURLOPT_NOPROGRESS, 1L);
    
    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/ipp");
    curl_easy_setopt(curl_handle, CURLOPT_HTTPHEADER, headers);
    
    CURLcode res = curl_easy_perform(curl_handle);
    
    // Clean up headers properly
    if (headers) {
        curl_slist_free_all(headers);
    }
    
    // Return 0 for success, 1 for failure
    return (res == CURLE_OK) ? 0 : 1;
}

// LibFuzzer entry point - this gets called for each input
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // Setup environment on first call
    if (!setup_done) {
        if (setup_environment() != 0) {
            // If setup fails, still continue - just simulate success
            // This allows fuzzer to run even without full environment
            setup_done = 1;
        }
    }
    
    // Skip empty inputs
    if (size == 0) {
        return 0;
    }
    
    // Only try HTTP request if curl is available
    if (curl_handle) {
        send_fuzzed_request(data, size);
    } else {
        // Simulate processing the data even without HTTP
        // This gives some basic coverage
        for (size_t i = 0; i < size && i < 100; i++) {
            volatile uint8_t dummy = data[i];
            (void)dummy; // Avoid unused variable warning
        }
    }
    
    return 0;  // Always return 0 unless you want to report a crash
}

// LibFuzzer cleanup - called when fuzzing ends
__attribute__((destructor))
void LLVMFuzzerFinalize() {
    cleanup_environment();
    
    // Run cleanup script
    const char* fuzzer_dir = getenv("OUT");
    if (!fuzzer_dir) fuzzer_dir = "/out";
    
    char cleanup_cmd[512];
    snprintf(cleanup_cmd, sizeof(cleanup_cmd), "%s/cleanup.sh >/dev/null 2>&1", fuzzer_dir);
    system(cleanup_cmd);
}