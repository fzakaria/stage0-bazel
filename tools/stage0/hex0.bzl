"""Rules for building hex0 programs.
"""

def hex0_assemble(ctx, src, assembler, out):
    """
    Compile a hex0 program.

    Args:
        ctx: The context.
        src: The source file.
        assembler: The assembler to use.
        out: The output file.
    """
    args = ctx.actions.args()
    args.add(src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [src],
        executable = assembler,
        arguments = [args],
        mnemonic = "Hex0Assemble",
    )

def _hex0_binary_impl(ctx):
    src = ctx.file.src
    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    hex0_assemble(
        ctx,
        src = src,
        assembler = ctx.executable.assembler,
        out = out,
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
        "assembler": attr.label(
            allow_single_file = True,
            executable = True,
            mandatory = True,
            cfg = "exec",
            doc = "hex0 assembler to use.",
        ),
    },
    doc = """Compiles a hex0 program.""",
    executable = True,
)