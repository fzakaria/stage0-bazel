/* The cc_library half of the toolchain check.

   A separate translation unit archived into a .a and linked into a binary,
   which is the one toolchain action a single-file cc_binary never reaches:
   the archiver. It is binutils' ar, and the index it writes is what lets the
   linker pull this object out again. */

#include "toolchain/tests/greeting.h"

#include <algorithm>
#include <string>
#include <vector>

namespace stage0 {

std::string Greeting() {
  std::vector<std::string> words;
  words.push_back("world");
  words.push_back("hello");
  std::sort(words.begin(), words.end());
  return words[0] + " " + words[1];
}

}  // namespace stage0
