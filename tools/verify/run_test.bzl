"""A test rule that runs a bootstrapped program and checks what it prints.

The programs this repository produces are freestanding static ELF binaries
with no test framework available to them, so the check has to live outside:
the program signals failure through its exit status, and the wrapper compares
its output against what the test expects.
"""

def _program_output_test_impl(ctx):
    program = ctx.executable.program

    # stderr is folded into stdout: freestanding programs from this chain are
    # as likely to report on one as the other, and tcc prints its version
    # banner to stderr.
    ctx.actions.write(
        output = ctx.outputs.executable,
        content = """#!/bin/sh
RUNFILES="${{TEST_SRCDIR:-$0.runfiles}}"
actual=$("$RUNFILES/{workspace}/{program}" {args} 2>&1) || exit 1
expected='{expected}'
if [ "$actual" != "$expected" ]; then
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
fi
""".format(
            workspace = ctx.workspace_name,
            program = program.short_path,
            args = " ".join(ctx.attr.arguments),
            expected = ctx.attr.expected_output,
        ),
        is_executable = True,
    )

    return [DefaultInfo(runfiles = ctx.runfiles(files = [program]))]

program_output_test = rule(
    implementation = _program_output_test_impl,
    test = True,
    attrs = {
        "program": attr.label(
            executable = True,
            cfg = "target",
            mandatory = True,
            doc = "The bootstrapped binary to run.",
        ),
        "arguments": attr.string_list(
            doc = "Command line arguments to pass to the program.",
        ),
        "expected_output": attr.string(
            mandatory = True,
            doc = "Exact stdout the program must produce, without a trailing newline.",
        ),
    },
    doc = "Runs a program and fails unless it exits zero and prints the expected output.",
)
