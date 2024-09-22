"""Rules for concatenating files via catm.
"""

def concatenate_files(ctx, srcs, tool, out):
    """Concatenate a series of files.

    Args:
        ctx: The context.
        srcs: The source files.
        tool: The catm tool, should be executable.
        out: The output file.
    """
    args = ctx.actions.args()
    args.add(out)
    args.add_all(srcs)

    ctx.actions.run(
        outputs = [out],
        inputs = srcs,
        executable = tool,
        arguments = [args],
        mnemonic = "Concatenate",
    )

def _cat_files_impl(ctx):
    out = ctx.actions.declare_file("%s" % ctx.label.name)
    concatenate_files(
        ctx,
        srcs = ctx.files.srcs,
        tool = ctx.executable._tool,
        out = out,
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
            default = "@//tools/stage0/phase2:catm",
        ),
    },
    doc = """Concatenate (cat) a series of files.""",
)