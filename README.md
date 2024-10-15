# Stage0 in Bazel

## Introduction

This project aims to reproduce the [Stage0](https://github.com/oriansj/stage0) compiler bootstrap process using [Bazel](https://bazel.build/) as the build system. The ultimate goal is to build a fully hermetic [GCC](https://gcc.gnu.org/) (GNU Compiler Collection) compiler starting from the minimal Stage0 hex2 seed and use that for a `cc_toolchain`

## What is Stage0?

The **Stage0** project is an initiative to create a trustworthy and minimal compiler bootstrap path starting from virtually nothing—a tiny seed program represented in hexadecimal code (the **hex2 seed**).

This seed is a simple, human-inspectable binary that serves as the foundational starting point for building up a complete compiler toolchain from scratch.

## How far am I ?

I am at _mes_ compiler.

```console
>  MES_DEBUG=2 bazel run //tools/mes:mes-m2 -- --help
INFO: Analyzed target //tools/mes:mes-m2 (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //tools/mes:mes-m2 up-to-date:
  bazel-bin/tools/mes/mes-m2
INFO: Elapsed time: 0.054s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/tools/mes/mes-m2 --help
mes: reading boot-0 [${srcdest}mes]: mes/module/mes/boot-0.scm
mes: reading boot-0 [<boot>]: boot-0.scm
mes: boot failed: no such file: boot-0.scm
```

> GNU Mes is a Scheme interpreter and C compiler for bootstrapping the GNU System. It has helped to decimate the number and size of binary seeds that were used in the bootstrap of GNU Guix 1.0. Recently, version 0.24.2 has realized the first Full Source Bootstrap for Guix. The final goal is to help create a full source bootstrap as part of the bootstrappable builds effort for any UNIX-like operating system.

A really good description of all the tools can be found [here](https://github.com/fosslinux/live-bootstrap/blob/1f272f90504871ed5b39af4ae2c7c9aed8a56dbb/parts.rst).