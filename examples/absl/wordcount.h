/* Counting words, as an excuse to make Abseil do real work. */

#ifndef EXAMPLES_ABSL_WORDCOUNT_H_
#define EXAMPLES_ABSL_WORDCOUNT_H_

#include <string>
#include <utility>
#include <vector>

#include "absl/status/statusor.h"
#include "absl/strings/string_view.h"

namespace example {

/* Counts the words in `text`, case-insensitively, most frequent first and
   ties broken alphabetically. Returns InvalidArgumentError for empty text. */
absl::StatusOr<std::vector<std::pair<std::string, int>>> CountWords(
    absl::string_view text);

/* Renders what CountWords returned as "word=n, word=n". */
std::string FormatCounts(
    const std::vector<std::pair<std::string, int>>& counts);

}  // namespace example

#endif  // EXAMPLES_ABSL_WORDCOUNT_H_
