# A module that uses the bootstrapped toolchain

This is the top-level README's claim, as something you can run:

```console
$ cd examples/consumer
$ bazel test //...
$ bazel run //:app
bazel=1 stage0=2
```

`MODULE.bazel` is four lines of substance — depend on the module, register
its toolchain — and `BUILD.bazel` is an ordinary `cc_library`, `cc_binary`
and `cc_test`. Nothing in either mentions the bootstrap.

It is a separate module rather than a directory of the outer one, and
deliberately so: it is the only thing that checks the paths and labels this
repository hands to a *consumer*, which is where a build that only ever ran
as the main repository goes wrong. Four such faults were found by running it.

The `local_path_override` in `MODULE.bazel` points at the checkout two
directories up, so the example tracks the repository it lives in. A real
consumer drops the override and takes the module from a registry.

The first build builds the whole bootstrap, which takes on the order of
twenty minutes.
