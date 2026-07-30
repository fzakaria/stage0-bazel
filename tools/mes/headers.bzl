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
