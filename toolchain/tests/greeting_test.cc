/* A cc_test, so that `bazel test` exercises the toolchain the way a caller
   would. There is no test framework in this repository, so the check is a
   comparison and an exit status -- which is all a cc_test needs to be. */

#include "toolchain/tests/greeting.h"

#include <iostream>
#include <string>

int main() {
  const std::string expected = "hello world";
  const std::string actual = stage0::Greeting();

  if (actual != expected) {
    std::cerr << "expected \"" << expected << "\", got \"" << actual << "\""
              << std::endl;
    return 1;
  }
  std::cout << "greeting ok" << std::endl;
  return 0;
}
