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
        printf("Failed to initialize curl\n");
        return 1;
    }
    
    // Setup curl options that don't change
    curl_easy_setopt(curl_handle, CURLOPT_TIMEOUT, 5L);
    curl_easy_setopt(curl_handle, CURLOPT_CONNECTTIMEOUT, 2L);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, NULL); // Discard response
    curl_easy_setopt(curl_handle, CURLOPT_VERBOSE, 0L);
    curl_easy_setopt(curl_handle, CURLOPT_NOPROGRESS, 1L);
    
    // Get fuzzer directory - use /out if not set
    const char* fuzzer_dir = getenv("FUZZER_DIR");
    if (!fuzzer_dir) fuzzer_dir = "/out";
    
    // Check if setup script exists
    char setup_script[512];
    snprintf(setup_script, sizeof(setup_script), "%s/setup_environment.sh", fuzzer_dir);
    
    if (access(setup_script, F_OK) != 0) {
        printf("Setup script not found at %s, skipping setup\n", setup_script);
        setup_done = 1;
        return 0; // Continue without setup script
    }
    
    // Run setup script
    char setup_cmd[512];
    snprintf(setup_cmd, sizeof(setup_cmd), "%s 2>&1", setup_script);
    
    FILE* setup_output = popen(setup_cmd, "r");
    if (setup_output == NULL) {
        printf("Failed to run setup script\n");
        return 1;
    }
    
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), setup_output) != NULL) {
        printf("Setup: %s", buffer);
    }
    
    int result = pclose(setup_output);
    if (result != 0) {
        printf("Setup script failed with code %d\n", WEXITSTATUS(result));
        // Don't fail completely - continue without setup for OSS-Fuzz compatibility
        printf("Continuing without setup...\n");
    }
    
    // Wait for services to start
    sleep(5);
    
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
    
    curl_easy_setopt(curl_handle, CURLOPT_URL, url);
    curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDS, data);
    curl_easy_setopt(curl_handle, CURLOPT_POSTFIELDSIZE, size);
    
    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/ipp");
    curl_easy_setopt(curl_handle, CURLOPT_HTTPHEADER, headers);
    
    CURLcode res = curl_easy_perform(curl_handle);
    
    curl_slist_free_all(headers);
    
    // Return 0 regardless of curl result to avoid stopping fuzzer
    return 0;
}

// LibFuzzer entry point - this gets called for each input
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // Setup environment on first call
    if (!setup_done) {
        if (setup_environment() != 0) {
            printf("Setup failed, but continuing with fuzzing\n");
        }
    }
    
    // Skip empty inputs
    if (size == 0) {
        return 0;
    }
    
    // Send the fuzzed data via HTTP to ipp-usb
    send_fuzzed_request(data, size);
    
    return 0;  // Always return 0 unless you want to report a crash
}

// LibFuzzer cleanup - called when fuzzing ends
__attribute__((destructor))
void LLVMFuzzerFinalize() {
    cleanup_environment();
    
    // Run cleanup script if it exists
    const char* fuzzer_dir = getenv("FUZZER_DIR");
    if (!fuzzer_dir) fuzzer_dir = "/out";
    
    char cleanup_script[512];
    snprintf(cleanup_script, sizeof(cleanup_script), "%s/cleanup.sh", fuzzer_dir);
    
    if (access(cleanup_script, F_OK) == 0) {
        char cleanup_cmd[512];
        snprintf(cleanup_cmd, sizeof(cleanup_cmd), "%s >/dev/null 2>&1", cleanup_script);
        system(cleanup_cmd);
    }
}