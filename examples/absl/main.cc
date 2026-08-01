#include <iostream>

#include "absl/strings/str_cat.h"
#include "wordcount.h"

int main() {
  const auto counts =
      example::CountWords("bootstrap the compiler the whole way the down");
  if (!counts.ok()) {
    std::cerr << counts.status() << std::endl;
    return 1;
  }
  std::cout << example::FormatCounts(*counts) << std::endl;
  return 0;
}
