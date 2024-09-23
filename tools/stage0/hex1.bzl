"""Rules for building hex1 programs.
"""

def hex1_assemble(ctx, src, assembler, out):
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
        mnemonic = "Hex2Assemble",
    )

def _hex1_binary_impl(ctx):
    src = ctx.file.src
    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    hex1_assemble(
        ctx,
        src = src,
        assembler = ctx.executable._assembler,
        out = out,
    )
    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

hex1_binary = rule(
    implementation = _hex1_binary_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".hex1"],
            mandatory = True,
            doc = "Source file (hex1) to compile.",
        ),
        "_assembler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "hex1 assembler to use.",
            default = "@//tools/stage0/phase1:hex1",
        ),
    },
    doc = """Compiles a hex1 program.""",
    executable = True,
)