/* The language features the self-rebuild chain switches on, one stage at a
   time: bitfields, long long, and floating point. A compiler that skipped a
   stage produces wrong answers here rather than failing to build. */

#include <stdio.h>

struct packed
{
  unsigned low : 3;
  unsigned high : 5;
};

int
main (void)
{
  struct packed bits;
  double scaled = 3.5;
  long long big = 1234567890123LL;
  char line[128];

  bits.low = 5;
  bits.high = 20;

  snprintf (line, sizeof line, "%d %d %lld %d", bits.low, bits.high, big,
            (int) (scaled * 2));
  puts (line);
  return 0;
}
