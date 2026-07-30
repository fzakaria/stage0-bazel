exports_files([
    "x86/linux/bootstrap.c",
    "bootstrappable.c",
    "x86/x86_defs.M1",
    "x86/libc-core.M1",
    "x86/libc-full.M1",
    "x86/ELF-x86.hex2",
    # Same ELF header, but with the section headers that let a debugger
    # resolve the symbols blood-elf emits.
    "x86/ELF-x86-debug.hex2",
    "x86/linux/unistd.c",
    "x86/linux/fcntl.c",
    "x86/linux/sys/stat.c",
    "fcntl.c",
    "stddef.h",
    "stdio.c",
    "stdio.h",
    "stdlib.c",
    "sys/types.h",
    "sys/utsname.h",
    "string.c",
])

# M2-Mesoplanet resolves its C library through M2LIBC_PATH rather than through
# -I flags, so it needs the whole tree rather than a curated list.
filegroup(
    name = "tree",
    srcs = glob(
        ["**"],
        exclude = ["BUILD.bazel"],
    ),
    visibility = ["//visibility:public"],
)
