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
