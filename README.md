# Stage0 in Bazel

Bootstrapping a compiler toolchain from [stage0](https://github.com/oriansj/stage0)
under [Bazel](https://bazel.build/), the way Nix and Guix do it, with the
bootstrap expressed as a build graph rather than as shell scripts.

The chain starts from a single 357-byte hand-auditable binary — the hex0 seed —
and builds everything above it. No compiler, assembler, linker or shell from
the host participates, and that claim is checked rather than asserted; see
[Verifying no host toolchain is used](#verifying-no-host-toolchain-is-used).

## Where the chain currently reaches

| Stage | Status |
| --- | --- |
| hex0 → hex1 → hex2 → catm → M0 → cc_x86 (phases 0–5) | ✅ |
| M2-Planet, M1, blood-elf, kaem, M2-Mesoplanet, get_machine (phases 6–15) | ✅ |
| GNU Mes (Scheme interpreter) | ✅ boots and evaluates |
| mescc (C99 compiler) and the mes C library | ✅ compiles and links working programs |
| tinycc (`tcc-mes`, i386 target) | ✅ builds, runs, compiles C to i386 objects |
| tinycc hosted natively on x86-64 | ❌ blocked, see below |
| binutils, GCC 4.7 (first with usable C++), modern GCC | ❌ not started |

**There is no C or C++ `cc_toolchain` yet, and this module cannot build
ordinary C++ code.** Neither mescc nor tinycc 0.9.27 compiles C++, and
registering a `cc_toolchain` on top of them would advertise a capability that
does not exist. That wiring is deliberately deferred until the chain reaches a
compiler that can compile C++ — see [Roadmap](#roadmap).

What *does* work today is that C is compiled and linked by compilers whose
entire ancestry is in this repository:

```console
$ bazel test //...
//tools/mes:mes_boot_test                                       PASSED
//tools/mes/tests:hello_test                                    PASSED
//tools/stage0/phase0:hex0-diff                                 PASSED
//tools/stage0/phase2:catm-diff-test                            PASSED
//tools/tcc:tcc_version_test                                    PASSED

$ bazel run //tools/mes/tests:hello
hello from mescc

$ bazel run //:tcc-mes -- -v
tcc version 0.9.27 (i386 Linux)
```

Those binaries are statically linked x86-64 ELF executables whose only
untrusted input is the hex0 seed.

`tcc-mes` targets i386 while running as x86-64, which makes it a cross
compiler. That is not a shortcut: the 64-bit code paths in tinycc reach
`Elf64_*` typedefs that mescc's C parser cannot handle, and i386 is the target
upstream and live-bootstrap bootstrap through. Moving the chain to a natively
hosted x86-64 tcc is a later step.

## Building

The repository pins its Bazel release in `.bazelversion`, so use
[bazelisk](https://github.com/bazelbuild/bazelisk). A `shell.nix` is provided
that supplies bazelisk and a JDK, and deliberately supplies no C compiler:

```console
$ nix-shell
$ bazel test //...
$ bazel build //:trust-report && cat bazel-bin/tools/verify/no_native_toolchain.report
```

## Verifying no host toolchain is used

Two mechanisms: one configured, one checked.

`.bazelrc` sets `BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1`, so Bazel does not
auto-detect a host C++ toolchain, and `--incompatible_strict_action_env`, so
actions see a fixed `PATH` rather than the developer's.

Configuration can be overridden on the command line, so the real check is
`//:trust-report`. It runs an aspect over every action reachable from the
bootstrap roots and inspects the program each one actually executes. Anything
not under `bazel-out/` fails analysis, with one allowlisted exception:

```
Bootstrap trust report

Every action in the checked graph runs a program built by this
repository, except for these audited seed binaries:

external/+_repo_rules+hex0-seeds/POSIX/x86/hex0-seed
```

Test targets are exempt. Bazel's own test runner is a bash script, and the
audits themselves live in test targets; the exemption is confined to test
actions and does not extend to anything producing a build artifact.

## Using this as a Bazel module

```starlark
bazel_dep(name = "stage0-bazel", version = "0.1.0")
```

```starlark
load("@stage0-bazel//tools:defs.bzl", "mescc_binary", "mescc_object")

mescc_object(
    name = "hello_o",
    src = "hello.c",
    toolchain = "@stage0-bazel//:mescc",
)

mescc_binary(
    name = "hello",
    objects = [":hello_o"],
    toolchain = "@stage0-bazel//:mescc",
)
```

The bootstrapped tools are also available under stable labels:
`@stage0-bazel//:hex2`, `//:M1`, `//:blood-elf`, `//:M2-Planet`,
`//:M2-Mesoplanet`, `//:get_machine`, `//:kaem`, `//:mes` and `//:tcc-mes`.

## How the pieces fit

Each stage0 phase lives in its own package under `tools/stage0/phaseN`, and the
rules that drive the tools live in `tools/stage0/*.bzl`. From phase 7 onward
every binary carries a blood-elf symbol footer and is linked against the
debuggable ELF header, so `objdump` and `gdb` work on the intermediate tools —
which is exactly when a bootstrap is hardest to debug without them.

mescc is not a single binary. It is a Scheme program interpreted by mes, it
parses C with [nyacc](https://www.nongnu.org/nyacc/), and it spawns the stage0
`M1`, `hex2` and `blood-elf` tools to assemble and link. `tools/stage0/mescc.bzl`
hides that: the tool locations go through the `M1`, `HEX2` and `BLOOD_ELF`
environment variables mescc already honours, so `PATH` — and with it the host —
never enters the picture.

The file formats are stage0's rather than the platform's. A mescc `.o` is a
hex2 file, and an "archive" is those files concatenated, which is all upstream's
`mesar` does. The concatenation is performed by `catm` from phase 2, so even
archiving uses no host tool.

## Roadmap

The remaining path to C++ follows
[live-bootstrap](https://github.com/fosslinux/live-bootstrap), which is the
reference for how far this has to go:

1. **A natively hosted tcc.** `tcc-mes` currently emits i386 code. Either
   build an i386 mes so the whole chain is 32-bit as live-bootstrap does, or
   use the i386 tcc to build an x86-64 tcc.
2. **tinycc 0.9.27**, rebuilt several times against musl.
3. **The shell-script problem.** Everything past tinycc — binutils, GCC — is
   built by `./configure && make`. live-bootstrap solves this by bootstrapping
   `kaem`, then a real shell, `make`, `sed`, `tar` and the rest. `kaem` is
   already built here (phase 11), but each of those packages is its own port.
4. **GCC 4.0.4 → 4.7.4.** 4.7.4 is the first release whose C++ front end is
   usable for building later GCCs.
5. **Modern GCC**, and only then a `cc_toolchain` that can honestly claim C++
   support.

Steps 3 and 4 are the bulk of the work; this is a project measured in months,
not an afternoon.

## References

- [stage0-posix](https://github.com/oriansj/stage0-posix) — the reference
  bootstrap this repository mirrors.
- [live-bootstrap parts.rst](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst)
  — the clearest description of what each tool in the chain does.
- [GNU Mes](https://www.gnu.org/software/mes/) — the Scheme interpreter and C
  compiler that carries the bootstrap from stage0 to tinycc.
