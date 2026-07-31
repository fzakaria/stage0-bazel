/* There is no test framework in this world yet, so a cc_test is a program
   that returns non-zero when it is unhappy. That is all a cc_test has to be,
   and it is enough to show that cc_test resolves to the bootstrapped
   toolchain like everything else. */

#include <iostream>
#include <map>
#include <string>
#include <vector>

#include "counter.h"

int main() {
  std::vector<std::string> words;
  words.push_back("b");
  words.push_back("a");
  words.push_back("b");

  const std::map<std::string, int> counts = consumer::CountWords(words);

  if (counts.size() != 2) {
    std::cerr << "expected 2 distinct words, got " << counts.size() << std::endl;
    return 1;
  }
  if (counts.find("a")->second != 1 || counts.find("b")->second != 2) {
    std::cerr << "wrong counts" << std::endl;
    return 1;
  }
  std::cout << "counter ok" << std::endl;
  return 0;
}
