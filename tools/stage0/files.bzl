"""File-shuffling rules that do not need a shell.

genrule and skylib's copy_file both run `cp` through the host shell, which the
bootstrap graph is not allowed to touch. Bazel can create symlinks itself, so
these rules do the same work as an internal action.
"""

def _relocate_impl(ctx):
    outputs = []
    for src in ctx.files.srcs:
        out = ctx.actions.declare_file(ctx.attr.prefix + "/" + src.basename)
        ctx.actions.symlink(output = out, target_file = src)
        outputs.append(out)

    return [DefaultInfo(files = depset(outputs))]

relocate_files = rule(
    implementation = _relocate_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Files to make visible under a different directory.",
        ),
        "prefix": attr.string(
            mandatory = True,
            doc = "Package-relative directory the files appear in, keeping their basenames.",
        ),
    },
    doc = """Exposes files under a different directory, by basename.

Mes source refers to its architecture headers as `arch/syscall.h` and friends;
upstream's ./configure satisfies that by copying the headers for the selected
target into an `arch` directory. This rule is the same trick without a shell.""",
)
