/* Abseil, used the way anyone would use it.

   Nothing here is chosen to be easy on the compiler. absl::flat_hash_map is
   a large template with its own SIMD-adjacent probing, StrSplit and StrJoin
   are variadic template machinery, StatusOr is a discriminated union with
   non-trivial destructors, and the whole library is compiled with the
   platform detection Abseil ships rather than anything this repository
   wrote. */

#include "wordcount.h"

#include <algorithm>
#include <string>
#include <utility>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/ascii.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_join.h"
#include "absl/strings/str_split.h"
#include "absl/strings/string_view.h"

namespace example {

absl::StatusOr<std::vector<std::pair<std::string, int>>> CountWords(
    absl::string_view text) {
  if (text.empty()) {
    return absl::InvalidArgumentError("no text to count");
  }

  /* Split on whitespace, discarding the empty pieces that runs of it leave. */
  absl::flat_hash_map<std::string, int> counts;
  for (absl::string_view word : absl::StrSplit(text, ' ', absl::SkipEmpty())) {
    counts[absl::AsciiStrToLower(word)] += 1;
  }

  /* flat_hash_map iterates in an unspecified order, and deliberately not a
     stable one, so the result has to be sorted to be worth comparing. */
  std::vector<std::pair<std::string, int>> sorted(counts.begin(), counts.end());
  std::sort(sorted.begin(), sorted.end(),
            [](const std::pair<std::string, int>& a,
               const std::pair<std::string, int>& b) {
              if (a.second != b.second) {
                return a.second > b.second;
              }
              return a.first < b.first;
            });
  return sorted;
}

std::string FormatCounts(
    const std::vector<std::pair<std::string, int>>& counts) {
  return absl::StrJoin(counts, ", ",
                       [](std::string* out,
                          const std::pair<std::string, int>& entry) {
                         absl::StrAppend(out, entry.first, "=", entry.second);
                       });
}

}  // namespace example
