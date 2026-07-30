/* A program built by the musl tinycc, linked against musl.

   The point is not that it prints: it is that strdup comes back as a real
   pointer and strlen agrees about its length. Under mes-libc that pair was
   the shape of the bug that made GNU make allocate without bound, because
   an undeclared strdup returned int and lost the top half of its pointer.
   A libc with complete headers is the reason that class of fault is gone. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int
main ()
{
  char *copy = strdup ("musl");

  if (copy == NULL)
    {
      printf ("strdup failed\n");
      return 1;
    }

  printf ("hello from %s, %d\n", copy, (int) strlen (copy));
  free (copy);
  return 0;
}
