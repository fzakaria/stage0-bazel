# Development shell for stage0-bazel.
#
# Deliberately minimal: the whole point of this repository is that the build
# does not consume a host C/C++ toolchain, so none is provided here. Only
# Bazel itself (via bazelisk, which honours .bazelversion) and the JDK Bazel
# needs to run are in scope.
{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  name = "stage0-bazel";

  packages = [
    pkgs.bazelisk
    pkgs.jdk21
  ];

  # bazelisk downloads the Bazel release named by .bazelversion into this
  # directory instead of $HOME, keeping the checkout self-contained.
  #
  # BAZEL_SH is the shell Bazel runs a genrule under. Nothing in the bootstrap
  # has a genrule -- every step of it runs a program this repository built --
  # but LLVM has eight, and a genrule's shell has to be an absolute system
  # path: sh_toolchain's `path` is a string rather than a label, and the shell
  # is not a declared input of the action, so a build artifact cannot serve.
  # Bazel's default is /bin/bash, which does not exist on NixOS.
  #
  # Setting it here rather than writing an absolute path into .bazelrc keeps
  # the value derived from this shell rather than from whatever the machine
  # happens to have. Note that Bazel reads BAZEL_SH when the server starts, so
  # changing it wants a `bazel shutdown` to take effect.
  shellHook = ''
    export BAZELISK_HOME="''${BAZELISK_HOME:-$PWD/.bazelisk}"
    export JAVA_HOME="${pkgs.jdk21}"
    export BAZEL_SH="${pkgs.bashInteractive}/bin/bash"
  '';
}
