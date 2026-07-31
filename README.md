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
| GCC 10.4.0, built by 4.6 | ✅ C++17 |
| musl a fourth time, compiled by GCC 10 | ✅ |
| A registered `cc_toolchain` | ✅ `cc_binary`, `cc_library` and `cc_test` work |
| clang 22.1.8 and lld, built by GCC 10 | ✅ a second `cc_toolchain` |

The chain ends in a C++ compiler, and ordinary Bazel rules use it:

```console
$ bazel test //...
//toolchain/tests:greeting_test                                 PASSED
//toolchain/tests:hello_test                                    PASSED
//tools/pkg/gcc:gcc_version_test                                PASSED
//tools/pkg/gcc/cxx:gcc_cxx_version_test                        PASSED
//tools/pkg/gcc/latest:gcc_latest_version_test                  PASSED
//toolchain/tests:cxx17_test                                    PASSED
... 43 tests, all passing

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

GCC 10.4.0 and musl 1.2.6, built in this order:

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
6. GCC 10.4.0, built by that C++ compiler. GCC has needed a C++ compiler to
   build itself since 4.8, and 10.4 asks only for C++98 — GCC 11 raises that
   to C++11, which 4.6 does not have, so 10.4 is as far as this ladder
   reaches in one step. 10.5 is not usable: it miscompiles under 4.6
   ([PR 110716](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=110716)).
7. musl a fourth time, compiled by GCC 10, so the C library a program links
   against was built by the compiler that compiles it.

Version numbers, patches and configure flags are nixpkgs'
[minimal-bootstrap](https://github.com/NixOS/nixpkgs/tree/master/pkgs/os-specific/linux/minimal-bootstrap),
with one deliberate departure: everything here is linked statically. nixpkgs
points the compiler at musl's dynamic loader, and there is no shared musl in
this repository to load.

### What C++ this is

C++17. `toolchain/tests/cxx17.cc` is built through the registered toolchain
and uses structured bindings, `if constexpr`, a fold expression,
`std::optional` and `std::string_view` — none of which GCC 4.6 can compile,
so the test fails to build rather than fails to run if the toolchain is ever
pointed back at it.

GCC 10 defaults to `gnu++14`, so ask for `-std=c++17` in `copts` when you
want it.

### clang

The chain does not stop at GCC. `//toolchain:clang` is a second
`cc_toolchain` driven by clang 22.1.8 and lld 22.1.8, both built by the
GCC 10 above. The `.comment` section of anything it produces is the whole
ladder in three lines:

```console
$ readelf -p .comment bazel-bin/toolchain/tests/cxx17
  GCC: (GNU) 10.4.0
  clang version 22.1.8
  Linker: LLD 22.1.8
```

LLVM is consumed through `utils/bazel`, which upstream does not publish to
the registry, so `MODULE.bazel` fetches the source and lets `llvm_configure`
overlay the BUILD files onto it. Four patches travel with it, each for one
reason: no Python interpreter, no glibc, a version string that reads
`22.1.8None` in a release tarball, and a zlib-ng that cannot be included with
angle brackets. compiler-rt is not built -- `libgcc.a` already has the
builtins -- and neither is libc++, so the C++ runtime is still libstdc++.

It is not registered by default and cannot be: GCC is what builds clang, so a
clang toolchain that also applied to the tools being built for the host would
depend on itself. Ask for it explicitly:

```console
$ bazel build --config=llvm \
    --extra_toolchains=//toolchain:clang \
    --platforms=//toolchain:clang_platform \
    //toolchain/tests:cxx17
```

`--config=llvm` carries the flags LLVM's own `.bazelrc` would have supplied,
and `--config=remote` adds BuildBuddy: LLVM is an ordinary Bazel build of an
ordinary C++ project and takes well to remote execution, where the bootstrap
does not and is pinned local. See `tools/stage0/exec.bzl`.

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
     36 checked in to this repository
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
the musl this ships has no shared objects. And the compiler is GCC 10.4, which
defaults to `gnu++14`; add `-std=c++17` with `copts` if you want it.

Building your first target builds the whole bootstrap -- the seed through to
GCC 10 -- which takes on the order of fifteen minutes on a sixteen-core
machine and is cached afterwards. The long builds run `make -j`; see
MAKE_JOBS in `tools/stage0/kaem.bzl` if that number needs changing.

`examples/consumer` is exactly the above as a runnable module — its own
`MODULE.bazel`, a `cc_library`, a `cc_binary` and a `cc_test` — and it is
worth running rather than only reading. It is the only thing that exercises
the paths and labels this repository hands to a *consumer*, which is where a
build that has only ever run as the main repository goes wrong; six such
faults were found by running it.

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

The chain reaches a C++17 compiler. What is left is mostly about making it a
compiler more people would reach for.

1. **The toolchain's rough edges.** Neither toolchain declares dynamic
   linking, `--start-lib`, module maps or separate debug info. None of these
   is hard, and each is a small, testable change.
2. **The genrule shell.** It is the one host program either audit still
   names, and only because Bazel takes a genrule's shell as an absolute
   system path -- `sh_toolchain`'s `path` is a string, and the shell is not a
   declared input, so it cannot be a build artifact. Replacing the eight
   genrules on the path to clang with rules that name the bootstrapped bash
   would close it.
3. **A `.bazelrc`-free consumer.** A depending module currently wants
   `--incompatible_enable_cc_toolchain_resolution`, which is the default in
   recent Bazel but is set explicitly here, and `--test_env=PATH` so that
   Bazel's own test runner can find a shell.
4. **More of the utility set**: gnutar, bison, flex. Nothing in the chain
   needs them today -- GCC's tar and flex rules are worked around rather than
   satisfied -- but a package added later probably will.

## References

- [stage0-posix](https://github.com/oriansj/stage0-posix) — the reference
  bootstrap this repository mirrors.
- [live-bootstrap parts.rst](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst)
  — the clearest description of what each tool in the chain does.
- [GNU Mes](https://www.gnu.org/software/mes/) — the Scheme interpreter and C
  compiler that carries the bootstrap from stage0 to tinycc.
