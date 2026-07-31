/* qsort, replacing mes-libc's.

   Upstream's lib/stdlib/qsort.c partitions around the last element and
   classifies each element against it:

       int c = compare (base + j * size, p);
       if (c < 0)
         {
           qswap (base + i * size, base + j * size, size);
           i++;
         }
       else if (c == 0)
         i++;

   `i` counts the elements already moved below the boundary, so advancing it
   without performing the swap leaves whatever sat at `i` -- possibly an
   element greater than the pivot -- inside the low partition, and strands the
   equal element above it. The returned index is then not the pivot's sorted
   position, the two recursive calls no longer sort disjoint halves, and the
   result comes out unordered. Any input with a repeated value can trigger it;
   over random arrays of at most nine elements drawn from five distinct values,
   a third come back wrong.

   That is not an obscure corner. Two of the programs this bootstrap depends
   on most call qsort on exactly such input:

     - GNU make's `$(sort)`. `$(sort d b a c b e a)` returned `d a c b e`
       instead of `a b c d e`, which stopped GCC's libgcc with
       "Configuration mismatch!" -- libgcc compares `$(sort $(EXTRA_PARTS))`
       against the list the gcc directory sorted the same way.

     - tinycc's case_sort. tccgen.c sorts a switch statement's cases and then
       binary-searches the result to emit the dispatch, so a misordered array
       silently compiles a switch into code that selects the wrong branch.
       Every compiler in this chain is built by a tinycc linked against this
       library, and tinycc's own lexer and code generator are large switches.

   Upstream's recursion is also unbounded in the shape that matters here. It
   recurses on [p, count) rather than on [p + 1, count), so a partition that
   places the pivot first does not shrink, and an already-sorted, reversed or
   all-equal array of n elements recurses n deep -- 500 frames for 500
   elements, which is the common case for a makefile's file lists.

   This is a heapsort instead: in place, no recursion, no allocation, and
   O(n log n) whatever the input looks like. Those properties matter more here
   than speed does, because there is no way to grow the stack and no way to
   report a failed allocation from qsort. */

#include <stdlib.h>

/* Exchange the two objects byte by byte. This is upstream's, unchanged
   except that it tolerates a zero size; it is a public symbol of the
   library, so it stays. */
void
qswap (void *a, void *b, size_t size)
{
  char *pa = a;
  char *pb = b;
  while (size > 0)
    {
      char tmp = *pa;
      *pa++ = *pb;
      *pb++ = tmp;
      size--;
    }
}

/* Restore the heap property at `root`, given that the subtrees below it
   already have it. `count` is the size of the heap, which is the unsorted
   prefix of the array rather than the whole of it. */
static void
sift_down (char *base, size_t root, size_t count, size_t size,
           int (*compare) (void const *, void const *))
{
  while (1)
    {
      size_t child = 2 * root + 1;
      size_t largest;

      if (child >= count)
        return;

      /* Of the two children, the one that could displace the parent. */
      largest = child;
      if (child + 1 < count
          && compare (base + child * size, base + (child + 1) * size) < 0)
        largest = child + 1;

      if (compare (base + root * size, base + largest * size) >= 0)
        return;

      qswap (base + root * size, base + largest * size, size);
      root = largest;
    }
}

void
qsort (void *base, size_t count, size_t size,
       int (*compare) (void const *, void const *))
{
  char *array = base;
  size_t i;

  if (count < 2 || size == 0)
    return;

  /* Heapify: every node that has a child, from the last one back to the
     root. Counting down rather than up is what makes each sift_down see
     subtrees that are already heaps. */
  i = count / 2;
  while (i > 0)
    {
      i--;
      sift_down (array, i, count, size, compare);
    }

  /* The root is now the largest element. Move it to the end, shrink the
     heap by one, and restore the heap property; repeating that leaves the
     array sorted ascending. */
  i = count;
  while (i > 1)
    {
      i--;
      qswap (array, array + i * size, size);
      sift_down (array, 0, i, size, compare);
    }
}
