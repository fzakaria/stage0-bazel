/* Exercises the C library tinycc rebuilt: dynamic allocation and stdio, not
   just a bare exit syscall. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int
main (void)
{
  char *buffer = malloc (64);

  if (buffer == NULL)
    {
      return 1;
    }

  strcpy (buffer, "hello from tcc");
  if (strlen (buffer) != 14)
    {
      return 1;
    }

  puts (buffer);
  free (buffer);
  return 0;
}
