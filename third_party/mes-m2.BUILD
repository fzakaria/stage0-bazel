exports_files(glob(["**"]))

# Scheme that mes reads at runtime rather than at build time. `mes/module`
# holds the interpreter's boot files, `module` holds mescc and the Scheme
# libraries compiled programs import.
filegroup(
    name = "runtime_files",
    srcs = glob([
        "mes/module/**",
        "module/**",
    ]),
    visibility = ["//visibility:public"],
)

# The mescc driver: the Scheme program that turns C into M1 assembly.
filegroup(
    name = "mescc_scripts",
    srcs = glob(["scripts/**"]),
    visibility = ["//visibility:public"],
)

# Every header mescc-compiled code can include. Listing them individually
# would mean tracking upstream's include graph by hand.
filegroup(
    name = "headers",
    srcs = glob(["include/**/*.h"]),
    visibility = ["//visibility:public"],
)

# Architecture support files mescc looks up through its -L path: the M1 macro
# definitions, and the ELF header and footer fragments hex2 links around the
# program.
filegroup(
    name = "arch_support",
    srcs = glob([
        "lib/*-mes/*.M1",
        "lib/linux/*-mes/*.hex2",
    ]),
    visibility = ["//visibility:public"],
)
