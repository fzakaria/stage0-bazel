def _M0_expand_impl(ctx):
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

M0_expand = rule(
    implementation = _M0_expand_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".M1", ".M0"],
            mandatory = True,
            doc = "Sources to expand macros.",
        ),
        "_tool": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The M0 tool.",
            default = "@//tools/stage1:M0",
        ),
    },
    doc = """Concatenate (cat) a series of files.""",
)