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
| tinycc (`tcc-mes`), native x86-64 | ✅ builds, runs, compiles and links working programs |
| mes C library rebuilt by tinycc | ✅ |
| mescc-tools-extra and a `kaem_run` rule | ✅ |
| tinycc self-rebuild chain (boot0…bootstrappable) | ⚠️ builds, but `tcc-boot0` segfaults; see below |
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
tcc version 0.9.28-mes (x86_64 Linux)

$ bazel run //tools/tcc/tests:hello
hello from tcc
```

Those binaries are statically linked x86-64 ELF executables whose only
untrusted input is the hex0 seed, and `tcc-mes` emits x86-64 objects — it is a
native compiler, not a cross compiler. `//tools/tcc/tests:hello` is the
strongest statement the chain currently makes: a C program using `malloc` and
stdio, compiled and linked by tinycc against a C library tinycc itself built.

### Where it currently stops

The self-rebuild chain in `tools/tcc/BUILD.bazel` is written but does not
work, and is tagged `manual` so `//...` stays green. `tcc-boot0` links and
answers `-v`, but segfaults on every compile. The library it links against is
not at fault: the same library and the same `tcc-mes` produce the working
`hello` above. So the defect is in how `tcc-mes` compiles tinycc's own source,
and bisecting the `HAVE_*` feature flags is the obvious next move.

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

1. **Fix the self-rebuild chain**, described above. Everything it needs is
   already in place: the staged source, the flags for all five stages, the
   library rebuild, and the `kaem_run` rule that drives it.
2. **The utility packages**, in nixpkgs' order: musl, gnumake, gnused,
   gnugrep, gawk, gnutar, gzip, bzip2, gnupatch, diffutils, findutils,
   coreutils, heirloom, bash, binutils, bison, gnum4, xz, zlib. Each is a
   `kaem_run` over `./configure && make`, so the shape is already settled.
3. **GCC 4.6 (C, then C++) → GCC 10.4**, with GMP, MPFR and MPC.

The 29-package list, versions, patches and configure flags are all pinned in
[nixpkgs' minimal-bootstrap](https://github.com/NixOS/nixpkgs/tree/master/pkgs/os-specific/linux/minimal-bootstrap),
so what remains is transcription plus debugging rather than research.

## References

- [stage0-posix](https://github.com/oriansj/stage0-posix) — the reference
  bootstrap this repository mirrors.
- [live-bootstrap parts.rst](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst)
  — the clearest description of what each tool in the chain does.
- [GNU Mes](https://www.gnu.org/software/mes/) — the Scheme interpreter and C
  compiler that carries the bootstrap from stage0 to tinycc.
