#include "counter.h"

namespace consumer {

std::map<std::string, int> CountWords(const std::vector<std::string>& words) {
  std::map<std::string, int> counts;
  for (std::vector<std::string>::const_iterator it = words.begin();
       it != words.end(); ++it) {
    ++counts[*it];
  }
  return counts;
}

}  // namespace consumer
