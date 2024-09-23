"""Rules for building hex2 programs.

This uses the more advanced hex2 assembler.
If you need the earlier stage checkout hex2.bzl
"""

def _hex2_binary_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    args = ctx.actions.args()
    args.add("--architecture", ctx.attr.architecture)
    if (ctx.attr.is_little_endian):
        args.add("--little-endian")
    else:
        args.add("--big-endian")
    args.add("--base-address", ctx.attr.base_address)
    args.add_all(ctx.files.srcs, before_each = "-f")
    args.add("-o", out)

    ctx.actions.run(
        outputs = [out],
        inputs = ctx.files.srcs,
        executable = ctx.executable.tool,
        arguments = [args],
        mnemonic = "Hex2Assemble",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

hex2_binary = rule(
    implementation = _hex2_binary_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".hex2"],
            mandatory = True,
            doc = "Source files (hex2) to compile.",
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
        "base_address": attr.string(
            mandatory = True,
            doc = "The base address of the program (i.e. 0x8048000).",
        ),
        "tool": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The hex2 assembler.",
            default = "@//tools/stage0/phase10:hex2",
        ),
    },
    doc = """Compiles a hex2 program.""",
    executable = True,
)