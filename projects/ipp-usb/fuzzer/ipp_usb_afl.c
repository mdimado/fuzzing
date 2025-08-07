// ipp_usb_afl.c - AFL++ harness for ipp-usb (stdin-based)

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <curl/curl.h>
#include <signal.h>
#include <stdint.h>
#include <sys/wait.h>

#define MAX_INPUT_SIZE 65536
#define IPP_USB_PORT 60000

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
    const char* fuzzer_dir = getenv("OUT");
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
    
    // Run cleanup script
    const char* fuzzer_dir = getenv("OUT");
    if (!fuzzer_dir) fuzzer_dir = "/out";
    
    char cleanup_cmd[512];
    snprintf(cleanup_cmd, sizeof(cleanup_cmd), "%s/cleanup.sh >/dev/null 2>&1", fuzzer_dir);
    system(cleanup_cmd);
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
    
    // Return 0 for success, 1 for failure
    return (res == CURLE_OK) ? 0 : 1;
}

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