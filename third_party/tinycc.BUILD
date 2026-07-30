"""tinycc, on the branch janneke maintains for the mes bootstrap."""

exports_files(glob(["**"]))

# With ONE_SOURCE, tcc.c textually includes most of the compiler, so the .c
# files are inputs to compiling it just as much as the headers are. stab.def
# is included too and matches neither pattern on its own.
filegroup(
    name = "sources",
    srcs = glob([
        "*.c",
        "*.h",
        "*.def",
    ]),
    visibility = ["//visibility:public"],
)

# tcc.c includes headers from include/ as well, and with ONE_SOURCE the whole
# tree has to be staged together so relative includes resolve.
filegroup(
    name = "tree",
    srcs = glob([
        "*.c",
        "*.h",
        "*.def",
        "include/**",
        "lib/*.c",
        "lib/*.S",
    ]),
    visibility = ["//visibility:public"],
)
