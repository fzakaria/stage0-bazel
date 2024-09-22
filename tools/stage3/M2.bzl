"""Rules for compiling C files using the M2 Planet compiler.

"""

def _M2_binary_impl(ctx):
    m2_toolchain = ctx.toolchains["@//tools/stage3:M2_toolchain_type"]
    # First create the M1 file
    m1_out = ctx.actions.declare_file("%s.M1" % ctx.label.name)
    args = ctx.actions.args()
    args.add("--architecture", m2_toolchain.architecture)
    args.add_all(ctx.files.srcs, before_each = "-f")
    args.add("--bootstrap-mode")
    args.add("-o", m1_out)

    ctx.actions.run(
        outputs = [m1_out],
        inputs = ctx.files.srcs,
        executable = m2_toolchain.compiler,
        arguments = [args],
        mnemonic = "M2Compile",
    )

    # cat multiple files into a single one
    cat_out = ctx.actions.declare_file("%s.cat" % ctx.label.name)
    args = ctx.actions.args()
    args.add(cat_out)
    args.add(m2_toolchain.M1_defs)
    args.add(m2_toolchain.M1_libc_core)
    args.add(m1_out)
    ctx.actions.run(
        outputs = [cat_out],
        inputs = [m2_toolchain.M1_defs, m2_toolchain.M1_libc_core, m1_out],
        executable = ctx.executable._catm,
        arguments = [args],
        mnemonic = "Concatenate",
    )

    # FIXME: this should need an M0 toolchain and we
    # then call a function on it.
    hex2_out = ctx.actions.declare_file("%s.hex2" % ctx.label.name)
    args = ctx.actions.args()
    args.add(cat_out)
    args.add(hex2_out)
    ctx.actions.run(
        outputs = [hex2_out],
        inputs = [cat_out],
        executable = ctx.executable._M0,
        arguments = [args],
        mnemonic = "M0Expand",
    )

    # cat multiple files into a single one
    cat_out = ctx.actions.declare_file("%s.cat" % hex2_out)
    args = ctx.actions.args()
    args.add(cat_out)
    args.add(m2_toolchain.ELF_header)
    args.add(hex2_out)
    ctx.actions.run(
        outputs = [cat_out],
        inputs = [m2_toolchain.ELF_header, hex2_out],
        executable = ctx.executable._catm,
        arguments = [args],
        mnemonic = "Concatenate",
    )

    out = ctx.actions.declare_file("%s.bin" % ctx.label.name)
    args = ctx.actions.args()
    args.add(cat_out)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [cat_out],
        executable = ctx.executable._hex2,
        arguments = [args],
        mnemonic = "Hex2Assemble",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

M2_binary = rule(
    implementation = _M2_binary_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".c"],
            mandatory = True,
            doc = "Source files (C) to compile.",
        ),
        "_catm": attr.label(
            executable = True,
            cfg = "exec",
            doc = "catm tool to use.",
            default = "@//tools/stage1:catm",
        ),
        "_M0": attr.label(
            executable = True,
            cfg = "exec",
            doc = "M0 tool to use.",
            default = "@//tools/stage1:M0",
        ),
        "_hex2": attr.label(
            executable = True,
            cfg = "exec",
            doc = "hex2 assembler to use.",
            default = "@//tools/stage1:hex2-0",
        ),
    },
    doc = """Compiles C files into a program.""",
    executable = True,
    toolchains = [
        "@//tools/stage3:M2_toolchain_type"
    ],
)