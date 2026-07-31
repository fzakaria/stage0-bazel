/* A header for the cc_library half of the toolchain check. */

#ifndef TOOLCHAIN_TESTS_GREETING_H_
#define TOOLCHAIN_TESTS_GREETING_H_

#include <string>

namespace stage0 {

/* Returns the two words in sorted order, separated by a space. */
std::string Greeting();

}  // namespace stage0

#endif  // TOOLCHAIN_TESTS_GREETING_H_
