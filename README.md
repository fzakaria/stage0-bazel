# Stage0 in Bazel

## Introduction

This project aims to reproduce the [Stage0](https://github.com/oriansj/stage0) compiler bootstrap process using [Bazel](https://bazel.build/) as the build system. The ultimate goal is to build a fully hermetic [GCC](https://gcc.gnu.org/) (GNU Compiler Collection) compiler starting from the minimal Stage0 hex2 seed and use that for a `cc_toolchain`

## What is Stage0?

The **Stage0** project is an initiative to create a trustworthy and minimal compiler bootstrap path starting from virtually nothing—a tiny seed program represented in hexadecimal code (the **hex2 seed**).

This seed is a simple, human-inspectable binary that serves as the foundational starting point for building up a complete compiler toolchain from scratch.