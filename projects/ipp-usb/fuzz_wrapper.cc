#include <iostream>
#include <fstream>
#include <vector>
#include <unistd.h>
#include <string>

int main(int argc, char **argv) {
  if (argc < 2) {
    std::cerr << "Usage: " << argv[0] << " <input_file>" << std::endl;
    return 1;
  }

  // The fuzzer will pass the input file path as the first argument.
  std::string input_file = argv[1];

  // Pass the input to your shell script.
  // Note: you may need to adjust your fuzz_target.sh to accept the file path as an argument.
  std::string go_emulator_path = std::string(getenv("OUT")) + "/ipp_usb_emulator";
  std::string go_daemon_path = std::string(getenv("OUT")) + "/ipp-usb";
  std::string script_path = std::string(getenv("OUT")) + "/fuzz_target.sh";

  // Use execl to replace the current process with the shell script.
  // The script can then read from the provided input file.
  execl(script_path.c_str(), script_path.c_str(), go_emulator_path.c_str(), go_daemon_path.c_str(), input_file.c_str(), (char *)NULL);

  // If execl returns, an error occurred.
  perror("execl");
  return 1;
}