"""Building an upstream source package with the bootstrapped tinycc.

Every package between tinycc and GCC has the same shape, which nixpkgs'
minimal-bootstrap makes explicit: unpack a tarball, write a `config.h` by hand
because ./configure cannot run yet, compile a known list of sources, link, and
install into a directory. `tcc_package` is that shape.

The scripts deliberately never `cd`. kaem has no way to name the working
directory, so every path a script uses is relative to the execroot; changing
directory would strand `${out}` and the tools. Unpacking leaves the source
tree under the execroot and the script addresses it by its prefix.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//tools/stage0:files.bzl", "tool_dir")
load("//tools/stage0:kaem.bzl", "kaem_run")

def _object_name(source):
    """Returns the object file name for a source path.

    Args:
        source: A source path relative to the unpacked tree.

    Returns:
        The base name with a .o suffix, matching what upstream's makefiles
        expect when they link.
    """
    base = source.split("/")[-1]
    if base.endswith(".c"):
        base = base[:-len(".c")]
    return base + ".o"

def _unpack_lines(prefix, compression):
    """Returns the script lines that unpack the source tarball.

    Args:
        prefix: The directory the tarball unpacks into.
        compression: "gz", "bz2" or "xz".

    Returns:
        A list of script lines.
    """
    decompressors = {
        "gz": "ungz",
        "bz2": "unbz2",
        "xz": "unxz",
    }
    if compression not in decompressors:
        fail("unknown compression %s" % compression)

    return [
        "# Unpack. untar extracts into the working directory, which is the",
        "# execroot, so the tree appears at %s." % prefix,
        "%s --file ${tarball} --output source.tar" % decompressors[compression],
        "untar --file source.tar",
        "",
    ]

def tcc_package(
        name,
        tarball,
        prefix,
        sources,
        binary,
        cflags = [],
        ldflags = [],
        configure = [],
        extra_setup = [],
        srcs = [],
        compression = "gz",
        check_argument = None,
        tcc = "//tools/tcc:tcc",
        tcc_libs = "//tools/tcc:tcc_libs",
        includes = [],
        tools = [],
        **kwargs):
    """Builds one upstream package with tinycc and installs its binary.

    Args:
        name: Target name; the output directory holds bin/<binary>.
        tarball: The source archive.
        prefix: The directory the archive unpacks into.
        sources: C sources to compile, relative to `prefix`.
        binary: Name of the program to link and install.
        cflags: Compiler flags, including the -D set that stands in for
            ./configure output.
        ldflags: Extra flags for the link step.
        configure: Script lines run before compiling, for the file shuffling
            upstream's ./configure would otherwise do.
        extra_setup: Script lines run immediately after unpacking.
        srcs: Additional files the script reads.
        compression: Archive compression: "gz", "bz2" or "xz".
        check_argument: Argument used to smoke-test the program in the script;
            omit when the program exits non-zero for it.
        tcc: The tinycc to build with.
        tcc_libs: That compiler's library directory.
        includes: Additional -I directories, as script variable references.
        tools: Extra tool directories to put on PATH.
        **kwargs: Passed through to the underlying kaem_run.
    """
    # tinycc knows where its own headers live, but only because those paths
    # were baked in when it was built; the directories still have to be staged
    # into the action. Naming them explicitly makes that dependency visible
    # and fixes the search order at the same time.
    compile_prefix = " ".join(
        [
            "tcc",
            "-B",
            "${tcc_libs}",
            "-I",
            "${tcc_include}",
            "-I",
            "${mes_arch_include}",
            "-I",
            "${mes_include}",
        ] +
        ["-I " + i for i in includes] +
        cflags,
    )

    objects = [_object_name(s) for s in sources]

    lines = _unpack_lines(prefix, compression)
    lines += extra_setup
    if configure:
        lines += [
            "# What ./configure would have produced, written out by hand.",
        ] + configure + [""]

    lines += ["# Compile."]
    for source, object in zip(sources, objects):
        lines.append("%s -c -o %s %s/%s" % (compile_prefix, object, prefix, source))

    lines += [
        "",
        "# Link.",
        " ".join([compile_prefix] + ldflags + ["-o", binary] + objects),
        "",
    ]

    # kaem --strict aborts on a non-zero exit, and several of these programs
    # report their version with a non-zero status. Where that is the case the
    # check moves out to a Bazel test, which can assert the exit code it
    # actually expects.
    if check_argument:
        lines += [
            "# Smoke-test the result before installing it.",
            "./%s %s" % (binary, check_argument),
            "",
        ]

    lines += [
        "# Install.",
        "mkdir -p ${out}/bin",
        "cp %s ${out}/bin/%s" % (binary, binary),
        "chmod 555 ${out}/bin/%s" % binary,
        "",
    ]

    write_file(
        name = name + "_script",
        out = name + ".kaem",
        content = lines,
    )

    tool_dir(
        name = name + "_tcc",
        tools = {"tcc": tcc},
    )

    kaem_run(
        name = name,
        script = name + ".kaem",
        substitutions = {"tarball": tarball},
        directory_substitutions = {
            "tcc_libs": tcc_libs,
            "tcc_include": "//tools/tcc:src_include_dir",
            "mes_arch_include": "//tools/mes:arch_include_dir",
            "mes_include": "@mes-m2//:headers",
        },
        srcs = [
            "//tools/tcc:src",
            "//tools/mes:arch_headers",
            "@mes-m2//:headers",
        ] + srcs,
        tools = [
            name + "_tcc",
            "//tools/mescc-tools-extra:bin",
        ] + tools,
        **kwargs
    )

def _installed_program_impl(ctx):
    directory = ctx.attr.package[DefaultInfo].files.to_list()
    if len(directory) != 1:
        fail("%s must provide exactly one directory" % ctx.attr.package.label)

    out = ctx.actions.declare_file(ctx.label.name)
    args = ctx.actions.args()
    args.add(out)
    args.add(directory[0].path + "/bin/" + ctx.attr.program)

    # catm copies by concatenating a single file, which avoids needing `cp`
    # to be reachable from a rule that is not running a script.
    ctx.actions.run(
        outputs = [out],
        inputs = directory,
        executable = ctx.executable._catm,
        arguments = [args],
        mnemonic = "ExtractProgram",
    )

    return [DefaultInfo(files = depset([out]), executable = out)]

installed_program = rule(
    implementation = _installed_program_impl,
    executable = True,
    attrs = {
        "package": attr.label(mandatory = True, doc = "A tcc_package output directory."),
        "program": attr.string(mandatory = True, doc = "Name of the program under bin/."),
        "_catm": attr.label(
            executable = True,
            cfg = "exec",
            default = "//tools/stage0/phase2:catm",
        ),
    },
    doc = """Extracts one program from a package's output directory.

A TreeArtifact cannot be run or depended on as an executable, so anything that
wants to invoke a built program needs the file on its own.""",
)
