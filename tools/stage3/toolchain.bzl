

def _M2_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        compiler = ctx.executable.compiler,
        architecture = ctx.attr.architecture,
        M1_defs = ctx.file.M1_defs,
        M1_libc_core = ctx.file.M1_libc_core,
        ELF_header = ctx.file.ELF_header,
    )
    return [toolchain_info]


M2_toolchain = rule(
    implementation = _M2_toolchain_impl,
    attrs = {
        "compiler": attr.label(
            executable = True,
            mandatory = True,
            allow_single_file = True,
            cfg = "exec",
            doc = "Compiler for C programs according to M2 Planet",
        ),
        "architecture": attr.string(
            mandatory = True,
            doc = "Architecture for the M2 Planet compiler",
        ),
        "M1_defs": attr.label(
            allow_single_file = True,
            doc = "M1 definitions file",
            mandatory = True,
        ),
        "M1_libc_core": attr.label(
            allow_single_file = True,
            doc = "M1 libc core file",
            mandatory = True,
        ),
        "ELF_header": attr.label(
            allow_single_file = True,
            doc = "ELF header file",
            mandatory = True,
        ),

    },
)
