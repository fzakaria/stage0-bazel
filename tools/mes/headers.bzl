"""Declarations mes-libc implements but never publishes.

A function that a header does not declare is assumed by C89 to return `int`.
On x86-64 that silently truncates a returned pointer to 32 bits and then sign
extends it, so a program works while the heap sits below 2 GiB and crashes
once address space layout randomisation pushes it higher. GNU make hit this
through `strdup`, and the failure looked like a non-deterministic heap bug
rather than a missing prototype.

Six public functions in mes-libc are in this state. These substitutions add
the declarations to the headers callers already include. The library's own
underscore-prefixed helpers are left alone: they are internal, and nothing
outside the library calls them.
"""

# Each entry appends a declaration after a line that is already there, keyed
# by the header it belongs in.
MES_HEADER_FIXES = {
    "include/string.h": [
        "char *strchr (char const *s, int c);",
        """char *strchr (char const *s, int c);
char *strdup (char const *s);
char *strncat (char *dest, char const *src, size_t n);
char *strpbrk (char const *s, char const *accept);""",
    ],
    "include/stdio.h": [
        "FILE *fopen (char const *file_name, char const *mode);",
        """FILE *fopen (char const *file_name, char const *mode);
FILE *freopen (char const *file_name, char const *mode, FILE *stream);""",
    ],
    "include/stdlib.h": [
        "char *getenv (char const *s);",
        """char *getenv (char const *s);
char *mktemp (char *template);""",
    ],
    "include/unistd.h": [
        "char *getcwd (char *buf, size_t size);",
        """char *getcwd (char *buf, size_t size);
char *ttyname (int filedes);""",
    ],

    "include/pwd.h": [
        "struct passwd *getpwuid ();",
        """struct passwd *getpwuid ();
struct passwd *getpwnam (char const *name);""",
    ],
}

# mes-libc's x86-64 `struct stat` does not match the one the kernel fills in.
# It orders the fields
#
#   ... st_size, st_atime, st_atime_nsec, st_mtime, st_mtime_nsec,
#       st_ctime, st_ctime_nsec, st_blksize, st_blocks, __pad1..__pad4
#
# where the kernel's asm/stat.h for x86-64 puts st_blksize and st_blocks
# immediately after st_size and the three timespecs after those. Every field
# up to st_size is therefore right and everything past it is read from the
# wrong offset: st_blksize comes back holding st_ctime, a Unix timestamp near
# 1.8e9.
#
# opendir passes st_blksize straight to calloc, so every directory a program
# opens asks for 1.8 GB of zeroed memory. GNU make opens enough of them while
# searching implicit rules to exhaust the machine, which looks like make
# leaking rather than like a wrong struct.
#
# The layout below is the kernel's, and the trailing __pad fields become the
# three unused words it actually reserves.
MES_ARCH_HEADER_FIXES = {
    "kernel-stat.h": [
        """  unsigned long	st_size;
  unsigned long	st_atime;
  unsigned long	st_atime_nsec;
  unsigned long	st_mtime;
  unsigned long	st_mtime_nsec;
  unsigned long	st_ctime;
  unsigned long	st_ctime_nsec;
  unsigned long	st_blksize;
  long		st_blocks;
  unsigned long	__pad1;
  unsigned long	__pad2;
  unsigned long	__pad3;
  unsigned long	__pad4;""",
        """  unsigned long	st_size;
  unsigned long	st_blksize;
  long		st_blocks;
  unsigned long	st_atime;
  unsigned long	st_atime_nsec;
  unsigned long	st_mtime;
  unsigned long	st_mtime_nsec;
  unsigned long	st_ctime;
  unsigned long	st_ctime_nsec;
  unsigned long	__unused1;
  unsigned long	__unused2;
  unsigned long	__unused3;""",
    ],
}
