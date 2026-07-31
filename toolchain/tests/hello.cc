/* A C++ program compiled by the toolchain this repository bootstraps.

   It is deliberately not the smallest possible one. `int main() { return 0; }`
   would prove that the driver runs; this asks for the parts of a C++
   implementation that a bootstrap is most likely to be missing:

     - libstdc++, through <string>, <vector> and <algorithm>;
     - iostreams, which pull in the locale machinery and the static
       initialisation that constructs std::cout before main;
     - templates instantiated across headers;
     - exceptions, which need libsupc++, the unwinder in libgcc, and the
       .eh_frame the assembler and linker have to have got right.

   The last of those is the one that actually exercises the whole chain: an
   exception thrown and caught means the unwind tables the compiler emitted,
   the assembler encoded and the linker merged all agree. */

#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

/* A template, so that the compiler has to instantiate something. */
template <typename T>
T largest(const std::vector<T>& values) {
  if (values.empty()) {
    throw std::runtime_error("largest of nothing");
  }
  return *std::max_element(values.begin(), values.end());
}

}  // namespace

int main() {
  std::vector<std::string> words;
  words.push_back("world");
  words.push_back("hello");
  std::sort(words.begin(), words.end());

  for (std::vector<std::string>::const_iterator it = words.begin();
       it != words.end(); ++it) {
    std::cout << *it << " ";
  }
  std::cout << std::endl;

  std::vector<int> numbers;
  numbers.push_back(3);
  numbers.push_back(11);
  numbers.push_back(7);
  std::cout << "largest " << largest(numbers) << std::endl;

  /* Throw across a function boundary and catch by reference: this is what
     needs the unwinder. */
  try {
    largest(std::vector<int>());
    std::cout << "no exception" << std::endl;
    return 1;
  } catch (const std::runtime_error& error) {
    std::cout << "caught " << error.what() << std::endl;
  }

  return 0;
}
