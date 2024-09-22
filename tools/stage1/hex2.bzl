load(":cat.bzl", "cat_files")

# FIXME: I decided to make this a macro but there's probably
# a better way to incorporate this into the rule.
# Ideally I would like to join the cat_files rule and the hex2_binary rule
# somehow together.
def hex2_multi_binary(
    name,
    srcs,
    assembler = "@//tools/stage1:hex2",
):
    cat_files(
        name = name + ".hex2",
        srcs = srcs,
    )
    hex2_binary(
        name = name,
        src = name + ".hex2",
        assembler = assembler,
    )

def _hex2_binary_impl(ctx):
    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    args = ctx.actions.args()
    args.add(ctx.file.src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = ctx.executable.assembler,
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
        "src": attr.label(
            allow_single_file = [".hex2"],
            mandatory = True,
            doc = "Source file (hex1) to compile.",
        ),
        # FIXME: Should this all be toolchain?
        "assembler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "hex2 assembler to use.",
            default = "@//tools/stage1:hex2",
        ),
    },
    doc = """Compiles a hex2 program.""",
    executable = True,
)