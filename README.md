# Stage0 in Bazel

> Please see [my blog post](https://fzakaria.com/2026/07/31/a-c++-toolchain-from-357-bytes-in-bazel) to learn more about this project.
>
> I had hand-written the initial bootstrap stages but relied on an LLM
> to help me write the remainder of the stages. There is a verification
> step to validate that the code does not in fact rely on external tools.

Bootstrapping a LLVM compiler toolchain from [stage0](https://github.com/oriansj/stage0)
under [Bazel](https://bazel.build/), the way Nix and Guix do it, with the
bootstrap expressed as a build graph rather than as shell scripts.

The chain starts from **a single 357-byte** hand-auditable binary, the hex0 seed, and builds everything above it. No compiler, assembler or linker from the host
participates, and that claim is checked rather than asserted; see
[Verifying no host toolchain is used](#verifying-no-host-toolchain-is-used).

## Building with clang

`--config=clang` builds your target with clang 22.1.8 and lld, both of which
this repository built:

```console
$ bazel build --config=clang //toolchain/tests:cxx17
$ readelf -p .comment bazel-bin/toolchain/tests/cxx17
  GCC: (GNU) 10.4.0
  clang version 22.1.8
  Linker: LLD 22.1.8
```

Those three lines are the ladder: GCC 10.4.0 built clang, clang compiled the
program, lld linked it, and the GCC came out of the 357-byte seed.

The first build builds the whole chain — the seed through GCC 10, then LLVM —
which is hours, and is cached afterwards. `--config=remote` runs the LLVM part
on [BuildBuddy](https://buildbuddy.io/); see `.bazelrc` for why only that part.

There are two toolchains, and `--config=clang` picks the second one. GCC 10.4
is registered as the default because GCC is what builds clang, so clang cannot
be its own default without depending on itself. `--config=clang` switches the
target platform to `//toolchain:clang_platform`, which carries the constraint
only the clang toolchain matches. Without it you get GCC, which is a working
C++17 compiler in its own right.

## Using this as a Bazel module

```starlark
bazel_dep(name = "stage0-bazel", version = "XXX")

# clang first: resolution takes the first match, and the GCC toolchain
# matches everything.
register_toolchains(
    "@stage0-bazel//toolchain:clang",
    "@stage0-bazel//toolchain:cc",
)
```

A registration in one module does not reach another, so those lines have to be
in your own `MODULE.bazel`. `cc_binary`, `cc_library` and `cc_test` then work
as usual; nothing in your BUILD files mentions the bootstrap. Programs come out
statically linked, because the musl this ships has no shared objects.

`--config=clang` lives in this repository's `.bazelrc`, which a depending
module does not inherit. Copy the `build:llvm` and `build:clang` blocks out of
it into your own, or pass the flags directly.

`examples/consumer` is the smallest runnable version of the above.
`examples/absl` is the same against somebody else's code: Abseil and GoogleTest
straight from the Bazel Central Registry, unpatched.

## Stages

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
| GNU tar 1.35 and the Linux 6.5.6 UAPI headers | ✅ |
| Abseil and GoogleTest, unpatched from the registry | ✅ `examples/absl` |

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

Version numbers, patches and configure flags mimic nixpkgs'
[minimal-bootstrap](https://github.com/NixOS/nixpkgs/tree/master/pkgs/os-specific/linux/minimal-bootstrap),
with one deliberate departure: everything here is linked statically. nixpkgs points the compiler at musl's dynamic loader, and there is no shared musl in this repository to load.

## Verifying no host toolchain is used

Two mechanisms: one configured, one checked.

`.bazelrc` sets `BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1`, so Bazel does not
auto-detect a host C++ toolchain, and `--incompatible_strict_action_env`, so actions see a fixed `PATH` rather than the developer's.

Configuration can be overridden on the command line, so the enforcing check is
`//:trust-report`. It runs an aspect over every action reachable from the
bootstrap roots and inspects the program each one actually executes. Anything
not under `bazel-out/` fails analysis, so the report is produced only if the
claim holds. It is analysis-only — it does not build the compiler, and takes a
second:

```console
$ bazel build //:trust-report
$ cat bazel-bin/tools/verify/no_native_toolchain.report
Bootstrap trust report

Every action in the checked graph runs a program built by this
repository, except for these audited seed binaries:

external/+_repo_rules+hex0-seeds/POSIX/x86/hex0-seed
```

Test targets are exempt. Bazel's own test runner is a bash script, and the
audits themselves live in test targets; the exemption is confined to test
actions and does not extend to anything producing a build artifact.

`//:attestation` states the wider claim: how many files reaching an action were
built here, how many came from a hash-pinned archive, how many are checked in,
and which binaries were taken on trust. Nothing falls outside those categories,
which is what "hermetic" means here — no input read from the host, and no
unpinned input:

```console
$ bazel build //:attestation
$ cat bazel-bin/tools/verify/attestation.txt
Hermeticity attestation
=======================
...
2. Every file reaching an action came from one of three places:

     2502 built by this graph
     853 from a hash-pinned archive
     35 checked in to this repository
...
3. Binaries taken on trust rather than built from source:

     external/+_repo_rules+hex0-seeds/POSIX/x86/hex0-seed
```

Two of those pinned files are worth naming, because they are shell scripts
rather than sources: `link_dynamic_library.sh` and `build_interface_so`, which
Bazel's own `cc_toolchain` rule attaches to every link action. This toolchain
declares no dynamic linking, so neither is ever run — and the trust report is
what establishes that, because it checks the program each action executes
rather than what it merely has available.

`//:trust-report-llvm` holds the clang graph to the same standard. It is a
separate target for cost rather than principle: an audit's roots are real
dependencies, so folding the two would make every `bazel test //...` fetch a
250 MB archive and build a compiler.

```console
$ bazel build --config=llvm //:trust-report-llvm
$ cat bazel-bin/tools/verify/no_native_toolchain_llvm.report
...
external/+_repo_rules+hex0-seeds/POSIX/x86/hex0-seed
/nix/store/…/bin/bash
```

The shell is the second entry because Bazel takes a genrule's shell as an
absolute system path — `sh_toolchain`'s `path` is a string, and the shell is
not a declared input of the action, so no file this repository built can serve.
LLVM has eight genrules; the bootstrap proper has none.

## How the pieces fit

Each stage0 phase lives in its own package under `tools/stage0/phaseN`, and the rules that drive the tools live in `tools/stage0/*.bzl`.

From phase 7 onward every binary carries a blood-elf symbol footer and is linked against the debuggable ELF header, so `objdump` and `gdb` work on the intermediate tools. The footer is a 16-byte signature, a 32-byte SHA256 of the binary, and a 32-byte SHA256 of the debug info. The signature is `blood-elf`'s, and the hashes are checked by `get_machine` before it runs any tool.

mescc is not a single binary. It is a Scheme program interpreted by mes, it parses C with [nyacc](https://www.nongnu.org/nyacc/), and it spawns the stage0 `M1`, `hex2` and `blood-elf` tools to assemble and link.

The file formats are stage0's rather than the platform's. A mescc `.o` is a hex2 file, and an "archive" is those files concatenated, which is all upstream's `mesar` does.

## References

- [stage0-posix](https://github.com/oriansj/stage0-posix) — the reference
  bootstrap this repository mirrors.
- [live-bootstrap parts.rst](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst)
  — the clearest description of what each tool in the chain does.
- [GNU Mes](https://www.gnu.org/software/mes/) — the Scheme interpreter and C
  compiler that carries the bootstrap from stage0 to tinycc.
