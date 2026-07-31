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

def _patch_variable(index):
    """Returns the script variable naming the index'th patch.

    Args:
        index: The patch's position in the package's list.

    Returns:
        A variable name.
    """
    return "patch%d" % index

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
        binary = None,
        programs = None,
        cflags = [],
        ldflags = [],
        configure = [],
        extra_setup = [],
        patches = [],
        srcs = [],
        compression = "gz",
        check_argument = None,
        tcc = "//tools/tcc/current:tcc",
        tcc_libs = "//tools/tcc/current:tcc_libs",
        tcc_include = "//tools/tcc/current:src_include_dir",
        tcc_src = "//tools/tcc/current:src",
        includes = [],
        tools = [],
        **kwargs):
    """Builds one upstream package with tinycc and installs its binary.

    Args:
        name: Target name; the output directory holds bin/<binary>.
        tarball: The source archive.
        prefix: The directory the archive unpacks into.
        sources: C sources to compile, relative to `prefix`. These are shared
            by every program the package produces.
        binary: Name of the program to link and install, when there is only
            one. Sugar for a single-entry `programs`.
        programs: Programs to link, as a map of name to the sources unique to
            that program. A package like grep compiles one set of objects and
            links several programs from it, each differing by a single file.
        cflags: Compiler flags, including the -D set that stands in for
            ./configure output.
        ldflags: Extra flags for the link step.
        configure: Script lines run before compiling, for the file shuffling
            upstream's ./configure would otherwise do.
        extra_setup: Script lines run immediately after unpacking.
        patches: Labels of patch files, applied in order at -p1.
        srcs: Additional files the script reads.
        compression: Archive compression: "gz", "bz2" or "xz".
        check_argument: Argument used to smoke-test the program in the script;
            omit when the program exits non-zero for it.
        tcc: The tinycc to build with.
        tcc_libs: That compiler's library directory.
        tcc_include: That compiler's own include directory. Its stdarg.h has
            to match its own calling convention, so this follows the compiler.
        tcc_src: The source tree those headers belong to, staged as inputs.
        includes: Additional -I directories, as script variable references.
        tools: Extra tool directories to put on PATH.
        **kwargs: Passed through to the underlying kaem_run.
    """
    if (binary == None) == (programs == None):
        fail("%s needs exactly one of binary or programs" % name)
    if binary != None:
        programs = {binary: []}

    # tinycc knows where its own headers live, but only because those paths
    # were baked in when it was built; the directories still have to be staged
    # into the action. Naming them explicitly makes that dependency visible
    # and fixes the search order at the same time.
    compile_prefix = " ".join(
        [
            "tcc",
            # Debug info costs nothing here and makes a crash in a
            # bootstrapped program traceable to a line of upstream source.
            "-g",
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

    # patch -d changes directory for patch alone. Running `cd` in the script
    # instead would break PATH, whose entries are relative to the execroot, so
    # every later command would stop resolving.
    # Each patch is named through a script variable rather than by path,
    # because a path that is right when this repository is the main one is
    # wrong when it is a dependency: everything moves under
    # external/<module>+/ then. The rule resolves the label.
    if patches:
        lines.append("# Patch, at -p1 relative to the unpacked tree.")
        for index in range(len(patches)):
            lines.append("patch -d %s -Np1 -i ../${%s}" %
                         (prefix, _patch_variable(index)))
        lines.append("")

    lines += extra_setup
    if configure:
        lines += [
            "# What ./configure would have produced, written out by hand.",
        ] + configure + [""]

    lines += ["# Compile the objects every program shares."]
    for source, object in zip(sources, objects):
        lines.append("%s -c -o %s %s/%s" % (compile_prefix, object, prefix, source))

    lines += ["", "# Link."]
    for program in sorted(programs):
        # A program's own sources are passed to the link as sources rather
        # than compiled separately: they are what distinguishes it, so nothing
        # else would reuse the object.
        own = ["%s/%s" % (prefix, source) for source in programs[program]]
        lines.append(
            " ".join([compile_prefix] + ldflags + ["-o", program] + objects + own),
        )
    lines.append("")

    # kaem --strict aborts on a non-zero exit, and several of these programs
    # report their version with a non-zero status. Where that is the case the
    # check moves out to a Bazel test, which can assert the exit code it
    # actually expects.
    if check_argument:
        lines += ["# Smoke-test the results before installing them."]
        for program in sorted(programs):
            lines.append("./%s %s" % (program, check_argument))
        lines.append("")

    lines += ["# Install.", "mkdir -p ${out}/bin"]
    for program in sorted(programs):
        lines.append("cp %s ${out}/bin/%s" % (program, program))
        lines.append("chmod 555 ${out}/bin/%s" % program)
    lines.append("")

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
        substitutions = dict(
            {"tarball": tarball},
            **{_patch_variable(i): patches[i] for i in range(len(patches))}
        ),
        directory_substitutions = {
            "tcc_libs": tcc_libs,
            "tcc_include": tcc_include,
            "mes_arch_include": "//tools/mes:arch_include_dir",
            "mes_include": "//tools/mes:header_dir",
        },
        srcs = [
            tcc_src,
            "//tools/mes:arch_headers",
            "//tools/mes:header_dir",
        ] + srcs,
        tools = [
            name + "_tcc",
            "//tools/mescc-tools-extra:bin",
        ] + tools,
        **kwargs
    )

def _extract(ctx, path):
    """Copies one file out of a package's output directory.

    Args:
        ctx: The rule context, which must have a `package` attribute and the
            private `_catm` tool.
        path: The path of the wanted file inside the directory.

    Returns:
        The extracted File.
    """
    directory = ctx.attr.package[DefaultInfo].files.to_list()
    if len(directory) != 1:
        fail("%s must provide exactly one directory" % ctx.attr.package.label)

    out = ctx.actions.declare_file(ctx.label.name)
    args = ctx.actions.args()
    args.add(out)
    args.add(directory[0].path + "/" + path)

    # catm copies by concatenating a single file, which avoids needing `cp`
    # to be reachable from a rule that is not running a script.
    ctx.actions.run(
        outputs = [out],
        inputs = directory,
        executable = ctx.executable._catm,
        arguments = [args],
        mnemonic = "ExtractProgram",
    )
    return out

def _installed_program_impl(ctx):
    out = _extract(ctx, "bin/" + ctx.attr.program)
    return [DefaultInfo(files = depset([out]), executable = out)]

def _installed_file_impl(ctx):
    out = _extract(ctx, ctx.attr.path)
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

installed_file = rule(
    implementation = _installed_file_impl,
    executable = True,
    attrs = {
        "package": attr.label(mandatory = True, doc = "A package output directory."),
        "path": attr.string(mandatory = True, doc = "Path of the file inside it."),
        "_catm": attr.label(
            executable = True,
            cfg = "exec",
            default = "//tools/stage0/phase2:catm",
        ),
    },
    doc = """Extracts one file from a package's output directory, by path.

The same problem installed_program solves, for a file that is not under bin/.
A cc_toolchain names its compiler by path, and a path inside a TreeArtifact
is not a label that anything can be pointed at.""",
)
