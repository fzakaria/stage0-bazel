"""Rules for compiling C with mescc, the C compiler written in Scheme.

mescc is not a self-contained binary. It is a Scheme program interpreted by
mes, it parses C with nyacc, and it shells out to the stage0 M1, hex2 and
blood-elf tools to assemble and link. `mescc_toolchain` gathers all of that
into one provider so the individual build rules stay readable.

The file formats are stage0's, not the platform's: a mescc `.o` is a hex2
file, and an "archive" is those hex2 files concatenated. Concatenation is
what upstream's `mesar` does, and catm from phase 2 does it without a shell.
"""

load("//tools/stage0:catm.bzl", "concatenate_files")
load("//tools/stage0:exec.bzl", "BOOTSTRAP_EXECUTION_REQUIREMENTS")
load("//tools/stage0:mes.bzl", "MesInfo", "mes_env")

# mescc reads C99 through nyacc and holds the whole AST in the mes heap. The
# defaults are far too small for anything the size of tinycc, and mes reports
# the overflow only as an out-of-memory abort.
_ARENA_BYTES = "100000000"

_STACK_BYTES = "10000000"

# Where mescc looks for architecture-specific inputs, relative to each -L
# directory. Outputs have to land here or `arch-find` will not see them.
_ARCH_SUBDIR = "x86_64-mes"

MesccInfo = provider(
    doc = "Everything mescc needs to compile, archive and link C.",
    fields = {
        "mes": "MesInfo for the interpreter that runs mescc",
        "driver": "File: the mescc.scm driver script",
        "scheme_files": "depset[File]: nyacc and other Scheme mescc loads",
        "nyacc_dir": "string: the directory to append to GUILE_LOAD_PATH for nyacc",
        "assembler": "File: the M1 macro assembler",
        "linker": "File: the hex2 linker",
        "debug_tool": "File: blood-elf, which builds symbol footers",
        "catm": "FilesToRunProvider: the concatenation tool used to archive",
        "includes": "depset[File]: header files available to compiled code",
        "include_dirs": "list[string]: -I directories, in search order",
        "library_dirs": "list[string]: -L directories, in search order",
        "library_files": "depset[File]: files reachable through library_dirs",
        "arch": "string: mescc --arch value",
        "machine": "string: mescc -m value",
    },
)

def _mescc_env(mescc_info):
    """Builds the environment a mescc action runs under.

    Args:
        mescc_info: A MesccInfo.

    Returns:
        A dict for the `env` argument of `ctx.actions.run`.
    """
    env = mes_env(mescc_info.mes)

    # mescc resolves its own module path on top of mes's, so nyacc has to be
    # appended to whatever mes already needs.
    env["GUILE_LOAD_PATH"] = env["GUILE_LOAD_PATH"] + ":" + mescc_info.nyacc_dir

    # The assemble and link steps are separate processes that mescc spawns.
    # Naming them explicitly keeps PATH out of the picture entirely.
    env["M1"] = mescc_info.assembler.path
    env["HEX2"] = mescc_info.linker.path
    env["BLOOD_ELF"] = mescc_info.debug_tool.path

    env["MES_ARENA"] = _ARENA_BYTES
    env["MES_MAX_ARENA"] = _ARENA_BYTES
    env["MES_STACK"] = _STACK_BYTES
    return env

def _common_args(ctx, mescc_info):
    """Builds the flags every mescc invocation shares.

    Args:
        ctx: The rule context.
        mescc_info: A MesccInfo.

    Returns:
        An Args object carrying architecture, include and library flags.
    """
    args = ctx.actions.args()
    args.add("--no-auto-compile")
    args.add("-e", "main")
    args.add(mescc_info.driver)

    # Everything after the bare `--` is for mescc rather than for mes.
    args.add("--")
    args.add("-m", mescc_info.machine)
    args.add("--arch=" + mescc_info.arch)
    for d in mescc_info.include_dirs:
        args.add("-I", d)
    for d in mescc_info.library_dirs:
        args.add("-L", d)
    return args

