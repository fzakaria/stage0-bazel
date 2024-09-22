def _hex1_binary_impl(ctx):
    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    args = ctx.actions.args()
    args.add(ctx.file.src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = ctx.executable._assembler,
        arguments = [args],
        mnemonic = "Hex1Assemble",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

hex1_binary = rule(
    implementation = _hex1_binary_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".hex1"],
            mandatory = True,
            doc = "Source file (hex1) to compile.",
        ),
        # FIXME: Should this all be toolchain?
        "_assembler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "hex1 assembler to use.",
            default = "@//tools/stage1:hex1",
        ),
    },
    doc = """Compiles a hex1 program.""",
    executable = True,
)