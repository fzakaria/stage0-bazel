"""Nyacc, the parser toolkit mescc's C99 front end is built on.

Only the Scheme modules matter here; the test suite and the standalone tools
are never run.
"""

filegroup(
    name = "runtime_files",
    srcs = glob([
        "module/**/*.scm",
        "module/**/*.d/**",
    ]),
    visibility = ["//visibility:public"],
)
