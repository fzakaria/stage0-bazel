#include <iostream>
#include <map>
#include <string>
#include <vector>

#include "counter.h"

int main() {
  std::vector<std::string> words;
  words.push_back("stage0");
  words.push_back("bazel");
  words.push_back("stage0");

  const std::map<std::string, int> counts = consumer::CountWords(words);
  for (std::map<std::string, int>::const_iterator it = counts.begin();
       it != counts.end(); ++it) {
    std::cout << it->first << "=" << it->second << " ";
  }
  std::cout << std::endl;
  return 0;
}
