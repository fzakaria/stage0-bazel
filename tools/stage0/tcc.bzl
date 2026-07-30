"""Rules for building with tinycc, once mescc has produced the first one.

The self-rebuild chain works because each tinycc can compile the next: every
stage recompiles the same source with more of the language switched on, and
recompiles the C library with the compiler that stage just produced. A stage
therefore has two outputs -- the compiler, and the library directory the next
stage links against -- which is why there are two rules here.

`-B` points tinycc at the directory holding crt1.o and the archives, so the
library output is a directory rather than a file list.
"""

def _library_dir(libs):
    """Returns the directory a tinycc `-B` flag should name.

    Args:
        libs: A Target providing the library directory, or None.

    Returns:
        The path to pass to -B, or None when no library directory was given.
    """
    if libs == None:
        return None
    files = libs[DefaultInfo].files.to_list()
    if len(files) != 1:
        fail("%s must provide exactly one directory" % libs.label)
    return files[0]

def _directory_root(target):
    """Returns the root directory of a target's files.

    Args:
        target: A Target whose files share a root.

    Returns:
        The shortest directory among them, which is that root.
    """
    files = target[DefaultInfo].files.to_list()
    if not files:
        fail("%s produces no files, so it names no directory" % target.label)

    # A TreeArtifact is already the directory; a staged tree is a set of files
    # sharing a root, which the shortest of their directories identifies.
    if len(files) == 1 and files[0].is_directory:
        return files[0].path

    root = files[0].dirname
    for f in files:
        if len(f.dirname) < len(root):
            root = f.dirname
    return root

def _tcc_args(ctx, output):
    """Builds the command line shared by compiling and linking.

    Args:
        ctx: The rule context.
        output: The File tinycc should write.

    Returns:
        An Args object.
    """
    args = ctx.actions.args()
    args.add("-g")

    libs = _library_dir(ctx.attr.libs)
    if libs != None:
        args.add("-B", libs.path)

    for d in ctx.attr.defines:
        args.add("-D", d)
    for marker in ctx.files.include_dir_markers:
        args.add("-I", marker.dirname)

    # Where the compiler being built will look for headers when it is run.
    # This is baked into the binary, so it names directories in this build
    # rather than anything on the eventual host.
    if ctx.attr.sysinclude_dirs:
        roots = [_directory_root(d) for d in ctx.attr.sysinclude_dirs]
        args.add("-D", "CONFIG_TCC_SYSINCLUDEPATHS=\"%s\"" % ":".join(roots))
    args.add_all(ctx.attr.copts)
    args.add("-o", output)
    return args

def _tcc_inputs(ctx, extra):
    """Collects the inputs every tinycc action needs.

    Args:
        ctx: The rule context.
        extra: Additional File inputs.

    Returns:
        A depset of File.
    """
    direct = extra + ctx.files.srcs + ctx.files.include_dir_markers
    transitive = [d[DefaultInfo].files for d in ctx.attr.sysinclude_dirs]
    if ctx.attr.libs != None:
        transitive.append(ctx.attr.libs[DefaultInfo].files)
    return depset(direct = direct, transitive = transitive)

def _tcc_binary_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)

    source = None
    suffix = "/" + ctx.attr.main
    for f in ctx.files.srcs:
        if f.path.endswith(suffix):
            source = f
            break
    if source == None:
        fail("no file in srcs ends with %s" % suffix)

    args = _tcc_args(ctx, out)
    args.add(source)

    ctx.actions.run(
        outputs = [out],
        inputs = _tcc_inputs(ctx, []),
        executable = ctx.executable.tcc,
        arguments = [args],
        mnemonic = "TccLink",
        progress_message = "Building %{label} with tinycc",
    )

    return [DefaultInfo(files = depset([out]), executable = out)]

_TCC_ATTRS = {
    "srcs": attr.label_list(
        allow_files = True,
        mandatory = True,
        doc = "The staged source tree, including everything the unit includes.",
    ),
    "defines": attr.string_list(doc = "Preprocessor definitions, as NAME=VALUE."),
    "copts": attr.string_list(doc = "Additional flags, passed through verbatim."),
    "include_dir_markers": attr.label_list(
        allow_files = True,
        doc = "One file per -I directory, sitting directly in it.",
    ),
    "sysinclude_dirs": attr.label_list(
        doc = "Targets whose root directories become the built compiler's default include path.",
    ),
    "libs": attr.label(
        doc = "Directory of crt objects and archives to pass as -B.",
    ),
    "tcc": attr.label(
        executable = True,
        cfg = "exec",
        mandatory = True,
        doc = "The tinycc that builds this stage.",
    ),
}

tcc_binary = rule(
    implementation = _tcc_binary_impl,
    executable = True,
    attrs = dict(_TCC_ATTRS, main = attr.string(
        mandatory = True,
        doc = "Path suffix naming the translation unit to compile.",
    )),
    doc = "Compiles and links one translation unit with tinycc.",
)
