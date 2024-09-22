def _cat_files_impl(ctx):
    out = ctx.actions.declare_file("%s" % ctx.label.name)
    args = ctx.actions.args()
    args.add(out)
    args.add_all(ctx.files.srcs)

    ctx.actions.run(
        outputs = [out],
        inputs = ctx.files.srcs,
        executable = ctx.executable._tool,
        arguments = [args],
        mnemonic = "Concatenate",
    )

    return [DefaultInfo(
        files = depset([out]),
    )]

cat_files = rule(
    implementation = _cat_files_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Sources to concatenate.",
        ),
        "_tool": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The cat tool.",
            default = "@//tools/stage1:catm",
        ),
    },
    doc = """Concatenate (cat) a series of files.""",
)