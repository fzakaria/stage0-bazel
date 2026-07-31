"""How the bootstrap's actions may be executed.

Every action in this repository below the C++ toolchain runs a program this
repository built, and those programs are freestanding static ELF executables
that talk to the kernel directly. That rules out running them anywhere but
here, for two reasons.

The practical one: a remote executor sandboxes its workers, and the syscalls
these binaries make are not the ones a seccomp filter written for ordinary
compilers expects. Sending the bootstrap to BuildBuddy gets as far as GCC and
then stops with

    Running //tools/pkg/gcc:gcc_dist under kaem failed: (Bad system call)

which is SIGSYS -- the filter rejecting a syscall rather than anything being
wrong with the build.

The one that would matter even if the first were fixed: the claim this
repository makes is that a C++ compiler comes out of a 357-byte seed on your
machine, from sources you can read. An action that runs on someone else's
worker moves part of that claim onto their container image. //:trust-report
checks which program each action executes, not where it ran, so nothing would
go red -- which is exactly why this is declared here rather than left to a
--config someone might forget.

LLVM is the other side of the line and is unaffected: it is an ordinary Bazel
build of an ordinary C++ project, its actions are cc_library and cc_binary
rather than kaem scripts, and they run remotely without complaint. See
--config=remote and --config=llvm in .bazelrc.
"""

BOOTSTRAP_EXECUTION_REQUIREMENTS = {
    "no-remote": "",
}
