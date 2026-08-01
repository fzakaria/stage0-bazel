"""The C/C++ toolchain configuration for the bootstrapped clang.

The same shape as cc_toolchain_config.bzl and for the same reasons -- every
tool is a build artifact, so nothing can be named by a path written down in a
BUILD file -- but the compiler is clang rather than GCC, and three things
follow from that.

clang is one driver for both languages. It decides C from C++ by the file
name, so unlike GCC there is no second binary to name; the split that
cc_toolchain_config.bzl has to make between gcc and g++ does not arise here.

clang carries its own headers. stddef.h, stdarg.h and the rest of what
belongs to a compiler rather than to a libc come from clang's staging
directory, not from GCC's. The C++ library headers still come from GCC,
because libstdc++ is the C++ runtime this toolchain ships -- libc++ would be
another LLVM build and another decision.

The runtime is GCC's. --rtlib=libgcc says so, and it is deliberate:
compiler-rt would be a third LLVM build to get exactly the builtins that
libgcc.a already has.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "action_config",
    "feature",
    "flag_group",
    "flag_set",
    "tool",
    "variable_with_value",
)

_TARGET = "x86_64-unknown-linux-gnu"

# Where clang's own headers sit inside the staged tree the overlay builds.
# See builtin_headers_gen in LLVM's clang/BUILD.bazel.
_RESOURCE_INCLUDE = "/staging/include/"

_C_COMPILE_ACTIONS = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
]

_CXX_COMPILE_ACTIONS = [
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.clif_match,
]

_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

def _resource_include_directory(ctx):
    """Returns the directory holding clang's own headers.

    The genrule that stages them declares one output per header rather than a
    directory, so the directory has to be recovered from a path. Every one of
    them is under the same .../staging/include/ prefix.

    Args:
        ctx: The rule context.

    Returns:
        The path of clang's resource include directory.
    """
    for f in ctx.files.builtin_headers:
        index = f.path.find(_RESOURCE_INCLUDE)
        if index >= 0:
            return f.path[:index] + _RESOURCE_INCLUDE.rstrip("/")
    fail("no staged clang header is under %s; has the overlay's " % _RESOURCE_INCLUDE +
         "builtin_headers_gen changed shape?")

def _impl(ctx):
    gcc_tree = ctx.file.gcc_tree
    musl_tree = ctx.file.musl_tree
    binutils_tree = ctx.file.binutils_tree
    gcc_version = ctx.attr.gcc_version
    gcc_lib = "%s/lib/gcc/%s/%s" % (gcc_tree.path, _TARGET, gcc_version)

    # The directory holding ld.lld, which clang searches for a linker on its
    # -B prefixes once -fuse-ld=lld names one.
    lld_dir = ctx.file.lld.dirname

    resource_include = _resource_include_directory(ctx)

    # libstdc++'s headers, which only a C++ translation unit sees.
    cxx_include_directories = [
        "%s/include/c++/%s" % (gcc_tree.path, gcc_version),
        "%s/include/c++/%s/%s" % (gcc_tree.path, gcc_version, _TARGET),
        "%s/include/c++/%s/backward" % (gcc_tree.path, gcc_version),
    ]

    # clang's own headers, then musl's.
    c_include_directories = [
        resource_include,
        "%s/include" % musl_tree.path,
        # The kernel's own interface; see //tools/pkg/linux-headers.
        "%s/include" % ctx.file.linux_headers_tree.path,
    ]

    include_directories = cxx_include_directories + c_include_directories

    def include_flags(directories):
        return [
            flag
            for directory in directories
            for flag in ("-isystem", directory)
        ]

    # -nostdinc drops everything clang would look for on its own, including
    # the resource directory it locates relative to its own binary -- which is
    # not where the staged headers are.
    c_compile_flags = ["-nostdinc"] + include_flags(c_include_directories)

    cxx_compile_flags = ["-nostdinc"] + include_flags(include_directories)

    link_flags = [
        # musl here is static only, and there is no dynamic loader for a
        # program to name.
        "-static",
        # lld, found as ld.lld on the -B prefix below.
        "-fuse-ld=lld",
        "-B" + lld_dir,
        # GCC's libgcc.a rather than compiler-rt: it already provides the
        # builtins, and building compiler-rt would be another LLVM pass for
        # nothing.
        "--rtlib=libgcc",
        # The startup files. crt1.o, crti.o and crtn.o are musl's;
        # crtbegin.o and crtend.o are GCC's. A startup file is looked for by
        # name on the startfile prefixes, so these have to be -B and not -L.
        "-B" + musl_tree.path + "/lib",
        "-B" + gcc_lib,
        "-L" + musl_tree.path + "/lib",
        "-L" + gcc_tree.path + "/lib64",
        "-L" + gcc_lib,
    ]

    # libstdc++ is self-contained here; the GCC packages merge the libsupc++
    # objects into it at install. See //tools/pkg/gcc:defs.bzl.
    link_libs = [
        "-lstdc++",
        "-lm",
    ]

    features = [
        feature(
            name = "default_compile_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = _C_COMPILE_ACTIONS,
                    flag_groups = [flag_group(flags = c_compile_flags)],
                ),
                flag_set(
                    actions = _CXX_COMPILE_ACTIONS,
                    flag_groups = [flag_group(flags = cxx_compile_flags)],
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
        # Ordered after the object files rather than before them; an archive
        # only satisfies references the linker has already seen.
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
        feature(
            name = "archiver_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = [ACTION_NAMES.cpp_link_static_library],
                    flag_groups = [
                        flag_group(
                            flags = ["rcsD", "%{output_execpath}"],
                            expand_if_available = "output_execpath",
                        ),
                        flag_group(
                            iterate_over = "libraries_to_link",
                            expand_if_available = "libraries_to_link",
                            flag_groups = [
                                flag_group(
                                    flags = ["%{libraries_to_link.name}"],
                                    expand_if_equal = variable_with_value(
                                        name = "libraries_to_link.type",
                                        value = "object_file",
                                    ),
                                ),
                                flag_group(
                                    flags = ["%{libraries_to_link.object_files}"],
                                    iterate_over = "libraries_to_link.object_files",
                                    expand_if_equal = variable_with_value(
                                        name = "libraries_to_link.type",
                                        value = "object_file_group",
                                    ),
                                ),
                            ],
                        ),
                    ],
                ),
            ],
        ),
        feature(name = "supports_start_end_lib", enabled = False),
        feature(name = "supports_dynamic_linker", enabled = False),
    ]

    # One driver for every action. clang assembles with its own integrated
    # assembler, so binutils' `as` is not named here the way it is for GCC.
    action_configs = [
        action_config(
            action_name = name,
            enabled = True,
            tools = [tool(tool = ctx.file.clang)],
        )
        for name in _C_COMPILE_ACTIONS + _CXX_COMPILE_ACTIONS + _LINK_ACTIONS
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
        toolchain_identifier = "stage0-clang-%s" % ctx.attr.clang_version,
        host_system_name = _TARGET,
        target_system_name = _TARGET,
        target_cpu = "k8",
        target_libc = "musl",
        compiler = "clang",
        abi_version = "clang-%s" % ctx.attr.clang_version,
        abi_libc_version = "musl",
        cxx_builtin_include_directories = include_directories,
        features = features,
        action_configs = action_configs,
    )

stage0_clang_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "clang": attr.label(
            allow_single_file = True,
            mandatory = True,
            # Built for the execution platform, which does not carry the
            # clang_backend constraint, so these resolve to the GCC toolchain
            # that built them. Left in the target configuration they would
            # need a cc_toolchain that needs them. See //toolchain:cc_backend.
            cfg = "exec",
            doc = "The clang driver, which compiles both languages and links.",
        ),
        "clang_version": attr.string(
            mandatory = True,
            doc = "The compiler's version, for the toolchain identifier.",
        ),
        "lld": attr.label(
            allow_single_file = True,
            mandatory = True,
            # Built for the execution platform, which does not carry the
            # clang_backend constraint, so these resolve to the GCC toolchain
            # that built them. Left in the target configuration they would
            # need a cc_toolchain that needs them. See //toolchain:cc_backend.
            cfg = "exec",
            doc = "lld, named ld.lld so that -fuse-ld=lld finds it.",
        ),
        "builtin_headers": attr.label(
            allow_files = True,
            mandatory = True,
            # Generated by clang-tblgen in part, so exec for the same reason.
            cfg = "exec",
            doc = "clang's own headers, staged by the overlay's genrule.",
        ),
        "gcc_tree": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "The GCC tree, for libstdc++'s headers and libgcc.a.",
        ),
        "gcc_version": attr.string(
            mandatory = True,
            doc = "That GCC's version, which names directories inside it.",
        ),
        "musl_tree": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "The installed musl tree the compiler links against.",
        ),
        "linux_headers_tree": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "The kernel's userspace API headers, which musl does not" +
                  " ship and which anything touching the kernel needs.",
        ),
        "binutils_tree": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "The installed binutils tree, for ar and strip.",
        ),
        "ar": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "The archiver, which builds a cc_library's .a.",
        ),
        "strip": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "The stripper, for a build that asks for stripped output.",
        ),
    },
    provides = [CcToolchainConfigInfo],
    doc = "Configures a cc_toolchain around the clang this repository builds.",
)

def _exec_files_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.srcs))]

exec_files = rule(
    implementation = _exec_files_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            cfg = "exec",
            doc = "The files to collect, built for the execution platform.",
        ),
    },
    doc = "Collects files the way a filegroup does, but in the execution" +
          " configuration.\n\ncc_toolchain keeps its all_files in the target" +
          " configuration, and for this toolchain that is a cycle: the target" +
          " platform is the one carrying the clang_backend constraint, so" +
          " staging clang and lld there means building them with themselves." +
          " Everything the toolchain runs is a host tool and belongs in the" +
          " execution configuration anyway; this is also the configuration" +
          " stage0_clang_toolchain_config computes its paths in, and the two" +
          " have to agree or the compiler is handed paths to files that were" +
          " never staged.",
)
