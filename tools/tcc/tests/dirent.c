/* Checks that struct stat's fields land where the kernel puts them.

   mes-libc's x86-64 struct stat used to order st_blksize and st_blocks after
   the three timespecs rather than before them, so every field past st_size
   was read from the wrong offset. Nothing failed loudly: st_blksize simply
   came back holding st_ctime, a Unix timestamp near 1.8e9, and opendir --
   which passes st_blksize straight to calloc -- asked for 1.8 GB per
   directory. GNU make opened enough directories searching implicit rules to
   exhaust the machine.

   The two fields are checked against each other rather than against fixed
   values: a block size is a small power of two and a timestamp is not, so a
   layout that swaps them fails whichever way round it is wrong. */

#include <stdio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>

/* Any real filesystem reports a block size in this range. A timestamp cannot
   land in it, which is what makes the check discriminating. */
#define MAX_PLAUSIBLE_BLKSIZE 65536

/* Seconds since the epoch at the start of 2020, comfortably before this code
   was written and comfortably after anything a small integer would give. */
#define MIN_PLAUSIBLE_MTIME 1577836800

int
main ()
{
  struct stat sb;
  DIR *dir;
  int fd;

  fd = open (".", O_RDONLY | O_DIRECTORY);
  if (fd < 0)
    {
      printf ("open failed\n");
      return 1;
    }

  if (fstat (fd, &sb) < 0)
    {
      printf ("fstat failed\n");
      return 1;
    }

  /* A block size that is a small power of two. The timestamp that used to
     appear here is neither small nor a power of two. */
  if (sb.st_blksize > 0
      && sb.st_blksize <= MAX_PLAUSIBLE_BLKSIZE
      && (sb.st_blksize & (sb.st_blksize - 1)) == 0)
    {
      printf ("blksize ok\n");
    }
  else
    {
      printf ("blksize wrong: %d\n", (int) sb.st_blksize);
    }

  /* The mirror of the check above: the timespec fields have to hold
     timestamps, which they do not if st_blksize has displaced them. */
  if (sb.st_mtime >= MIN_PLAUSIBLE_MTIME)
    {
      printf ("mtime ok\n");
    }
  else
    {
      printf ("mtime wrong: %d\n", (int) sb.st_mtime);
    }

  /* The call that turned the wrong offset into an unbounded allocation. */
  dir = opendir (".");
  if (dir == 0)
    {
      printf ("opendir failed\n");
      return 1;
    }
  closedir (dir);
  printf ("opendir ok\n");

  return 0;
}
