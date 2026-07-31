"""The C/C++ toolchain configuration for the bootstrapped GCC.

Everything here exists because the compiler is a build artifact rather than
something installed on the machine. Its directories are only known once the
packages that produce them have been analysed, so the include paths, the
library paths and the -B prefixes cannot be written down in a BUILD file --
they are computed from the trees the toolchain depends on.

GCC is used from its installed tree. The driver finds cc1, cc1plus and
collect2 by searching its -B prefixes, so naming those directories is what
replaces the relative-to-argv[0] search a normally installed GCC does.

Nothing is looked for outside the trees named here: -nostdinc drops the
compiler's built-in include path, and every directory that replaces it is a
directory this repository built.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "action_config",
    "feature",
    "flag_group",
    "flag_set",
    "tool",
)

# The target triplet GCC was configured for, and its version. Both appear in
# the layout of the installed tree.
_TARGET = "x86_64-unknown-linux-gnu"

_GCC_VERSION = "4.6.4"

_GCC_TARGET_DIR = "%s/%s" % (_TARGET, _GCC_VERSION)

# Every action that runs the compiler on a source file, and every action that
# runs it to link. The driver is the same program for both.
_COMPILE_ACTIONS = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.clif_match,
]

_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

def _impl(ctx):
    # Every tool here is a build artifact, so its path is relative to the
    # execroot. Bazel resolves a tool path against the package holding the
    # cc_toolchain and then insists the result be normalized, so the two only
    # agree when that package is the root one -- climbing out with ../ is
    # rejected. Both the toolchain and this configuration therefore live in
    # //, and the paths below are used exactly as Bazel reports them.
    if ctx.label.package:
        fail("%s must be in the root package: a tool path is resolved " % ctx.label +
             "against it, and only there does an execroot-relative path " +
             "resolve to itself")

    gcc_tree = ctx.file.gcc_tree
    musl_tree = ctx.file.musl_tree
    binutils_tree = ctx.file.binutils_tree

    # Where the pieces of the installed GCC live.
    gcc_libexec = "%s/libexec/gcc/%s" % (gcc_tree.path, _GCC_TARGET_DIR)
    gcc_lib = "%s/lib/gcc/%s" % (gcc_tree.path, _GCC_TARGET_DIR)
    binutils_bin = "%s/bin" % binutils_tree.path

    # The include path, in the order the compiler should search it. These are
    # also what Bazel checks every #include against, so the two lists have to
    # be the same one.
    include_directories = [
        "%s/include/c++/%s" % (gcc_tree.path, _GCC_VERSION),
        "%s/include/c++/%s/%s" % (gcc_tree.path, _GCC_VERSION, _TARGET),
        "%s/include/c++/%s/backward" % (gcc_tree.path, _GCC_VERSION),
        "%s/include" % gcc_lib,
        "%s/include-fixed" % gcc_lib,
        "%s/include" % musl_tree.path,
    ]

    compile_flags = [
        # Drop the compiler's built-in include path. What it holds is a
        # directory inside the sandbox GCC was built in, which no longer
        # exists, and /include, which never did.
        "-nostdinc",
    ] + [
        flag
        for directory in include_directories
        for flag in ("-isystem", directory)
    ] + [
        # cc1 and cc1plus.
        "-B" + gcc_libexec,
        # The assembler.
        "-B" + binutils_bin,
    ]

    link_flags = [
        # musl here is static only, and there is no dynamic loader for a
        # program to name.
        "-static",
        # collect2, and the linker it drives.
        "-B" + gcc_libexec,
        "-B" + binutils_bin,
        # The startup files. crt1.o, crti.o and crtn.o are musl's; crtbeginT.o
        # and crtend.o are GCC's own. Both directories have to be -B rather
        # than -L, because a startup file is looked for by name on the
        # startfile prefixes and not on the library path.
        "-B" + musl_tree.path + "/lib",
        "-B" + gcc_lib,
        "-L" + musl_tree.path + "/lib",
        "-L" + gcc_tree.path + "/lib64",
        "-L" + gcc_lib,
    ]

    # The C++ runtime, named explicitly and in this order. libstdc++.a does
    # not carry the libsupc++ objects -- the exception machinery, the type
    # information and operator new -- so a link that only says -lstdc++ ends
    # with __cxa_throw undefined. -lsupc++ has to follow it rather than
    # precede it, because the members libstdc++ pulls in are what reference
    # those symbols.
    link_libs = [
        "-lstdc++",
        "-lsupc++",
        "-lm",
    ]

    features = [
        feature(
            name = "default_compile_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = _COMPILE_ACTIONS,
                    flag_groups = [flag_group(flags = compile_flags)],
                ),
            ],
        ),
        feature(
            name = "default_link_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = _LINK_ACTIONS,
                    flag_groups = [flag_group(flags = link_flags)],
                ),
            ],
        ),
        # A separate feature so that it can be ordered after the object files
        # rather than before them; an archive only satisfies references that
        # the linker has already seen.
        feature(
            name = "cpp_runtime",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = _LINK_ACTIONS,
                    flag_groups = [flag_group(flags = link_libs)],
                ),
            ],
        ),
        # Features Bazel looks for by name, declared so that cc_binary and
        # cc_library do not ask for behaviour this toolchain does not have.
        # static_link_cpp_runtimes is deliberately absent: it would have
        # Bazel put the C++ runtime on the link line itself, from a
        # static_runtime_lib the cc_toolchain would have to name, and the
        # cpp_runtime feature above already does it in the order that works.
        feature(name = "supports_start_end_lib", enabled = False),
        feature(name = "supports_dynamic_linker", enabled = False),
    ]

    # Which program runs each action, named by artifact rather than by path.
    #
    # A tool_path is the usual way to say this, and it cannot be used here: it
    # is resolved against the package holding the cc_toolchain, and the result
    # must be normalized. Every tool in this toolchain is a build artifact
    # under bazel-out/, and when this repository is a dependency the package
    # is external/<module>+ -- so the path would have to climb out with ../,
    # which Bazel rejects. An action_config names the File itself and leaves
    # Bazel to work out where it is.
    action_configs = [
        action_config(
            action_name = name,
            enabled = True,
            tools = [tool(tool = ctx.file.driver)],
        )
        for name in _COMPILE_ACTIONS + _LINK_ACTIONS
    ] + [
        action_config(
            action_name = ACTION_NAMES.cpp_link_static_library,
            enabled = True,
            tools = [tool(tool = ctx.file.ar)],
        ),
        action_config(
            action_name = ACTION_NAMES.strip,
            enabled = True,
            tools = [tool(tool = ctx.file.strip)],
        ),
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "stage0-gcc-%s" % _GCC_VERSION,
        host_system_name = _TARGET,
        target_system_name = _TARGET,
        target_cpu = "k8",
        target_libc = "musl",
        compiler = "gcc",
        abi_version = "gcc-%s" % _GCC_VERSION,
        abi_libc_version = "musl",
        cxx_builtin_include_directories = include_directories,
        features = features,
        action_configs = action_configs,
    )

stage0_cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "gcc_tree": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The installed GCC tree, as built by //tools/pkg/gcc/cxx.",
        ),
        "musl_tree": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The installed musl tree the compiler links against.",
        ),
        "binutils_tree": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The installed binutils tree holding as and ld.",
        ),
        "driver": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The g++ driver, extracted from the GCC tree as one file.",
        ),
        "ar": attr.label(allow_single_file = True, mandatory = True),
        "ld": attr.label(allow_single_file = True, mandatory = True),
        "nm": attr.label(allow_single_file = True, mandatory = True),
        "objdump": attr.label(allow_single_file = True, mandatory = True),
        "strip": attr.label(allow_single_file = True, mandatory = True),
    },
    provides = [CcToolchainConfigInfo],
    doc = "Configures a cc_toolchain around the GCC this repository builds.",
)
