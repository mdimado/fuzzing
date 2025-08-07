// ipp_usb_harness_libfuzzer.c - LibFuzzer harness for ipp-usb

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/wait.h>
#include <stdint.h>

#define MAX_INPUT_SIZE 65536

// LibFuzzer entry point - THIS IS REQUIRED FOR LIBFUZZER
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char temp_file[] = "/tmp/fuzz_input_XXXXXX";
    int fd;
    FILE *fp;

    // Limit input size
    if (size == 0 || size > MAX_INPUT_SIZE) {
        return 0;
    }

    // Create temporary file with fuzzed data
    fd = mkstemp(temp_file);
    if (fd == -1) {
        return 0;
    }

    fp = fdopen(fd, "wb");
    if (!fp) {
        close(fd);
        unlink(temp_file);
        return 0;
    }

    fwrite(data, 1, size, fp);
    fclose(fp);

    // Execute the wrapper script with the temporary file
    char command[512];
    snprintf(command, sizeof(command), 
             "%s/fuzz_ipp_usb.sh %s 2>/dev/null", 
             getenv("FUZZER_DIR") ?: ".", 
             temp_file);
    
    int result = system(command);

    // Cleanup
    unlink(temp_file);

    // Return 0 to continue fuzzing
    return 0;
}