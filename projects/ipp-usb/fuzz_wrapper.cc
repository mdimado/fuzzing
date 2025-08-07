#include <iostream>
#include <fstream>
#include <vector>
#include <unistd.h>
#include <string>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  // Create a temporary file with the fuzz data
  std::string temp_file = "/tmp/afl_input_XXXXXX";
  int fd = mkstemp(&temp_file[0]);
  if (fd == -1) {
    return 0;  // Not a crash, just couldn't create temp file
  }
  
  // Write the fuzz data to the temp file
  if (write(fd, data, size) != static_cast<ssize_t>(size)) {
    close(fd);
    unlink(temp_file.c_str());
    return 0;  // Not a crash, just couldn't write data
  }
  close(fd);

  // Get paths for the components
  std::string go_emulator_path = std::string(getenv("OUT") ? getenv("OUT") : "/out") + "/ipp_usb_emulator";
  std::string go_daemon_path = std::string(getenv("OUT") ? getenv("OUT") : "/out") + "/ipp-usb";
  std::string script_path = std::string(getenv("OUT") ? getenv("OUT") : "/out") + "/fuzz_target.sh";

  // Fork and execute the shell script
  pid_t pid = fork();
  if (pid == 0) {
    // Child process: execute the shell script
    execl(script_path.c_str(), script_path.c_str(), go_emulator_path.c_str(), go_daemon_path.c_str(), temp_file.c_str(), (char *)NULL);
    // If execl returns, an error occurred
    exit(1);
  } else if (pid > 0) {
    // Parent process: wait for child
    int status;
    waitpid(pid, &status, 0);
    
    // Clean up temp file
    unlink(temp_file.c_str());
    
    // Return 0 for success, 1 for crash
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 1;
  } else {
    // Fork failed
    unlink(temp_file.c_str());
    return 0;  // Not a crash, just couldn't fork
  }
}