"""Rules for running GNU Mes, the Scheme interpreter stage0 hands off to.

The mes binary is useless on its own: it boots by reading Scheme from a
directory tree it locates through `MES_PREFIX`, and resolves `use-modules`
through `GUILE_LOAD_PATH`. Both have to point at paths inside the action's
execroot, which is what `MesInfo` carries around.
"""

# Relative to MES_PREFIX, this is where mes looks for its boot files. Locating
# any file under it is enough to recover the prefix itself.
_BOOT_FILE = "mes/module/mes/boot-5.scm"

# The two directories mes resolves `(use-modules ...)` against, relative to
# MES_PREFIX. `mes/module` holds the interpreter's own Scheme, `module` holds
# the compiler (mescc) and the libraries user code imports.
_LOAD_PATH_DIRS = [
    "mes/module",
    "module",
]

MesInfo = provider(
    doc = "Everything needed to invoke mes as part of a build action.",
    fields = {
        "interpreter": "File: the mes executable",
        "prefix": "string: execroot-relative directory to pass as MES_PREFIX",
        "runfiles_prefix": "string: the same directory, relative to a runfiles tree",
        "runtime_files": "depset[File]: Scheme sources mes reads at runtime",
    },
)

def _strip_boot_file(path):
    """Recovers the MES_PREFIX directory from a path to a known boot file.

    Args:
        path: A path ending in `_BOOT_FILE`.

    Returns:
        The directory that path makes a MES_PREFIX.
    """
    if not path.endswith(_BOOT_FILE):
        fail("expected %s to end with %s" % (path, _BOOT_FILE))

    # Drop the boot file suffix along with the separator that precedes it.
    return path[:-(len(_BOOT_FILE) + 1)]

def mes_env(mes_info):
    """Builds the environment mes needs to boot inside an action.

    Args:
        mes_info: A MesInfo.

    Returns:
        A dict suitable for the `env` argument of `ctx.actions.run`.
    """
    load_path = ":".join([mes_info.prefix + "/" + d for d in _LOAD_PATH_DIRS])
    return {
        "GUILE_LOAD_PATH": load_path,
        "MES_PREFIX": mes_info.prefix,
    }

def _mes_distribution_impl(ctx):
    boot_file = None
    for f in ctx.files.runtime_files:
        if f.path.endswith(_BOOT_FILE):
            boot_file = f
            break
    if boot_file == None:
        fail("runtime_files must contain %s; mes cannot boot without it" % _BOOT_FILE)

    mes_info = MesInfo(
        interpreter = ctx.executable.interpreter,
        prefix = _strip_boot_file(boot_file.path),
        runfiles_prefix = _strip_boot_file(boot_file.short_path),
        runtime_files = depset(ctx.files.runtime_files),
    )

    return [
        mes_info,
        DefaultInfo(
            files = depset([ctx.executable.interpreter]),
            runfiles = ctx.runfiles(
                files = ctx.files.runtime_files + [ctx.executable.interpreter],
            ),
        ),
    ]

mes_distribution = rule(
    implementation = _mes_distribution_impl,
    attrs = {
        "interpreter": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
            doc = "The mes ELF binary produced by the stage0 chain.",
        ),
        "runtime_files": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Scheme sources mes reads at runtime, including its boot files.",
        ),
    },
    provides = [MesInfo],
    doc = """Pairs the mes binary with the Scheme tree it boots from.

Depend on this rather than on the raw binary: rules that run mes need the
prefix and module path this provider computes.""",
)

def run_mes(ctx, mes_info, arguments, inputs, outputs, mnemonic, progress_message = None):
    """Registers an action that runs a Scheme program under mes.

    Args:
        ctx: The rule context.
        mes_info: The MesInfo describing which mes to run.
        arguments: List of Args objects or strings to pass to mes.
        inputs: depset of File inputs, excluding the mes runtime.
        outputs: List of declared output Files.
        mnemonic: Action mnemonic.
        progress_message: Optional progress message.
    """
    ctx.actions.run(
        outputs = outputs,
        inputs = depset(transitive = [inputs, mes_info.runtime_files]),
        executable = mes_info.interpreter,
        arguments = arguments,
        env = mes_env(mes_info),
        mnemonic = mnemonic,
        progress_message = progress_message,
    )

def _mes_scheme_test_impl(ctx):
    mes_info = ctx.attr.mes[MesInfo]

    # A test resolves paths against its runfiles tree rather than the
    # execroot, so the environment is recomputed here instead of reusing
    # mes_env. Files from another repository sit beside the workspace
    # directory, which their short path expresses as a leading "..".
    prefix = "$RUNFILES/" + ctx.workspace_name + "/" + mes_info.runfiles_prefix
    load_path = ":".join([prefix + "/" + d for d in _LOAD_PATH_DIRS])
    interpreter = "$RUNFILES/" + ctx.workspace_name + "/" + mes_info.interpreter.short_path

    ctx.actions.write(
        output = ctx.outputs.executable,
        content = """#!/bin/sh
RUNFILES="${{TEST_SRCDIR:-$0.runfiles}}"
exec env MES_PREFIX="{prefix}" GUILE_LOAD_PATH="{load_path}" "{interpreter}" -c '{expression}'
""".format(
            prefix = prefix,
            load_path = load_path,
            interpreter = interpreter,
            expression = ctx.attr.expression,
        ),
        is_executable = True,
    )

    return [DefaultInfo(
        runfiles = ctx.runfiles(
            files = [mes_info.interpreter],
            transitive_files = mes_info.runtime_files,
        ),
    )]

mes_scheme_test = rule(
    implementation = _mes_scheme_test_impl,
    test = True,
    attrs = {
        "mes": attr.label(
            providers = [MesInfo],
            mandatory = True,
            doc = "The mes distribution under test.",
        ),
        "expression": attr.string(
            mandatory = True,
            doc = "Scheme expression to evaluate; a non-zero exit fails the test.",
        ),
    },
    doc = """Evaluates a Scheme expression under mes and fails if mes does.

This is a test rather than a build step, so it may use the host shell that the
bootstrap graph itself forbids.""",
)
