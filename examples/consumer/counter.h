/* A small library, so that the example exercises the archiver as well as the
   compiler and the linker. */

#ifndef COUNTER_H_
#define COUNTER_H_

#include <map>
#include <string>
#include <vector>

namespace consumer {

/* Counts how many times each word appears, in sorted order. */
std::map<std::string, int> CountWords(const std::vector<std::string>& words);

}  // namespace consumer

#endif  // COUNTER_H_
