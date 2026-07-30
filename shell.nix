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
  shellHook = ''
    export BAZELISK_HOME="''${BAZELISK_HOME:-$PWD/.bazelisk}"
    export JAVA_HOME="${pkgs.jdk21}"
  '';
}
