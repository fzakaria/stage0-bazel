"""Rules for expanding M0 files.
"""
load("//tools/stage0:catm.bzl", "concatenate_files")

def _m0_expand_impl(ctx):

    src = None
    # skip the concatenate step if there is only one source file
    if len(ctx.files.srcs) == 1:
        src = ctx.files.srcs[0]
    else:
        combined_src = ctx.actions.declare_file("%s_combined.hex2" % ctx.label.name)
        concatenate_files(
            ctx,
            srcs = ctx.files.srcs,
            tool = ctx.executable._catm,
            out = combined_src,
        )
        src = combined_src

    out = ctx.actions.declare_file("%s" % ctx.label.name)
    args = ctx.actions.args()
    args.add(src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [src],
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
        "srcs": attr.label_list(
            allow_files = [".M1"],
            mandatory = True,
            doc = "Sources to expand macros. Will be concatenatd together first.",
        ),
        "_tool": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The M0 tool.",
            default = "@//tools/stage0/phase3:M0",
        ),
        "_catm": attr.label(
            executable = True,
            cfg = "exec",
            doc = "catm tool to use.",
            default = "@//tools/stage0/phase2:catm",
        ),
    },
    doc = """Expand a M1 file to hex2.""",
)