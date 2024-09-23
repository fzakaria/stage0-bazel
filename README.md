# Stage0 in Bazel

## Introduction

This project aims to reproduce the [Stage0](https://github.com/oriansj/stage0) compiler bootstrap process using [Bazel](https://bazel.build/) as the build system. The ultimate goal is to build a fully hermetic [GCC](https://gcc.gnu.org/) (GNU Compiler Collection) compiler starting from the minimal Stage0 hex2 seed and use that for a `cc_toolchain`

## What is Stage0?

The **Stage0** project is an initiative to create a trustworthy and minimal compiler bootstrap path starting from virtually nothing—a tiny seed program represented in hexadecimal code (the **hex2 seed**).

This seed is a simple, human-inspectable binary that serves as the foundational starting point for building up a complete compiler toolchain from scratch.

## How far am I ?

I am at _bloodelf_ or [Phase 7](https://github.com/oriansj/stage0-posix-x86/blob/master/mescc-tools-mini-kaem.kaem#L118) if you are following along there.

```console
> bazel run //tools/stage0/phase6:blood-elf-0 -- --help
INFO: Analyzed target //tools/stage3:blood-elf-0 (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //tools/stage3:blood-elf-0 up-to-date:
  bazel-bin/tools/stage3/blood-elf-0.bin
INFO: Elapsed time: 0.079s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/tools/stage3/blood-elf-0.bin --help
Usage: /home/fmzakari/.cache/bazel/_bazel_fmzakari/560838ef110f58094fd2796f2375f63a/execroot/__main__/bazel-out/k8-fastbuild/bin/tools/stage3/blood-elf-0.bin --file FILENAME1 {--file FILENAME2} --output FILENAME
```

A really good description of all the tools can be found [here](https://github.com/fosslinux/live-bootstrap/blob/1f272f90504871ed5b39af4ae2c7c9aed8a56dbb/parts.rst).