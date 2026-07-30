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
    # A filter reads its input rather than taking it as an argument, so the
    # wrapper has to be able to supply one. Programs that ignore stdin are
    # unaffected by the empty default.
    stdin = ctx.attr.stdin

    ctx.actions.write(
        output = ctx.outputs.executable,
        content = """#!/bin/sh
RUNFILES="${{TEST_SRCDIR:-$0.runfiles}}"
actual=$(printf '%s' '{stdin}' | "$RUNFILES/{workspace}/{program}" {args} 2>&1)
status=$?
if [ "$status" != "{exit_code}" ]; then
    echo "expected exit {exit_code}, got $status" >&2
    echo "$actual" >&2
    exit 1
fi
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
            exit_code = ctx.attr.expected_exit_code,
            expected = ctx.attr.expected_output,
            stdin = stdin,
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
        "expected_exit_code": attr.int(
            default = 0,
            doc = """Exit status the program must return.

Programs linked against mes-libc sometimes report a non-zero status where a
glibc build would report zero, so this is not always 0.""",
        ),
        "expected_output": attr.string(
            mandatory = True,
            doc = "Exact stdout the program must produce, without a trailing newline.",
        ),
        "stdin": attr.string(
            doc = """Input to feed the program on stdin.

A filter such as sed is only meaningfully exercised by giving it something to
read, which an argument list cannot do.""",
        ),
    },
    doc = "Runs a program and fails unless it exits zero and prints the expected output.",
)
