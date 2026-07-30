/* Smoke test for the mescc toolchain.

   This exercises the C library's string and stdio paths rather than a bare
   exit syscall, so a link that resolves nothing beyond crt1 still fails. */

#include <stdio.h>
#include <string.h>

int
main ()
{
  char const *greeting = "hello from mescc";

  if (strlen (greeting) != 16)
    {
      return 1;
    }

  puts (greeting);
  return 0;
}
