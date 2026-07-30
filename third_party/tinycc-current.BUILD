"""Current tinycc, from repo.or.cz."""

exports_files(glob(["**"]))

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
