"""Rules for building c programs using cc_$arch.
"""

def _cc_compile_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    args = ctx.actions.args()
    args.add(ctx.file.src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = ctx.executable._compiler,
        arguments = [args],
        mnemonic = "CCCompile",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

cc_compile = rule(
    implementation = _cc_compile_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".c"],
            mandatory = True,
            doc = "Source file (C) to compile.",
        ),
        "_compiler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "C compiler to use.",
            default = "@//tools/stage0/phase4:cc_arch",
        ),
    },
    doc = """Compiles a C program; turns it into M1 assembly.""",
)