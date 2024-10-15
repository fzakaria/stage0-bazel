"""Rules for creating M1 debug footers.

"""

def _blood_elf_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    
    args = ctx.actions.args()
    if (ctx.attr.is_little_endian):
        args.add("--little-endian")
    else:
        args.add("--big-endian")
    args.add("-f", ctx.file.src)
    args.add("-o", out)

    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = ctx.executable._bloodelf,
        arguments = [args],
        mnemonic = "BloodElf",
    )

    return [DefaultInfo(
        files = depset([out]),
    )]

blood_elf = rule(
    implementation = _blood_elf_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".M1"],
            mandatory = True,
            doc = "Source files (M1) to generate debug information.",
        ),
        "is_little_endian": attr.bool(
            default = False,
            mandatory = True,
            doc = "Whether to expand in little endian mode.",
        ),
        "_bloodelf": attr.label(
            executable = True,
            cfg = "exec",
            doc = "Bloodelf tool to create M1 footer for debug",
            default = "@//tools/stage0/phase13:blood-elf"
        )
    },
    doc = """Compiles C files into a M1 program.""",
)