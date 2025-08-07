// ipp_usb_harness_optimized.c - Optimized LibFuzzer harness for ipp-usb

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/wait.h>
#include <stdint.h>
#include <signal.h>
#include <sys/stat.h>

#define MAX_INPUT_SIZE 65536
#define MIN_INPUT_SIZE 10

// Global state to avoid repeated setup
static int initialized = 0;
static char temp_dir[256];

// One-time initialization
int LLVMFuzzerInitialize(int *argc, char ***argv) {
    // Create persistent temp directory
    snprintf(temp_dir, sizeof(temp_dir), "/tmp/fuzz_persist_%d", getpid());
    mkdir(temp_dir, 0755);
    
    // Set environment once
    setenv("FUZZER_DIR", "/out", 1);
    setenv("TMPDIR", temp_dir, 1);
    
    // Run setup once at start instead of every iteration
    system("/out/setup_environment.sh");
    
    initialized = 1;
    return 0;
}

// Fast input validator
static int is_valid_ipp_data(const uint8_t *data, size_t size) {
    if (size < MIN_INPUT_SIZE || size > MAX_INPUT_SIZE) return 0;
    
    // Quick checks for IPP-like data
    // IPP requests often start with version bytes or HTTP
    if (size >= 4) {
        // Check for IPP version (major.minor)
        if (data[0] <= 3 && data[1] <= 3) return 1;
        // Check for HTTP
        if (memcmp(data, "GET ", 4) == 0 || 
            memcmp(data, "POST", 4) == 0 ||
            memcmp(data, "HTTP", 4) == 0) return 1;
    }
    
    // Accept binary data too
    return 1;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    static int file_counter = 0;
    char temp_file[512];
    FILE *fp;
    pid_t pid;
    int status;
    
    // Fast input validation
    if (!is_valid_ipp_data(data, size)) {
        return 0;
    }
    
    // Create unique temp file (avoid conflicts)
    snprintf(temp_file, sizeof(temp_file), "%s/input_%d_%d", 
             temp_dir, getpid(), ++file_counter);
    
    // Write input data
    fp = fopen(temp_file, "wb");
    if (!fp) return 0;
    
    fwrite(data, 1, size, fp);
    fclose(fp);
    
    // Use fork instead of system() for better control
    pid = fork();
    if (pid == 0) {
        // Child process - redirect stderr to reduce noise
        freopen("/dev/null", "w", stderr);
        freopen("/dev/null", "w", stdout);
        
        // Execute with timeout built into the script
        execl("/bin/sh", "sh", "-c", 
              "/out/fuzz_ipp_usb.sh", temp_file, NULL);
        _exit(1);
    } else if (pid > 0) {
        // Parent - wait with timeout
        int wait_result = waitpid(pid, &status, WNOHANG);
        if (wait_result == 0) {
            // Still running after brief wait - give it a moment
            usleep(10000); // 10ms
            wait_result = waitpid(pid, &status, WNOHANG);
            if (wait_result == 0) {
                // Kill if still running
                kill(pid, SIGTERM);
                waitpid(pid, &status, 0);
            }
        }
        
        // Check for interesting crashes
        if (WIFSIGNALED(status)) {
            int sig = WTERMSIG(status);
            if (sig == SIGSEGV || sig == SIGABRT || sig == SIGFPE) {
                // Don't cleanup - let fuzzer save this input
                // Just exit to preserve the crash
                abort();
            }
        }
    }
    
    // Quick cleanup (don't call external script every time)
    unlink(temp_file);
    
    return 0;
}