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
| tinycc (`tcc-mes`), native x86-64 | ✅ |
| tinycc self-rebuild chain, then current tinycc (seven stages) | ✅ self-hosted |
| GNU patch, make, bash, coreutils, sed, grep, awk, gzip, diffutils | ✅ |
| musl, and tinycc rebuilt against it | ✅ |
| GNU binutils 2.46 | ✅ a real assembler and linker |
| GCC 4.6.4, C | ✅ |
| musl again, this time compiled by GCC | ✅ |
| GCC 4.6.4 with C++, and libstdc++ | ✅ |
| A registered `cc_toolchain` | ✅ `cc_binary`, `cc_library` and `cc_test` work |

The chain ends in a C++ compiler, and ordinary Bazel rules use it:

```console
$ bazel test //...
//toolchain/tests:greeting_test                                 PASSED
//toolchain/tests:hello_test                                    PASSED
//tools/pkg/gcc:gcc_version_test                                PASSED
//tools/pkg/gcc/cxx:gcc_cxx_version_test                        PASSED
... 38 tests, all passing

$ bazel run //toolchain/tests:hello
hello world
largest 11
caught largest of nothing
```

`toolchain/tests/hello.cc` is a plain `cc_binary`. It uses `std::vector`,
`std::string`, `std::sort`, iostreams, a template and a throw caught by
reference — the last of those is what proves the whole chain agrees, because
an exception crossing a function boundary needs the unwind tables the
compiler emitted, the assembler encoded and the linker merged. The result is
a static ELF executable with no `PT_INTERP`, and every program that produced
it descends from the 357-byte hex0 seed.

### What the compiler is

GCC 4.6.4 and musl 1.2.6, built in this order:

1. tinycc, seven stages deep, is the first compiler that can build a libc.
2. musl, compiled by tinycc twice — the first round because the mes-libc
   tinycc miscompiles long double arithmetic, so the libc it produces formats
   floating point wrongly, and the second by the tinycc that first round
   fixed.
3. binutils, then GCC 4.6.4 for C. 4.6 is the last release a compiler as
   limited as tinycc can build, which is why both reference bootstraps go
   through it.
4. musl a third time, compiled by GCC. The tinycc rounds are missing what
   tinycc could not build — the complex math, the hand-written x86-64 string
   and math routines — and a toolchain that ships a libc has to ship a whole
   one.
5. GCC 4.6.4 again with `--enable-languages=c,c++`, built by the C compiler
   from step 3 against the musl from step 4. tinycc cannot compile C++ at
   all, so a second GCC pass is how the chain acquires one.

Version numbers, patches and configure flags are nixpkgs'
[minimal-bootstrap](https://github.com/NixOS/nixpkgs/tree/master/pkgs/os-specific/linux/minimal-bootstrap),
with one deliberate departure: everything here is linked statically. nixpkgs
points the compiler at musl's dynamic loader, and there is no shared musl in
this repository to load.

### What C++ this is

GCC 4.6 is from 2011. It implements C++98 fully and the parts of C++0x that
existed at the time, which `-std=c++0x` selects; it is not a C++11 compiler
and it is nobody's idea of a modern one. It is the compiler this chain can
reach, and the next step is to use it to build a modern GCC — see
[Roadmap](#roadmap).

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

`//:attestation` states the whole claim as a build artifact: how many files
reaching an action were built here, how many came from a hash-pinned archive,
how many are checked in, and which binaries were taken on trust. Nothing falls
outside those categories, which is what "hermetic" means here — no input read
from the host, and no unpinned input. Both audits start from the C++ program,
so what they cover is the toolchain and everything under it:

```
2. Every file reaching an action came from one of three places:

     2467 built by this graph
     847 from a hash-pinned archive
     35 checked in to this repository
```

Two of those pinned files are worth naming, because they are shell scripts
rather than sources: `link_dynamic_library.sh` and `build_interface_so`, which
Bazel's own `cc_toolchain` rule attaches to every link action. This toolchain
declares no dynamic linking, so neither is ever run — and the trust report
below is what establishes that, because it checks the program each action
executes rather than what it merely has available.

Configuration can be overridden on the command line, so the enforcing check is
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

Depend on the module and register its toolchain. A registration made in one
module does not reach another, so this line has to be in your own
`MODULE.bazel`:

```starlark
bazel_dep(name = "stage0-bazel", version = "0.1.0")

register_toolchains("@stage0-bazel//toolchain:cc")
```

That is all. `cc_binary`, `cc_library` and `cc_test` then resolve to the
bootstrapped GCC, and nothing in your BUILD files mentions the bootstrap:

```starlark
cc_binary(
    name = "app",
    srcs = ["app.cc"],
)
```

Two things to know about the result. Programs are statically linked, because
the musl this ships has no shared objects. And the compiler is GCC 4.6, so
`-std=c++0x` is as new as the language gets; add it with `copts` if you want
it.

Building your first target builds the whole bootstrap, which takes on the
order of twenty minutes on a warm machine and is cached afterwards.

The lower-level tools are available under stable labels for anything that
wants them directly: `@stage0-bazel//:hex2`, `//:M1`, `//:blood-elf`,
`//:M2-Planet`, `//:M2-Mesoplanet`, `//:get_machine`, `//:kaem`, `//:mes`,
`//:tcc-mes` and `//:tcc`. mescc has rules of its own:

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

The chain reaches a working C++ compiler, but a 2011 one. What is left is
mostly about making it a compiler people would want to use.

1. **GCC 10.4**, built by the 4.6 that exists now. nixpkgs'
   minimal-bootstrap carries the recipe (`gcc/10.nix`) and it is the step
   that turns C++0x into C++17. It needs a C++98 compiler to build, which is
   exactly what step 5 above produced.
2. **The toolchain's rough edges.** `libstdc++.a` does not carry the
   libsupc++ objects, so the link line has to say `-lsupc++` explicitly; the
   toolchain declares no dynamic linking, no `--start-lib`, and no separate
   debug info. None of these is hard, and each is a small, testable change.
3. **A `.bazelrc`-free consumer.** A depending module currently wants
   `--incompatible_enable_cc_toolchain_resolution`, which is the default in
   recent Bazel but is set explicitly here.
4. **More of the utility set**: findutils, gnutar, bison, flex. Nothing in
   the chain needs them today -- GCC's tar and flex rules are worked around
   rather than satisfied -- but a package added later probably will.

## References

- [stage0-posix](https://github.com/oriansj/stage0-posix) — the reference
  bootstrap this repository mirrors.
- [live-bootstrap parts.rst](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst)
  — the clearest description of what each tool in the chain does.
- [GNU Mes](https://www.gnu.org/software/mes/) — the Scheme interpreter and C
  compiler that carries the bootstrap from stage0 to tinycc.
