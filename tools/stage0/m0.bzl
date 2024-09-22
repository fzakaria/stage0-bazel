"""Rules for expanding M0 files.
"""

def _m0_expand_impl(ctx):
    out = ctx.actions.declare_file("%s" % ctx.label.name)
    args = ctx.actions.args()
    args.add(ctx.file.src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = ctx.executable._tool,
        arguments = [args],
        mnemonic = "M0Expand",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

m0_expand = rule(
    implementation = _m0_expand_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".M1"],
            mandatory = True,
            doc = "Source to expand macros.",
        ),
        "_tool": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The M0 tool.",
            default = "@//tools/stage0/phase3:M0",
        ),
    },
    doc = """Expand a M1 file to hex2.""",
)