def _mescc_action_inputs(mescc_info, extra):
    """Collects the inputs shared by every mescc action.

    Args:
        mescc_info: A MesccInfo.
        extra: A list of additional File inputs.

    Returns:
        A depset of File.
    """
    return depset(
        direct = extra + [
            mescc_info.driver,
            mescc_info.assembler,
            mescc_info.linker,
            mescc_info.debug_tool,
        ],
        transitive = [
            mescc_info.mes.runtime_files,
            mescc_info.scheme_files,
            mescc_info.includes,
            mescc_info.library_files,
        ],
    )

def _mescc_toolchain_impl(ctx):
    mes_info = ctx.attr.mes[MesInfo]

    nyacc_files = ctx.files.nyacc
    if not nyacc_files:
        fail("mescc cannot parse C without nyacc")

    # Every nyacc module sits under a single `module` directory; recovering it
    # from any one file avoids hard-coding the repository's layout.
    nyacc_dir = None
    for f in nyacc_files:
        marker = "/module/"
        index = f.path.find(marker)
        if index >= 0:
            nyacc_dir = f.path[:index + len(marker) - 1]
            break
    if nyacc_dir == None:
        fail("no nyacc file lives under a module/ directory")

    # A search directory is named by any file sitting directly inside it.
    # Starlark cannot talk about directories, and the exec path of a generated
    # file is not knowable until analysis, so the file is the only handle.
    include_dirs = [f.dirname for f in ctx.files.include_dir_markers]
    library_dirs = [f.dirname for f in ctx.files.library_dir_markers]

    return [MesccInfo(
        mes = mes_info,
        driver = ctx.file.driver,
        scheme_files = depset(nyacc_files),
        nyacc_dir = nyacc_dir,
        assembler = ctx.executable.assembler,
        linker = ctx.executable.linker,
        debug_tool = ctx.executable.debug_tool,
        catm = ctx.attr.catm[DefaultInfo].files_to_run,
        includes = depset(ctx.files.includes),
        include_dirs = include_dirs,
        library_dirs = library_dirs,
        library_files = depset(ctx.files.libraries),
        arch = ctx.attr.arch,
        machine = ctx.attr.machine,
    )]

mescc_toolchain = rule(
    implementation = _mescc_toolchain_impl,
    attrs = {
        "mes": attr.label(providers = [MesInfo], mandatory = True),
        "driver": attr.label(allow_single_file = True, mandatory = True, doc = "mescc.scm"),
        "nyacc": attr.label(allow_files = True, mandatory = True, doc = "nyacc Scheme modules"),
        "assembler": attr.label(executable = True, cfg = "exec", mandatory = True, doc = "M1"),
        "linker": attr.label(executable = True, cfg = "exec", mandatory = True, doc = "hex2"),
        "debug_tool": attr.label(executable = True, cfg = "exec", mandatory = True, doc = "blood-elf"),
        "catm": attr.label(executable = True, cfg = "exec", mandatory = True, doc = "catm"),
        "includes": attr.label_list(allow_files = True, doc = "Header files reachable via the include dirs."),
        "include_dir_markers": attr.label_list(
            allow_files = True,
            doc = "One file per -I directory, sitting directly in it; order is search order.",
        ),
        "libraries": attr.label_list(allow_files = True, doc = "Files reachable via the library dirs."),
        "library_dir_markers": attr.label_list(
            allow_files = True,
            doc = "One file per -L directory, sitting directly in it; order is search order.",
        ),
        "arch": attr.string(default = "x86_64"),
        "machine": attr.string(default = "64"),
    },
    provides = [MesccInfo],
    doc = "Bundles mes, mescc, nyacc and the stage0 tools mescc drives.",
)

def _object_name(ctx):
    """Returns the path stem mescc should write its outputs under.

    mescc derives the assembly listing's name from the object's, so both live
    in the architecture subdirectory that `arch-find` searches.

    Args:
        ctx: The rule context.

    Returns:
        A path relative to the package directory, without a suffix.
    """
    return _ARCH_SUBDIR + "/" + ctx.label.name

