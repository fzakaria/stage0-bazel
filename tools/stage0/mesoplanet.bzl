"""Rules for compiling C with M2-Mesoplanet.

M2-Mesoplanet is the driver that makes M2-Planet usable as a C compiler: it
handles `#include`, then spawns M2-Planet, blood-elf, M1 and hex2 in turn.

It finds those four by bare name through PATH and locates its C library
through M2LIBC_PATH, so the action needs a directory of correctly-named tools
rather than a set of file paths. `tool_dir` builds that directory.
"""

load("//tools/stage0:exec.bzl", "BOOTSTRAP_EXECUTION_REQUIREMENTS")
load("//tools/stage0:files.bzl", "ToolDirInfo")

def _m2libc_root(ctx):
    """Finds the root of the staged M2libc tree.

    M2-Mesoplanet takes M2LIBC_PATH as a directory, and Starlark can only name
    a directory by naming a file inside it. A staged tree's files are declared
    outputs, which have no labels, so the marker is matched by path suffix.

    Args:
        ctx: The rule context.

    Returns:
        The execroot-relative path of M2libc's root directory.
    """
    suffix = "/" + ctx.attr.m2libc_marker
    for f in ctx.files.m2libc:
        if f.path.endswith(suffix):
            return f.dirname
    fail("no file in m2libc ends with %s" % suffix)

def _m2_mesoplanet_binary_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)
    tools = ctx.attr.tools[ToolDirInfo]

    args = ctx.actions.args()
    args.add("--operating-system", ctx.attr.operating_system)
    args.add("--architecture", ctx.attr.architecture)
    args.add("-f", ctx.file.src)
    args.add("-o", out)

    # The driver writes M2-Planet, blood-elf and M1 output to temporary files
    # before linking them. Left to itself it uses /tmp, which is shared between
    # concurrent actions; the working directory is per-action under a sandbox.
    args.add("--temp-directory", ".")

    ctx.actions.run(
        outputs = [out],
        inputs = depset(
            direct = [ctx.file.src] + ctx.files.hdrs + ctx.files.m2libc,
            transitive = [tools.files],
        ),
        executable = ctx.executable.compiler,
        arguments = [args],
        env = {
            # M2-Mesoplanet spawns its back end by bare name; a relative PATH
            # entry resolves against the action's working directory, which is
            # the execroot.
            "PATH": tools.path,
            "M2LIBC_PATH": _m2libc_root(ctx),
        },
        mnemonic = "MesoplanetCompile",
        execution_requirements = BOOTSTRAP_EXECUTION_REQUIREMENTS,
        progress_message = "Compiling %{label} with M2-Mesoplanet",
    )

    return [DefaultInfo(files = depset([out]), executable = out)]

m2_mesoplanet_binary = rule(
    implementation = _m2_mesoplanet_binary_impl,
    executable = True,
    attrs = {
        "src": attr.label(allow_single_file = [".c"], mandatory = True),
        "hdrs": attr.label_list(allow_files = True, doc = "Headers the source includes."),
        "m2libc": attr.label_list(allow_files = True, doc = "Every file of M2libc."),
        "m2libc_marker": attr.string(
            default = "bootstrappable.c",
            doc = "A file sitting directly in M2libc's root; its directory becomes M2LIBC_PATH.",
        ),
        "operating_system": attr.string(default = "Linux"),
        "architecture": attr.string(default = "amd64"),
        "compiler": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
            doc = "M2-Mesoplanet.",
        ),
        "tools": attr.label(
            providers = [ToolDirInfo],
            mandatory = True,
            doc = "Directory holding M2-Planet, blood-elf, M1 and hex2 under those names.",
        ),
    },
    doc = "Compiles a single C file into a static ELF binary with M2-Mesoplanet.",
)
