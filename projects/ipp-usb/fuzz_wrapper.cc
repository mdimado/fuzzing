  #include <cstdio>
  #include <cstdlib>
  #include <unistd.h>
  #include <string>

  extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
      char filename[] = "/tmp/fuzz_input_XXXXXX";
      int fd = mkstemp(filename);
      if (fd == -1) return 0;
      write(fd, data, size);
      close(fd);

      std::string go_emulator_path = std::string(getenv("OUT")) + "/ipp_usb_emulator";
      std::string go_daemon_path = std::string(getenv("OUT")) + "/ipp-usb";
      std::string script_path = std::string(getenv("OUT")) + "/fuzz_target.sh";

      // Call the script with the temp file
      int ret = system((script_path + " " + go_emulator_path + " " + go_daemon_path + " " + filename).c_str());

      unlink(filename); // Clean up
      return 0;
  }