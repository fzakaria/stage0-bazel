load("//tools/stage1:cat.bzl", "cat_files")

# FIXME: I decided to make this a macro but there's probably
# a better way to incorporate this into the rule.
def cc_binary(
    name,
    srcs,
):
    cat_files(
        name = name + ".c",
        srcs = srcs,
    )
    cc_single_binary(
        name = name,
        src = name + ".c",
    )

def _cc_single_binary_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".M1")
    args = ctx.actions.args()
    args.add(ctx.file.src)
    args.add(out)

    ctx.actions.run(
        outputs = [out],
        inputs = [ctx.file.src],
        executable = ctx.executable.compiler,
        arguments = [args],
        mnemonic = "CCCompile",
    )

    return [DefaultInfo(
        files = depset([out]),
        executable = out,
    )]

cc_single_binary = rule(
    implementation = _cc_single_binary_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".c"],
            mandatory = True,
            doc = "Source file (C) to compile.",
        ),
        # FIXME: Should this all be toolchain?
        "compiler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "C compiler to use.",
            default = "@//tools/stage2:cc_x86",
        ),
    },
    doc = """Compiles a C program; turns it into M1 assembly.""",
    executable = True,
)