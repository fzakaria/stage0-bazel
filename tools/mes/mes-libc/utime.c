/* utime, replacing mes-libc's stub.

   Upstream ships lib/stub/utime.c, which takes a single int, issues no
   syscall and returns 0:

       int
       utime (int x)
       {
         ...
         errno = 0;
         return 0;
       }

   That makes `touch` a no-op that reports success. coreutils reaches utime
   because gnulib's fdutimens only calls utimensat when configure could prove
   it works, and proving it means running a test program, which a build like
   this cannot do; the probe therefore guesses no and the code falls through
   to the utime branch. So `touch existing-file` opened the file and did
   nothing else -- strace shows one open() and no timestamp syscall at all.

   A silent no-op here is worse than a missing function, because make's whole
   model is timestamps. A tarball unpacked by mescc-tools-extra's untar
   carries the moment of extraction rather than what the archive recorded, so
   a shipped generated file can look older than the source it was generated
   from, and touching it is the repair. GCC 4.6 needs exactly that for
   gcc/gengtype-lex.c; see tools/pkg/gcc.

   mes-libc already has a real utimensat, so this is a two-line forward. A
   null `times` means "both timestamps to now", which is what utimensat does
   for a null argument as well. */

#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>

/* POSIX's utime buffer. mes-libc publishes no <utime.h>, and nothing else in
   the library names this type. */
struct utimbuf
{
  time_t actime;
  time_t modtime;
};

int
utime (char const *file_name, struct utimbuf const *times)
{
  struct timespec ts[2];

  if (times == 0)
    {
      return utimensat (AT_FDCWD, file_name, 0, 0);
    }

  /* utime carries whole seconds only. */
  ts[0].tv_sec = times->actime;
  ts[0].tv_nsec = 0;
  ts[1].tv_sec = times->modtime;
  ts[1].tv_nsec = 0;
  return utimensat (AT_FDCWD, file_name, ts, 0);
}
