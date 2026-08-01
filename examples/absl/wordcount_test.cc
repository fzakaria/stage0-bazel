/* A real test framework, compiled by the bootstrapped toolchain.

   GoogleTest is a heavier ask than the hand-rolled cc_test in
   examples/consumer: it wants RTTI, exceptions, threads and a good deal of
   template machinery, and it discovers its own tests through static
   initialisers. If any of that were wrong here, this would not link -- or
   would link and then run nothing. */

#include "wordcount.h"

#include <string>
#include <utility>
#include <vector>

#include "absl/status/status.h"
#include "gtest/gtest.h"

namespace example {
namespace {

TEST(CountWords, CountsCaseInsensitivelyAndSortsByFrequency) {
  const auto counts = CountWords("the cat the hat The");
  ASSERT_TRUE(counts.ok()) << counts.status();
  EXPECT_EQ(FormatCounts(*counts), "the=3, cat=1, hat=1");
}

TEST(CountWords, CollapsesRunsOfWhitespace) {
  const auto counts = CountWords("a   a  b");
  ASSERT_TRUE(counts.ok()) << counts.status();
  EXPECT_EQ(FormatCounts(*counts), "a=2, b=1");
}

TEST(CountWords, RejectsEmptyText) {
  const auto counts = CountWords("");
  ASSERT_FALSE(counts.ok());
  EXPECT_EQ(counts.status().code(), absl::StatusCode::kInvalidArgument);
}

}  // namespace
}  // namespace example
