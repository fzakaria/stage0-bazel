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
    "variable_with_value",
)

# The target triplet GCC was configured for. It appears in the layout of the
# installed tree, alongside the version, which is a rule attribute rather than
# a constant: this repository builds two GCCs now, and the toolchain has to be
# able to name either one.
_TARGET = "x86_64-unknown-linux-gnu"

# Compiling C and compiling C++ are separate here, and have to be.
#
# The driver decides the language from the file name, and g++ answers .c with
# C++. That is invisible while everything being built is C++, which it was
# until LLVM: llvm/lib/Support/regcomp.c is C, and C++ rejects the implicit
# void* conversions C allows --
#
#     regcomp.c:1183:18: error: invalid conversion from 'void*' to 'cset*'
#
# so a C source has to reach gcc rather than g++. The C++ standard headers
# are likewise only on the C++ include path; a C translation unit has no use
# for them and should not be able to reach one by accident.
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

_COMPILE_ACTIONS = _C_COMPILE_ACTIONS + _CXX_COMPILE_ACTIONS

_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

def _impl(ctx):
    gcc_tree = ctx.file.gcc_tree
    musl_tree = ctx.file.musl_tree
    binutils_tree = ctx.file.binutils_tree
    gcc_version = ctx.attr.gcc_version
    gcc_target_dir = "%s/%s" % (_TARGET, gcc_version)

    # Where the pieces of the installed GCC live.
    gcc_libexec = "%s/libexec/gcc/%s" % (gcc_tree.path, gcc_target_dir)
    gcc_lib = "%s/lib/gcc/%s" % (gcc_tree.path, gcc_target_dir)
    binutils_bin = "%s/bin" % binutils_tree.path

    # libstdc++'s headers, which only a C++ translation unit sees.
    cxx_include_directories = [
        "%s/include/c++/%s" % (gcc_tree.path, gcc_version),
        "%s/include/c++/%s/%s" % (gcc_tree.path, gcc_version, _TARGET),
        "%s/include/c++/%s/backward" % (gcc_tree.path, gcc_version),
    ]

    # The compiler's own headers -- stddef.h, stdarg.h and the rest that
    # belong to a compiler rather than to a libc -- and then musl's.
    c_include_directories = [
        "%s/include" % gcc_lib,
        "%s/include-fixed" % gcc_lib,
        "%s/include" % musl_tree.path,
    ]

    # What Bazel checks every #include against. It has no notion of a
    # per-language builtin include path, so this is the union.
    include_directories = cxx_include_directories + c_include_directories

    def include_flags(directories):
        return [
            flag
            for directory in directories
            for flag in ("-isystem", directory)
        ]

    # Common to both languages. -nostdinc drops the compiler's built-in
    # include path: what it holds is a directory inside the sandbox GCC was
    # built in, which no longer exists, and /include, which never did.
    base_compile_flags = [
        "-nostdinc",
    ] + include_flags(c_include_directories) + [
        # cc1 and cc1plus.
        "-B" + gcc_libexec,
        # The assembler.
        "-B" + binutils_bin,
    ]

    # The C++ headers come first, ahead of musl's, exactly as a normally
    # installed GCC orders them.
    cxx_compile_flags = [
        "-nostdinc",
    ] + include_flags(include_directories) + [
        "-B" + gcc_libexec,
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

    # The C++ runtime, named explicitly: Bazel's own way of adding it wants a
    # static_runtime_lib on the cc_toolchain, and this is a link line the
    # configuration already controls.
    #
    # -lsupc++ used to have to follow -lstdc++ here, because the libstdc++.a
    # these packages installed did not carry the libsupc++ objects and a link
    # saying only -lstdc++ ended with __cxa_throw undefined. The GCC packages
    # now merge the two archives at install time, the way a normally
    # configured GCC already does, so -lstdc++ is self-contained; see
    # MERGE_LIBSUPCXX_INTO_LIBSTDCXX in //tools/pkg/gcc:defs.bzl.
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
                    flag_groups = [flag_group(flags = base_compile_flags)],
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
        # What the archiver is told. Bazel supplies these itself for a
        # toolchain that does not name the archive action, but naming one --
        # which is the only way to point at an archiver that is a build
        # artifact -- replaces its version wholesale, flags included.
        feature(
            name = "archiver_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = [ACTION_NAMES.cpp_link_static_library],
                    flag_groups = [
                        flag_group(
                            # Replace rather than append, write an index, and
                            # zero the timestamps and uids so that the same
                            # objects give the same archive.
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
            tools = [tool(tool = ctx.file.c_driver)],
        )
        for name in _C_COMPILE_ACTIONS
    ] + [
        action_config(
            action_name = name,
            enabled = True,
            tools = [tool(tool = ctx.file.driver)],
        )
        for name in _CXX_COMPILE_ACTIONS + _LINK_ACTIONS
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
        toolchain_identifier = "stage0-gcc-%s" % gcc_version,
        host_system_name = _TARGET,
        target_system_name = _TARGET,
        target_cpu = "k8",
        target_libc = "musl",
        compiler = "gcc",
        abi_version = "gcc-%s" % gcc_version,
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
            doc = "The installed GCC tree, as built by //tools/pkg/gcc/latest.",
        ),
        "gcc_version": attr.string(
            mandatory = True,
            doc = "The compiler's version, which names directories inside the" +
                  " installed tree. Must match what gcc_tree actually is.",
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
            doc = "The g++ driver, which compiles C++ and links everything.",
        ),
        "c_driver": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The gcc driver. A C source compiled by g++ is compiled as" +
                  " C++, which rejects what C allows.",
        ),
        "ar": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The archiver, which builds a cc_library's .a.",
        ),
        "strip": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The stripper, for a build that asks for stripped output.",
        ),
    },
    provides = [CcToolchainConfigInfo],
    doc = "Configures a cc_toolchain around the GCC this repository builds.",
)
