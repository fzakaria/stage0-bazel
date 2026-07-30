"""One stage of the tinycc self-rebuild chain.

A stage is a compiler plus the C library that compiler produced. The next
stage builds itself with them, so each stage can enable language features the
one before it could not compile: bitfields, then floats, then setjmp.

The sequence and its flags come from nixpkgs' minimal-bootstrap
tinycc/bootstrappable.nix, which follows live-bootstrap's tcc-0.9.26 step.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//tools/stage0:kaem.bzl", "kaem_run")
load("//tools/stage0:files.bzl", "tool_dir")
load("//tools/stage0:tcc.bzl", "tcc_binary")

# The C standard the mes library is written against.
_LIBC_STD = "-std=c11"

def _library_script(cflags, libtcc_flags, with_prev_libs, libtcc_names):
    """Writes the kaem script that rebuilds the C library.

    Compiling into the working directory and archiving from there is what
    upstream does; kaem has no way to name a temporary file, and the working
    directory is per-action under a sandbox.

    Args:
        cflags: Flags for the library proper, as a list of strings.
        libtcc_flags: Flags for libtcc1, which needs the target definitions.
        with_prev_libs: Whether to point tinycc at the previous stage's -B
            directory. The first stage has none, because it is creating it.
        libtcc_names: Script variable names holding the libtcc1 sources.

    Returns:
        The script, as a list of lines.
    """
    prefix = "tcc"
    if with_prev_libs:
        prefix = "tcc -B ${prev_libs}"

    common = prefix + " " + " ".join(cflags)
    libtcc = prefix + " " + " ".join(libtcc_flags)

    return [
        "# Rebuild the mes C library with the tinycc from this stage.",
        "mkdir -p ${out}",
        "",
        "# crt1 starts the program; crti and crtn bracket .init and .fini.",
        common + " -c -o ${out}/crt1.o ${crt_dir}/crt1.c",
        common + " -c -o ${out}/crti.o ${crt_dir}/crti.c",
        common + " -c -o ${out}/crtn.o ${crt_dir}/crtn.c",
        "",
        "# The library proper, as one translation unit.",
        common + " -c -o libc.o ${libc}",
        "tcc -ar cr ${out}/libc.a libc.o",
        "",
        "# The helper routines tinycc emits calls to. Which ones are needed",
        "# depends on the compiler: the bootstrappable fork calls out to",
        "# va_list.c for variadic arguments, current tinycc handles those",
        "# itself but needs alloca.",
    ] + [
        libtcc + " -c -o %s.o ${%s}" % (name, name)
        for name in libtcc_names
    ] + [
        "tcc -ar cr ${out}/libtcc1.a " + " ".join([n + ".o" for n in libtcc_names]),
        "",
        "# getopt, wanted by several packages built later.",
        common + " -c -o libgetopt.o ${getopt}",
        "tcc -ar cr ${out}/libgetopt.a libgetopt.o",
        "",
    ]

def tcc_libraries(
        name,
        tcc,
        mes_headers,
        prev_libs = None,
        libtcc_defines = [],
        tcc_include = "//tools/tcc:src_include_dir",
        tcc_src = "//tools/tcc:src",
        libtcc_srcs = {
            "libtcc1": "@mes-m2//:lib/libtcc1.c",
            "va_list": "@tinycc//:lib/va_list.c",
        },
        tags = []):
    """Rebuilds the mes C library with a given tinycc.

    Args:
        name: Name of the resulting directory target.
        tcc: The compiler to build with.
        mes_headers: Target providing the mes headers; its root becomes -I.
        prev_libs: The previous stage's library directory, if there is one.
        libtcc_defines: Extra -D flags for libtcc1, which needs to know the
            target it is generating helpers for.
        tcc_include: The include directory of the tinycc doing the building.
            Its stdarg.h has to match its own calling convention, so this
            follows the compiler rather than being fixed.
        tcc_src: The source tree those headers belong to, staged as inputs.
        libtcc_srcs: Script variable name to source label, for the helper
            routines tinycc emits calls to.
        tags: Tags for the resulting target.
    """
    # The arch headers come first: mes source includes <arch/syscall.h> and
    # expects the build to have selected a target for it.
    cflags = [
        _LIBC_STD,
        "-I",
        "${tcc_include}",
        "-I",
        "${mes_arch_include}",
        "-I",
        "${mes_include}",
    ]
    libtcc_flags = cflags + ["-D " + d for d in libtcc_defines]

    write_file(
        name = name + "_script",
        out = name + ".kaem",
        content = _library_script(
            cflags,
            libtcc_flags,
            prev_libs != None,
            sorted(libtcc_srcs.keys()),
        ),
        tags = tags,
    )

    tool_dir(
        name = name + "_tools",
        tools = {"tcc": tcc},
        tags = tags,
    )

    substitutions = {
        "libc": "//tools/mes/mes-libc:libc.c",
        "getopt": "@mes-m2//:lib/posix/getopt.c",
    }
    substitutions.update(libtcc_srcs)
    directory_substitutions = {
        "crt_dir": "//tools/mes/mes-libc:crt",
        "tcc_include": tcc_include,
        "mes_include": mes_headers,
        "mes_arch_include": "//tools/mes:arch_include_dir",
    }
    if prev_libs != None:
        directory_substitutions["prev_libs"] = prev_libs

    kaem_run(
        name = name,
        script = name + ".kaem",
        # The marker only names the directory; the headers themselves have to
        # be staged too, or tinycc silently falls through to mes's stdarg.h
        # and every variadic function in the library reads its arguments from
        # the wrong place.
        srcs = [
            tcc_src,
            "//tools/mes:arch_headers",
            "//tools/mes:header_dir",
        ],
        substitutions = substitutions,
        directory_substitutions = directory_substitutions,
        tools = [
            name + "_tools",
            "//tools/mescc-tools-extra:bin",
        ],
        tags = tags,
    )

# What every stage compiles tinycc with. The paths are the ones the compiler
# being built will use later; the flags describing how to build it come from
# the stage's own `defines`.
_COMMON_DEFINES = [
    "BOOTSTRAP=1",
    "ONE_SOURCE=1",
    "TCC_TARGET_X86_64=1",
    "CONFIG_TCCBOOT=1",
    "CONFIG_TCC_STATIC=1",
    "CONFIG_USE_LIBGCC=1",
    "TCC_MES_LIBC=1",
    "CONFIG_TCCDIR=\"\"",
    "CONFIG_SYSROOT=\"\"",
    "CONFIG_TCC_CRTPREFIX=\"{B}\"",
    "CONFIG_TCC_ELFINTERP=\"\"",
    "CONFIG_TCC_LIBPATHS=\"{B}\"",
    "TCC_LIBGCC=\"libc.a\"",
    "TCC_LIBTCC1=\"libtcc1.a\"",
    "TCC_VERSION=\"0.9.28-mes\"",
]

def tcc_stage(
        name,
        prev,
        prev_libs,
        src,
        src_dir_marker,
        defines,
        libtcc_defines,
        mes_headers,
        tags = []):
    """Builds one tinycc, then rebuilds the C library with it.

    Args:
        name: Base name; the compiler is `name` and the libraries `name_libs`.
        prev: The tinycc that compiles this stage.
        prev_libs: The library directory `prev` links against.
        src: The staged tinycc source tree.
        src_dir_marker: A file sitting directly in that tree's root.
        defines: Language features this stage may use, as -D flags.
        libtcc_defines: -D flags for libtcc1 when rebuilding the library.
        mes_headers: Target providing the mes headers.
        tags: Tags for both targets of the stage.
    """
    tcc_binary(
        name = name,
        srcs = [src, "//tools/mes:arch_headers", "//tools/mes:header_dir"],
        main = "src/tcc.c",
        defines = _COMMON_DEFINES + defines,
        include_dir_markers = [
            "//tools/tcc:src/include/TCC_INCLUDEDIR",
            src_dir_marker,
            # The compiler doing the building needs the mes headers on its
            # own include path; what gets baked into the compiler being built
            # is set separately by sysinclude_dirs.
            "//tools/mes:include/MESCC_INCLUDEDIR",
            "//tools/mes:headers/include/MES_INCLUDEDIR",
        ],
        # What the compiler being built will search when nobody passes -I.
        # tinycc's own headers first, for the same reason they come first
        # above.
        sysinclude_dirs = [
            "//tools/tcc:src_include_dir",
            mes_headers,
        ],
        libs = prev_libs,
        tcc = prev,
        tags = tags,
    )

    tcc_libraries(
        name = name + "_libs",
        tcc = ":" + name,
        prev_libs = prev_libs,
        libtcc_defines = libtcc_defines,
        mes_headers = mes_headers,
        tags = tags,
    )
