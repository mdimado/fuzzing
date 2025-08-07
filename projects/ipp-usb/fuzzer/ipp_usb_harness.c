// ipp_usb_harness.c - AFL++ harness for ipp-usb

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/wait.h>

#define MAX_INPUT_SIZE 65536

int main(int argc, char **argv) {
    char *input_data;
    size_t input_size;
    char temp_file[] = "/tmp/fuzz_input_XXXXXX";
    int fd;
    FILE *fp;

    // Read input from stdin (AFL++ will provide this)
    input_data = (char *)malloc(MAX_INPUT_SIZE);
    if (!input_data) {
        return 1;
    }

    input_size = fread(input_data, 1, MAX_INPUT_SIZE, stdin);
    if (input_size == 0) {
        free(input_data);
        return 1;
    }

    // Create temporary file with fuzzed data
    fd = mkstemp(temp_file);
    if (fd == -1) {
        free(input_data);
        return 1;
    }

    fp = fdopen(fd, "w");
    if (!fp) {
        close(fd);
        unlink(temp_file);
        free(input_data);
        return 1;
    }

    fwrite(input_data, 1, input_size, fp);
    fclose(fp);

    // Execute the wrapper script with the temporary file
    char command[512];
    snprintf(command, sizeof(command), 
             "%s/fuzz_ipp_usb.sh %s", 
             getenv("FUZZER_DIR") ?: ".", 
             temp_file);
    
    int result = system(command);

    // Cleanup
    unlink(temp_file);
    free(input_data);

    return WEXITSTATUS(result);
}