/* Checks that the C library sorts, and that tinycc dispatches a switch.

   mes-libc's qsort left an element equal to the pivot on the wrong side of
   the partition, so any array with a repeated value could come back
   unordered. See tools/mes/mes-libc/qsort.c.

   Two things depended on that and both were broken by it. GNU make's
   `$(sort)` is a direct call, and it returned makefile lists in the wrong
   order. tinycc's case_sort is the indirect one: tccgen.c sorts a switch
   statement's cases and then binary-searches the sorted array to emit the
   dispatch, so a misordered array compiles a switch into code that jumps to
   the wrong branch. That is silent, and it applies to every program this
   compiler builds -- including the next tinycc.

   The test therefore checks both: qsort on tie-heavy input, and a switch
   wide enough that the compiler emits a search rather than a chain of
   comparisons. */

#include <stdio.h>
#include <stdlib.h>

/* Enough repeated values that a partition mishandling ties cannot avoid
   them, and enough elements that the result is not sorted by luck. */
#define COUNT 32
#define DISTINCT 5

static int
compare_int (void const *a, void const *b)
{
  int x = *(int const *) a;
  int y = *(int const *) b;

  if (x < y)
    {
      return -1;
    }
  return x > y;
}

/* A switch with more arms than tinycc emits as a comparison chain, so the
   generated code is a binary search over case_sort's output. The values are
   deliberately not written in ascending order: the sort is what puts them
   in the order the search assumes. */
static int
classify (int n)
{
  switch (n)
    {
    case 13: return 130;
    case 3: return 30;
    case 21: return 210;
    case 8: return 80;
    case 34: return 340;
    case 1: return 10;
    case 55: return 550;
    case 5: return 50;
    case 89: return 890;
    case 2: return 20;
    case 144: return 1440;
    case 233: return 2330;
    default: return -1;
    }
}

int
main ()
{
  int values[COUNT];
  int cases[] = { 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233 };
  int i;

  /* Descending, with each value repeated, which is the shape the old
     partition got wrong. */
  for (i = 0; i < COUNT; i++)
    {
      values[i] = (COUNT - 1 - i) % DISTINCT;
    }

  qsort (values, COUNT, sizeof (int), compare_int);

  for (i = 1; i < COUNT; i++)
    {
      if (values[i - 1] > values[i])
        {
          printf ("qsort wrong at %d: %d then %d\n",
                  i, values[i - 1], values[i]);
          return 1;
        }
    }
  printf ("qsort ok\n");

  /* Every arm of the switch has to reach its own case, and a value that
     matches none of them has to reach the default. */
  for (i = 0; i < (int) (sizeof (cases) / sizeof (cases[0])); i++)
    {
      if (classify (cases[i]) != cases[i] * 10)
        {
          printf ("switch wrong for %d: %d\n", cases[i], classify (cases[i]));
          return 1;
        }
    }
  if (classify (4) != -1)
    {
      printf ("switch default wrong: %d\n", classify (4));
      return 1;
    }
  printf ("switch ok\n");

  return 0;
}