def _select_source(ctx):
    """Picks the translation unit to compile out of the `src` attribute.

    A staged source tree yields hundreds of files, only one of which is the
    unit being compiled, so `main` names it. The rest are still inputs: with
    ONE_SOURCE the compiler reads most of them.

    Args:
        ctx: The rule context.

    Returns:
        The File to pass to mescc.
    """
    files = ctx.files.src
    if not ctx.attr.main:
        if len(files) != 1:
            fail("src produces %d files; set main to name the one to compile" % len(files))
        return files[0]

    suffix = "/" + ctx.attr.main
    for f in files:
        if f.path.endswith(suffix):
            return f
    fail("no file in src ends with %s" % suffix)

def _mescc_object_impl(ctx):
    mescc_info = ctx.attr.toolchain[MesccInfo]

    source = _select_source(ctx)
    stem = _object_name(ctx)
    obj = ctx.actions.declare_file(stem + ".o")

    # mescc always writes the M1 assembly beside the object and later needs it
    # to build debug footers, so it is declared rather than left as a stray.
    listing = ctx.actions.declare_file(stem + ".s")

    args = _common_args(ctx, mescc_info)
    args.add("-c")

    # Target-specific include directories come after the toolchain's, so a
    # header shipped with mes still wins over one of the same name here.
    for marker in ctx.files.include_dir_markers:
        args.add("-I", marker.dirname)
    for define in ctx.attr.defines:
        args.add("-D", define)
    args.add("-o", obj)
    args.add(source)

    ctx.actions.run(
        outputs = [obj, listing],
        inputs = _mescc_action_inputs(
            mescc_info,
            ctx.files.src + ctx.files.hdrs + ctx.files.include_dir_markers,
        ),
        executable = mescc_info.mes.interpreter,
        arguments = [args],
        env = _mescc_env(mescc_info),
        mnemonic = "MesccCompile",
        execution_requirements = BOOTSTRAP_EXECUTION_REQUIREMENTS,
        progress_message = "Compiling %{label} with mescc",
    )

    return [DefaultInfo(files = depset([obj, listing]))]

mescc_object = rule(
    implementation = _mescc_object_impl,
    attrs = {
        "src": attr.label(
            allow_files = True,
            mandatory = True,
            doc = "The C source, or a staged tree containing it alongside its includes.",
        ),
        "main": attr.string(
            doc = "Path suffix naming the translation unit, when src yields more than one file.",
        ),
        "hdrs": attr.label_list(allow_files = True, doc = "Headers the source includes."),
        "include_dir_markers": attr.label_list(
            allow_files = True,
            doc = "One file per extra -I directory, sitting directly in it.",
        ),
        "defines": attr.string_list(doc = "Preprocessor definitions, as NAME=VALUE."),
        "toolchain": attr.label(providers = [MesccInfo], mandatory = True),
    },
    doc = "Compiles one C file to a mescc object (a hex2 file) plus its listing.",
)

def _mescc_library_impl(ctx):
    mescc_info = ctx.attr.toolchain[MesccInfo]

    objects = [f for f in ctx.files.objects if f.extension == "o"]
    listings = [f for f in ctx.files.objects if f.extension == "s"]

    # Upstream's mesar is `cat`: an archive is its members end to end, and the
    # listings are concatenated in parallel so the linker can find symbols.
    archive = ctx.actions.declare_file("%s/lib%s.a" % (_ARCH_SUBDIR, ctx.attr.library_name))
    listing = ctx.actions.declare_file("%s/lib%s.s" % (_ARCH_SUBDIR, ctx.attr.library_name))

    concatenate_files(ctx, srcs = objects, tool = mescc_info.catm.executable, out = archive)
    concatenate_files(ctx, srcs = listings, tool = mescc_info.catm.executable, out = listing)

    return [DefaultInfo(files = depset([archive, listing]))]

