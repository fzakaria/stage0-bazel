"""Rules for building hex2 programs.
"""

load("//tools/stage0:catm.bzl", "concatenate_files")

def hex2_assemble(ctx, src, assembler, out):
    """
    Compile a hex2 program.

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

def _hex2_binary_impl(ctx):
    srcs = ctx.files.srcs
    
    combined_src = ctx.actions.declare_file("%s_combined.hex2" % ctx.label.name)
    concatenate_files(
        ctx,
        srcs = srcs,
        tool = ctx.executable._catm,
        out = combined_src,
    )

    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    hex2_assemble(
        ctx,
        src = combined_src,
        assembler = ctx.executable.assembler,
        out = out,
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
        "assembler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "hex2 assembler to use.",
            default = "@//tools/stage0/phase2:hex2-0",
        ),
        "_catm": attr.label(
            executable = True,
            cfg = "exec",
            doc = "catm tool to use.",
            default = "@//tools/stage0/phase2:catm",
        ),
    },
    doc = """Compiles a hex2 program.""",
    executable = True,
)

def _hex2_simple_binary_impl(ctx):
    src = ctx.file.src
    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    hex2_assemble(
        ctx,
        src = src,
        assembler = ctx.executable.assembler,
        out = out,
    )
    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

hex2_simple_binary = rule(
    implementation = _hex2_simple_binary_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".hex2"],
            mandatory = True,
            doc = "Source file (hex2) to compile.",
        ),
        "assembler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "hex2 assembler to use.",
            default = "@//tools/stage0/phase2:hex2-0",
        ),
    },
    doc = """Compiles a hex2 program.""",
    executable = True,
)