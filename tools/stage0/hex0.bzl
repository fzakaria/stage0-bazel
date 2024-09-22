"""Rules for building stage0 to something that can generate gcc.

"""

def _hex0_binary_impl(ctx):
    hex0_toolchain = ctx.toolchains["@//tools/stage0:toolchain_type"]
    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    args = ctx.actions.args()
    args.add(ctx.file.src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = hex0_toolchain.assembler,
        arguments = [args],
        mnemonic = "Hex0Assemble",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

hex0_binary = rule(
    implementation = _hex0_binary_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".hex0"],
            mandatory = True,
            doc = "Source file (hex0) to compile.",
        ),
    },
    doc = """Compiles a hex0 program.""",
    executable = True,
    toolchains = [
        "@//tools/stage0:toolchain_type"
    ],
)