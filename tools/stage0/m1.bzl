"""Rules for expanding M0 files.

This uses the M1 binary rather than M0 which is more capable.
"""
def _m1_expand_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    args = ctx.actions.args()
    args.add("--architecture", ctx.attr.architecture)
    if (ctx.attr.is_little_endian):
        args.add("--little-endian")
    else:
        args.add("--big-endian")
    args.add_all(ctx.files.srcs, before_each = "-f")
    args.add("-o", out)

    ctx.actions.run(
        outputs = [out],
        inputs = ctx.files.srcs,
        executable = ctx.executable.tool,
        arguments = [args],
        mnemonic = "M1Expand",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

m1_expand = rule(
    implementation = _m1_expand_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".M1"],
            mandatory = True,
            doc = "Sources to expand macros. Will be concatenatd together first.",
        ),
        "architecture": attr.string(
            mandatory = True,
            doc = "The architectures to expand for.",
        ),
        "is_little_endian": attr.bool(
            default = False,
            mandatory = True,
            doc = "Whether to expand in little endian mode.",
        ),
        "tool": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The M0 tool.",
            default = "@//tools/stage0/phase7:M1-0",
        ),
    },
    doc = """Expand a M1 file to hex2.""",
)