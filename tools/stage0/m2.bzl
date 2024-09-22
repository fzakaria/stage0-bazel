"""Rules for compiling C files using the M2 Planet compiler.

"""

def _m2_compile_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    args = ctx.actions.args()
    args.add("--architecture", ctx.attr.architecture)
    args.add_all(ctx.files.srcs, before_each = "-f")
    args.add("--bootstrap-mode")
    if (ctx.attr.is_debug):
        args.add("--debug")
    args.add("-o", out)

    ctx.actions.run(
        outputs = [out],
        inputs = ctx.files.srcs,
        executable = ctx.executable._compiler,
        arguments = [args],
        mnemonic = "M2Compile",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

m2_compile = rule(
    implementation = _m2_compile_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".c"],
            mandatory = True,
            doc = "Source files (C) to compile.",
        ),
        "architecture": attr.string(
            mandatory = True,
            doc = "Architecture to compile for.",
        ),
        "is_debug": attr.bool(
            default = False,
            doc = "Whether to compile in debug mode.",
        ),
        "_compiler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "M2 compiler to use.",
            default = "@//tools/stage0/phase5:M2",
        ),
    },
    doc = """Compiles C files into a M1 program.""",
)