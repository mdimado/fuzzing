// ipp_usb_harness.c - Improved LibFuzzer harness for ipp-usb

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/wait.h>
#include <stdint.h>
#include <signal.h>

#define MAX_INPUT_SIZE 65536
#define TIMEOUT_SECONDS 10

static void timeout_handler(int sig) {
    // Kill any hanging processes
    system("pkill -f fuzz_ipp_usb.sh");
    _exit(1);
}

// LibFuzzer entry point
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char temp_file[] = "/tmp/fuzz_input_XXXXXX";
    int fd;
    FILE *fp;
    pid_t pid;
    int status;

    // Limit input size and reject empty inputs
    if (size == 0 || size > MAX_INPUT_SIZE) {
        return 0;
    }

    // Create temporary file with fuzzed data
    fd = mkstemp(temp_file);
    if (fd == -1) {
        return 0;
    }

    fp = fdopen(fd, "wb");  // Binary mode
    if (!fp) {
        close(fd);
        unlink(temp_file);
        return 0;
    }

    fwrite(data, 1, size, fp);
    fclose(fp);

    // Set up timeout handler
    signal(SIGALRM, timeout_handler);
    alarm(TIMEOUT_SECONDS);

    // Fork and execute to better control the process
    pid = fork();
    if (pid == 0) {
        // Child process
        char command[512];
        snprintf(command, sizeof(command), 
                 "%s/fuzz_ipp_usb.sh %s", 
                 getenv("FUZZER_DIR") ?: ".", 
                 temp_file);
        
        // Redirect stderr to avoid noise
        freopen("/dev/null", "w", stderr);
        
        execl("/bin/sh", "sh", "-c", command, NULL);
        _exit(1);
    } else if (pid > 0) {
        // Parent process - wait for child
        waitpid(pid, &status, 0);
        
        // Cancel timeout
        alarm(0);
        
        // If child was killed by signal, that might indicate a crash
        if (WIFSIGNALED(status)) {
            int sig = WTERMSIG(status);
            if (sig == SIGSEGV || sig == SIGABRT || sig == SIGBUS) {
                // This is likely a real crash - let fuzzer know
                unlink(temp_file);
                abort();  // Trigger fuzzer crash detection
            }
        }
    }

    // Cleanup
    unlink(temp_file);
    
    return 0;
}

// Optional: Initialize fuzzer state
int LLVMFuzzerInitialize(int *argc, char ***argv) {
    // Set environment variables or initialize state here
    setenv("FUZZER_DIR", ".", 1);
    return 0;
}