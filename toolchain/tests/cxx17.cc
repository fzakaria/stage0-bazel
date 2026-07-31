/* What the compiler upgrade was for.

   Every construct below is C++17 and none of it exists in GCC 4.6, which
   offered C++98 and a partial C++0x: structured bindings, if constexpr,
   std::optional, std::string_view, and a fold expression. A toolchain still
   pointed at 4.6 does not fail this test at run time, it fails to compile it,
   which is the point.

   A cc_binary rather than a cc_test, because //tools/verify's audits are not
   test rules and cannot depend on a testonly target. program_output_test in
   the BUILD file is what turns it into a test, the same way hello.cc is
   handled; the program still returns non-zero when it is unhappy. */

#include <iostream>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>

namespace {

/* if constexpr: the discarded branch is not instantiated, so this compiles
   for both a type that has a .size() and one that does not. */
template <typename T>
size_t MeasureSize(const T& value) {
  if constexpr (std::is_integral_v<T>) {
    return static_cast<size_t>(value);
  } else {
    return value.size();
  }
}

/* A fold expression over a parameter pack. */
template <typename... Args>
int SumAll(Args... values) {
  return (values + ... + 0);
}

/* std::optional, returning nothing rather than a sentinel value. */
std::optional<int> LookUp(const std::map<std::string, int>& table,
                          std::string_view key) {
  const auto entry = table.find(std::string(key));
  if (entry == table.end()) {
    return std::nullopt;
  }
  return entry->second;
}

}  // namespace

int main() {
  const std::map<std::string, int> table = {{"one", 1}, {"two", 2}};

  /* Structured bindings, over a map whose value_type is a pair. */
  int total = 0;
  for (const auto& [name, value] : table) {
    total += value * static_cast<int>(name.size());
  }
  if (total != 1 * 3 + 2 * 3) {
    std::cerr << "structured bindings: expected 9, got " << total << std::endl;
    return 1;
  }

  if (MeasureSize(std::string("abcd")) != 4 || MeasureSize(7) != 7) {
    std::cerr << "if constexpr: wrong size" << std::endl;
    return 1;
  }

  if (SumAll(1, 2, 3, 4) != 10) {
    std::cerr << "fold expression: expected 10" << std::endl;
    return 1;
  }

  const std::optional<int> found = LookUp(table, "two");
  const std::optional<int> missing = LookUp(table, "three");
  if (!found.has_value() || *found != 2 || missing.has_value()) {
    std::cerr << "optional: wrong lookup result" << std::endl;
    return 1;
  }

  std::cout << "c++17 ok" << std::endl;
  return 0;
}