mescc_library = rule(
    implementation = _mescc_library_impl,
    attrs = {
        "objects": attr.label_list(allow_files = True, mandatory = True, doc = "mescc_object targets."),
        "library_name": attr.string(mandatory = True, doc = "Name without the lib prefix or .a suffix."),
        "toolchain": attr.label(providers = [MesccInfo], mandatory = True),
    },
    doc = "Archives mescc objects into the concatenated form mescc links against.",
)

def _object_target_name(src):
    """Derives a target name from a source label.

    Upstream names objects by flattening the source path, and the same scheme
    is used here so an object can be traced back to its source at a glance.

    Args:
        src: A source label such as `@mes-m2//:lib/string/strlen.c`.

    Returns:
        A target name such as `string-strlen`.
    """
    path = src.split(":")[-1]
    if path.startswith("lib/"):
        path = path[len("lib/"):]
    if path.endswith(".c"):
        path = path[:-len(".c")]
    return path.replace("/", "-")

def mescc_archive(name, library_name, srcs, toolchain, hdrs = [], defines = [], **kwargs):
    """Compiles a list of C sources and archives them into one library.

    Args:
        name: Name of the resulting `mescc_library` target.
        library_name: Library name without the `lib` prefix or `.a` suffix.
        srcs: C source labels to compile.
        toolchain: The `mescc_toolchain` to build with.
        hdrs: Headers the sources include.
        defines: Preprocessor definitions shared by every source.
        **kwargs: Passed through to the `mescc_library` target.
    """
    objects = []
    for src in srcs:
        object_name = "%s_%s" % (name, _object_target_name(src))
        objects.append(":" + object_name)
        mescc_object(
            name = object_name,
            src = src,
            hdrs = hdrs,
            defines = defines,
            toolchain = toolchain,
        )

    mescc_library(
        name = name,
        library_name = library_name,
        objects = objects,
        toolchain = toolchain,
        **kwargs
    )

def _mescc_binary_impl(ctx):
    mescc_info = ctx.attr.toolchain[MesccInfo]

    out = ctx.actions.declare_file(ctx.label.name)
    objects = [f for f in ctx.files.objects if f.extension == "o"]
    listings = [f for f in ctx.files.objects if f.extension == "s"]

    args = _common_args(ctx, mescc_info)
    if ctx.attr.debug_info:
        args.add("-g")
    for library in ctx.attr.libraries:
        args.add("-l", library)
    args.add("-o", out)

    # Objects, not the assembly listings. Upstream's own build scripts hand
    # mescc the listings, but mescc then reassembles each one into an object
    # beside it, and under a sandbox that directory holds another action's
    # declared outputs and is read-only. Linking objects avoids the write; the
    # cost is that blood-elf sees only the first object's symbols, so debug
    # info for a multi-object program is incomplete.
    args.add_all(objects)

    ctx.actions.run(
        outputs = [out],
        inputs = _mescc_action_inputs(mescc_info, objects + listings),
        executable = mescc_info.mes.interpreter,
        arguments = [args],
        env = _mescc_env(mescc_info),
        mnemonic = "MesccLink",
        execution_requirements = BOOTSTRAP_EXECUTION_REQUIREMENTS,
        progress_message = "Linking %{label} with mescc",
    )

    return [DefaultInfo(files = depset([out]), executable = out)]

mescc_binary = rule(
    implementation = _mescc_binary_impl,
    executable = True,
    attrs = {
        "objects": attr.label_list(allow_files = True, mandatory = True, doc = "mescc_object targets to link."),
        "libraries": attr.string_list(doc = "Library names to pass as -l, without the lib prefix."),
        "debug_info": attr.bool(default = True, doc = "Emit a blood-elf symbol footer."),
        "toolchain": attr.label(providers = [MesccInfo], mandatory = True),
    },
    doc = "Links mescc objects and archives into a static ELF executable.",
)
