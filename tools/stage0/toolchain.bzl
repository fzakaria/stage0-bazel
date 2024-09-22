

def _hex0_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        assembler = ctx.executable.assembler,
    )
    return [toolchain_info]


hex0_toolchain = rule(
    implementation = _hex0_toolchain_impl,
    attrs = {
        "assembler": attr.label(
            executable = True,
            mandatory = True,
            allow_single_file = True,
            cfg = "exec",
            doc = "Assembler for hex0 programs",
        ),
    },
)
