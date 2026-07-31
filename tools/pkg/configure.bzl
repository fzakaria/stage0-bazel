"""Building an upstream package by running its own ./configure.

Everything up to and including coreutils had to be compiled from a source
list transcribed by hand, because no shell existed to run a configure script.
bash changes that, and from here on a package is built the way its authors
meant it to be.

Two things have to be pinned that a normal build leaves to the system.

A configure script's shebang is `#!/bin/sh`, and make runs any recipe holding
a shell metacharacter through `$(SHELL)`, which also defaults to `/bin/sh`.
Neither is sandboxed away on a normal Linux host, so both would silently pick
up the host's shell and the bootstrap would stop being a bootstrap. The driver
below invokes configure through the bash this repository built and passes that
same bash to make and to autoconf, so nothing in the build can reach /bin/sh.

Paths handed to the action are relative to the execroot, and configure runs
one directory down inside the unpacked tree. The driver turns them absolute
before descending rather than trying to count `../`s.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//tools/stage0:files.bzl", "tool_dir")
load(
    "//tools/stage0:kaem.bzl",
    "MAKE_JOBS",
    "MAKE_PARALLEL",
    "MAKE_SERIAL",
    "kaem_run",
)

# The decompressor for each archive format, as mescc-tools-extra names them.
_DECOMPRESSORS = {
    "gz": "ungz",
    "bz2": "unbz2",
    "xz": "unxz",
}

# Which program unpacks a .gz.
#
# mescc-tools-extra's ungz is a minimal inflate built on puff, and it does not
# handle every stream a modern gzip produces -- bash 5.3's tarball makes it
# fail with "puff() failed with return code -2". Once this repository has
# built GNU gzip, that is the better answer; until then ungz is the only one
# there is, which is why gzip itself has to use it.
DECOMPRESS_SEED = "seed"
DECOMPRESS_GNU = "gnu"

_DECOMPRESSOR_KINDS = [
    DECOMPRESS_SEED,
    DECOMPRESS_GNU,
]

# Which C library's headers a package is compiled against.
#
# Everything up to now borrows mes-libc's, because it has no other. A C
# library is the exception: musl ships a complete set of its own and they have
# to be the only ones on the include path. mes-libc's would otherwise shadow
# them -- the injected -I flags come before the ones the package's own
# makefile adds -- and musl's internal headers would silently lose to
# same-named files that mean something else.
LIBC_HEADERS_MES = "mes"
LIBC_HEADERS_OWN = "own"

# The musl tinycc installs its compiler, musl's headers and musl's runtime as
# one tree, so a single directory names all three. Packages built after that
# point use this rather than the scattered mes-libc directories.
LIBC_HEADERS_TOOLCHAIN = "toolchain"

# Nothing to stage: the package is built by a compiler that already knows
# where its C library is, or ships the C library itself. Only a package
# passing `cc` can use this, because the tinycc directories a default build
# needs are not made available.
LIBC_HEADERS_NONE = "none"

_LIBC_HEADERS = [
    LIBC_HEADERS_MES,
    LIBC_HEADERS_OWN,
    LIBC_HEADERS_TOOLCHAIN,
    LIBC_HEADERS_NONE,
]

def _patch_variable(index):
    """Returns the script variable naming the index'th patch.

    Args:
        index: The patch's position in the package's list.

    Returns:
        A variable name.
    """
    return "patch%d" % index

def _driver_lines(prefix, configure_flags, make_flags, build_targets, build_attempts, install_target, install_commands, post_install_commands, cc, cc_flags, exports, extra_setup, libc_headers, make_concurrency):
    """Returns the bash driver that configures, builds and installs a package.

    Args:
        prefix: The directory the tarball unpacks into.
        configure_flags: Flags appended to ./configure.
        make_flags: Flags passed to the build and install runs of make.
        build_targets: One string of make targets per build run, so that a
            package needing staged builds can have them. Empty means a single
            run of the makefile's default target.
        build_attempts: How many times to run make before giving up. Above
            one this works around a known flake rather than a real
            dependency problem, and the package saying so should explain
            which.
        install_target: The make target that installs, usually "install".
        install_commands: Shell lines that install the build products, used
            instead of running make when the install rules need tools that do
            not exist yet.
        post_install_commands: Shell lines run after the install, to repair an
            installed tree the package's own rules leave unusable.
        cc: The compiler command, when it is not tinycc. Empty means tinycc,
            which the driver spells out itself because it has to name the
            directories tinycc was built knowing.
        cc_flags: Extra flags appended to the CC the package is given.
        exports: Shell assignments exported before ./configure runs.
        extra_setup: Shell lines run inside the tree before ./configure.
        libc_headers: One of _LIBC_HEADERS.
        make_concurrency: MAKE_PARALLEL to build with -j, MAKE_SERIAL for one
            recipe at a time.

    Returns:
        A list of shell lines.
    """
    lines = [
        "# Generated by configure_package. Run by the bash this repository",
        "# built, never by the host's.",
        "set -eu",
        "",
        "# Every PATH entry here is relative to the execroot, and this script",
        "# changes directory. bash remembers where it found a program and",
        "# reuses that path, so a command run before the cd would be looked",
        "# for at a stale relative path afterwards and fail with ENOENT.",
        "set +h",
        "",
        "# Every path the action supplies is relative to the execroot, and",
        "# configure runs one directory down. Absolute paths survive the cd.",
        "root=\"$PWD\"",
        "out=\"$root/$out\"",
        "",
        "# The shell for configure, for config.status and for every make",
        "# recipe that needs one. Without this all three find /bin/sh and the",
        "# host's shell enters a build that is supposed to have none.",
        "bash_path=\"$root/$(command -v bash)\"",
        "export CONFIG_SHELL=\"$bash_path\"",
        "export SHELL=\"$bash_path\"",
        "",
        "# A shell writes here-documents to a temporary file, and the action",
        "# runs with an emptied environment, so there is no TMPDIR to write",
        "# them to. autoconf builds config.status out of very large here-",
        "# documents; when they cannot be written it reports only",
        "# \"could not make ./config.status\" and stops.",
        "export TMPDIR=\"$root/tmp\"",
        "mkdir -p \"$TMPDIR\"",
        "",
        "# Make PATH absolute. The action supplies it relative to the",
        "# execroot, with a ../-prefixed copy of each entry so that a build",
        "# one directory down still resolves. That breaks down here: a",
        "# configure script descends into subdirectories to configure them,",
        "# and each depth would need a different number of ../ segments.",
        "# Anchoring every entry to the execroot makes the depth irrelevant.",
        "absolute_path=\"\"",
        "saved_ifs=\"$IFS\"",
        "IFS=:",
        "for entry in $PATH; do",
        "  while [ \"${entry#../}\" != \"$entry\" ]; do entry=\"${entry#../}\"; done",
        "  case \"$entry\" in",
        "    /*) ;;",
        "    *) entry=\"$root/$entry\" ;;",
        "  esac",
        "  absolute_path=\"$absolute_path${absolute_path:+:}$entry\"",
        "done",
        "IFS=\"$saved_ifs\"",
        "export PATH=\"$absolute_path\"",
        "",
    ]

    # A package built by something other than tinycc names its own compiler,
    # and says where its C library is in its own exports. There is nothing
    # for the driver to fill in on its behalf.
    if cc:
        lines += [
            " ".join(["export CC=\"" + cc] + cc_flags) + "\"",
            "",
        ]
    else:
        lines += [
            "# tinycc knows where its own headers live only because those",
            "# paths were baked in when it was built; they still have to be",
            "# named. tcc_include holds the compiler's own headers --",
            "# stdarg.h, stddef.h and the rest that belong to the compiler",
            "# rather than to a libc -- so it is needed whichever C library",
            "# the package compiles against.",
            " ".join(
                [
                    "export CC=\"tcc",
                ] + ([
                    # No -I for the C library here. The compiler was built
                    # knowing where musl's headers live, and finds them on its
                    # system include path -- which is searched after -I, so a
                    # package that ships gnulib replacements still gets its own.
                    "-B $root/$toolchain/lib",
                ] if libc_headers == LIBC_HEADERS_TOOLCHAIN else [
                    "-B $root/$tcc_libs",
                    "-I $root/$tcc_include",
                ] + ([
                    "-I $root/$mes_arch_include",
                    "-I $root/$mes_include",
                ] if libc_headers == LIBC_HEADERS_MES else [])) + cc_flags,
            ) + "\"",
            "",
        ]

    for export in exports:
        lines.append("export " + export)
    if exports:
        lines.append("")

    lines += [
        # How many recipes make may run at once. Empty for a serial build,
        # which is what most of these packages get; see MAKE_JOBS in kaem.bzl
        # for why the number is what it is.
        "make_jobs=\"%s\"" % ("-j%d" % MAKE_JOBS if make_concurrency == MAKE_PARALLEL else ""),
        "",
        "cd " + prefix,
        "",
        "# The timestamp every unpacked file is given below. It has to exist",
        "# before the walk starts, and outside the tree, so that it is not",
        "# itself restamped.",
        "unpack_stamp=\"$TMPDIR/unpack-stamp\"",
        ": > \"$unpack_stamp\"",
        "",
        "# Walk the unpacked tree once, doing two things to it.",
        "#",
        "# untar does not preserve the executable bit, and a configure script",
        "# needs it: it runs missing, install-sh, config.sub and the configure",
        "# scripts of subdirectories by path, not through a shell.",
        "#",
        "# untar also stamps each file with the moment it was written rather",
        "# than with what the archive recorded, so the order of the files in",
        "# the archive becomes an order in time. A release tarball ships",
        "# generated files beside the sources they were generated from --",
        "# gengtype-lex.c beside gengtype-lex.l, aclocal.m4 beside",
        "# configure.ac, a .info file beside its .texi -- and whichever of the",
        "# pair is written after a whole-second boundary comes out newer. make",
        "# then decides the generated file is stale and reaches for flex,",
        "# aclocal or makeinfo, none of which exist here. Whether that happens",
        "# depends on how the writes fall against the clock, so it varies from",
        "# run to run and from package to package. One timestamp for the whole",
        "# tree settles all of it: make rebuilds on strictly-newer, so if",
        "# nothing is newer than anything else no maintainer rule can fire.",
        "#",
        "# The walk is a shell function because findutils does not exist yet",
        "# here, and it restamps a whole directory in one call because touch",
        "# takes many operands. Empty directories make the glob stay literal",
        "# and a tarball can hold a symbolic link to a path that does not",
        "# exist, so a failed touch is not an error.",
        "shopt -s dotglob",
        "prepare_source_tree () {",
        "  local entry",
        "  touch -r \"$unpack_stamp\" \"$1\"/* || :",
        "  for entry in \"$1\"/*; do",
        "    if [ -d \"$entry\" ]; then",
        "      prepare_source_tree \"$entry\"",
        "    elif [ -f \"$entry\" ]; then",
        "      case \"$entry\" in",
        "        */configure | *.sh | */missing | */install-sh | */mkinstalldirs \\",
        "        | */config.sub | */config.guess | */depcomp | */compile \\",
        "        | */move-if-change | */ylwrap | */test-driver)",
        "          chmod +x \"$entry\"",
        "          ;;",
        "      esac",
        "    fi",
        "  done",
        "}",
        "prepare_source_tree .",
        "shopt -u dotglob",
        "",
        "# Now let the clock move past the second the tree was stamped with.",
        "# autoconf's sanity check compares a file it has just created against",
        "# the distributed files and stops if its own is not strictly newer:",
        "# \"newly created file is older than distributed files\".",
        "#",
        "# The wait has to be in whole seconds, because that is the resolution",
        "# the check compares at: it asks `ls -t`, and this coreutils records",
        "# only seconds. bash's own -nt would not do -- it compares",
        "# nanoseconds, so a loop waiting on it finishes immediately and leaves",
        "# the two files inside the same second after all. SECONDS is bash's",
        "# counter and moves with the clock, and it needs no external program:",
        "# coreutils' sleep is built against mes-libc here and cannot read the",
        "# realtime clock.",
        "timestamp_wait_start=$SECONDS",
        "while [ $((SECONDS - timestamp_wait_start)) -lt 2 ]; do",
        "  :",
        "done",
        "",
    ]

    if extra_setup:
        lines += extra_setup + [""]

    lines += [
        "# Configure. Naming the shell rather than running ./configure",
        "# directly does two jobs: untar does not preserve the executable bit,",
        "# and the script's own #!/bin/sh is never consulted.",
        " ".join(["\"$bash_path\"", "./configure", "--prefix=\"$out\""] + configure_flags),
        "",
        "# Build. SHELL is passed explicitly because make ignores it from the",
        "# environment by design.",
    ]

    # Each entry is one make run. Some packages have to be built in stages --
    # binutils links its libraries into the tools, and the tools do not
    # resolve unless the libraries are finished first.
    for targets in (build_targets or [""]):
        # $make_jobs is unquoted deliberately: it is empty for a serial build,
        # and an empty quoted word would be an argument make has to reject.
        command = " ".join(["make", "$make_jobs", "SHELL=\"$bash_path\""] + make_flags +
                           ([targets] if targets else []))
        if build_attempts > 1:
            lines += [
                "attempt=1",
                "while true; do",
                "  if %s; then break; fi" % command,
                "  attempt=$((attempt + 1))",
                "  if [ $attempt -gt %d ]; then" % build_attempts,
                "    echo \"make failed %d times\" >&2" % build_attempts,
                "    exit 1",
                "  fi",
                "  echo \"make failed, retrying ($attempt)\" >&2",
                "done",
            ]
        else:
            lines.append(command)
    lines.append("")

    # A package whose install rules need tools this bootstrap does not have
    # yet -- makeinfo is the usual one -- says what to copy instead.
    if install_commands:
        lines += ["# Install."] + install_commands + [""]
    else:
        lines += [
            "# Install.",
            " ".join(["make", "SHELL=\"$bash_path\"", install_target] + make_flags),
            "",
        ]

    # Repairs to the installed tree, for a package whose own install rules
    # leave it in a state this repository cannot use.
    if post_install_commands:
        lines += post_install_commands + [""]
    return lines

def configure_package(
        name,
        tarball,
        prefix,
        configure_flags = [],
        make_flags = [],
        build_targets = [],
        build_attempts = 1,
        make_concurrency = MAKE_SERIAL,
        install_target = "install",
        install_commands = [],
        post_install_commands = [],
        cc = "",
        cc_flags = [],
        exports = [],
        extra_setup = [],
        extra_files = {},
        extra_directories = {},
        libc_headers = LIBC_HEADERS_MES,
        patches = [],
        patch_strip = 1,
        extra_tarballs = {},
        extra_tarball_compression = {},
        srcs = [],
        compression = "gz",
        decompressor = DECOMPRESS_SEED,
        tcc = "//tools/tcc/current:tcc",
        tcc_libs = "//tools/tcc/current:tcc_libs",
        tcc_include = "//tools/tcc/current:src_include_dir",
        tcc_src = "//tools/tcc/current:src",
        # Round two, not round one: the mes-libc tinycc miscompiles long
        # double arithmetic, so a musl it builds formats floating point
        # wrongly. See tools/pkg/musl.
        toolchain = "//tools/tcc/musl:tcc-musl2",
        toolchain_tcc = "//tools/tcc/musl:tcc2",
        tools = [],
        **kwargs):
    """Builds a package by running its own ./configure, make and make install.

    Args:
        name: Target name; the output directory is what `make install` wrote.
        tarball: The source archive.
        prefix: The directory the archive unpacks into.
        configure_flags: Flags appended to ./configure.
        make_flags: Flags passed to make, for both the build and the install.
        build_targets: One string of make targets per build run, so that a
            package needing staged builds can have them. Empty means a single
            run of the makefile's default target.
        build_attempts: How many times to run make before giving up. Above
            one this works around a known flake; see build_attempts in the
            package that sets it.
        make_concurrency: MAKE_PARALLEL to build with -j MAKE_JOBS and to
            reserve that many CPUs from Bazel's pool, or MAKE_SERIAL for one
            recipe at a time. Only the build runs in parallel; the install
            does not, because it is short and its rules are the ones most
            likely never to have been tried concurrently.
        install_target: The make target that installs.
        install_commands: Shell lines that install the build products, used
            instead of running make when the install rules need tools that do
            not exist yet.
        post_install_commands: Shell lines run after the install, to repair an
            installed tree the package's own rules leave unusable.
        cc: The compiler command, for a package built by something other than
            tinycc. Defaults to empty, which means tinycc pointed at the
            directories named by `libc_headers`.
        cc_flags: Extra flags appended to the CC the package is given.
        exports: Shell assignments exported before ./configure runs.
        extra_setup: Shell lines run inside the unpacked tree before
            ./configure, for the file shuffling some packages need.
        extra_files: Further single files the build reads, as a map of
            script-variable name to label. A path written out by hand would
            be wrong as soon as this repository is a dependency rather than
            the main one, so a file a setup line copies is named this way.
        extra_directories: Further directories the build reads, as a map of
            script-variable name to label. A package built by GCC uses this
            to name its C library, which the driver does not know about.
        libc_headers: LIBC_HEADERS_MES to compile against mes-libc's headers,
            LIBC_HEADERS_OWN for a package that ships its own C library
            headers and must not see any others, LIBC_HEADERS_TOOLCHAIN for
            the musl tinycc's combined tree, or LIBC_HEADERS_NONE for a
            package that names its own compiler and needs none of them.
        patches: Labels of patch files, applied in order.
        patch_strip: The -p level the patches are written against.
        extra_tarballs: Further archives unpacked beside the main one, as a
            map of script-variable name to label. A package like GCC ships
            its front ends and its arbitrary-precision libraries separately.
        extra_tarball_compression: The compression of an entry in
            `extra_tarballs`, for any that is not gzip. Same keys, values
            "gz", "bz2" or "xz".
        srcs: Additional files the build reads.
        compression: Archive compression: "gz", "bz2" or "xz".
        decompressor: DECOMPRESS_SEED for mescc-tools-extra's inflate, or
            DECOMPRESS_GNU for the gzip this repository built. The seed's
            cannot read every stream a modern gzip writes.
        tcc: The tinycc to build with.
        tcc_libs: That compiler's library directory.
        tcc_include: That compiler's own include directory.
        tcc_src: The source tree those headers belong to, staged as inputs.
        toolchain_tcc: The compiler inside `toolchain`, as an executable.
        tools: Extra tool directories to put on PATH.
        **kwargs: Passed through to the underlying kaem_run.
    """
    if compression not in _DECOMPRESSORS:
        fail("unknown compression %s" % compression)
    if decompressor not in _DECOMPRESSOR_KINDS:
        fail("decompressor must be one of %s, got %s" % (_DECOMPRESSOR_KINDS, decompressor))
    if libc_headers not in _LIBC_HEADERS:
        fail("libc_headers must be one of %s, got %s" % (_LIBC_HEADERS, libc_headers))
    if libc_headers == LIBC_HEADERS_NONE and not cc:
        fail("%s: libc_headers = LIBC_HEADERS_NONE stages none of the " % name +
             "directories tinycc needs, so it requires an explicit cc")
    for archive, archive_compression in extra_tarball_compression.items():
        if archive not in extra_tarballs:
            fail("%s: extra_tarball_compression names %s, which is not an " %
                 (name, archive) + "entry in extra_tarballs")
        if archive_compression not in _DECOMPRESSORS:
            fail("%s: unknown compression %s for %s" %
                 (name, archive_compression, archive))

    write_file(
        name = name + "_driver",
        out = name + "_build.sh",
        content = _driver_lines(
            prefix,
            configure_flags,
            make_flags,
            build_targets,
            build_attempts,
            install_target,
            install_commands,
            post_install_commands,
            cc,
            cc_flags,
            exports,
            extra_setup,
            libc_headers,
            make_concurrency,
        ),
    )

    # kaem still does the unpacking and patching. It cannot cd, which is
    # exactly why the driver above exists, but it can decompress and patch
    # without any of this mattering.
    if decompressor == DECOMPRESS_GNU:
        # gzip decides the output name by dropping the suffix, which is what
        # makes this expressible in kaem: there is no redirection here, so a
        # decompressor that writes to stdout would be unusable.
        lines = [
            "# Unpack, with the gzip this repository built rather than the",
            "# seed's minimal inflate.",
            "cp ${tarball} source.tar.gz",
            "gzip -d source.tar.gz",
            "untar --file source.tar",
            "",
        ]
    else:
        lines = [
            "# Unpack.",
            "%s --file ${tarball} --output source.tar" % _DECOMPRESSORS[compression],
            "untar --file source.tar",
            "",
        ]

    # Further archives unpacked beside the main one, each with whatever
    # compression it happens to ship with. GCC 4.6's support libraries were
    # all gzip; 10.4's are two xz, one bzip2 and one gzip.
    #
    # A gzip archive goes through the gzip this repository built rather than
    # the seed's inflate, which cannot read every stream a modern gzip writes,
    # and gzip has no --output so the file is copied to a name it will accept.
    # The seed's unbz2 and unxz take --file and --output directly.
    if extra_tarballs:
        lines.append("# Unpack the archives that travel with it.")
        for archive in sorted(extra_tarballs):
            compression_kind = extra_tarball_compression.get(archive, "gz")
            if compression_kind == "gz":
                lines += [
                    "cp ${%s} %s.tar.gz" % (archive, archive),
                    "gzip -d %s.tar.gz" % archive,
                ]
            else:
                lines.append("%s --file ${%s} --output %s.tar" %
                             (_DECOMPRESSORS[compression_kind], archive, archive))
            lines.append("untar --file %s.tar" % archive)
        lines.append("")

    # Each patch is named through a script variable rather than by path,
    # because a path that is right when this repository is the main one is
    # wrong when it is a dependency: everything moves under
    # external/<module>+/ then. The rule resolves the label.
    if patches:
        lines.append("# Patch, relative to the unpacked tree.")
        for index in range(len(patches)):
            lines.append("patch -d %s -Np%d -i ../${%s}" %
                         (prefix, patch_strip, _patch_variable(index)))
        lines.append("")

    lines += [
        "# Hand over to the bootstrapped shell. The driver is a generated",
        "# file under bazel-out, not a path this script could spell.",
        "mkdir -p ${out}",
        "bash ${driver}",
        "",
    ]

    write_file(
        name = name + "_script",
        out = name + ".kaem",
        content = lines,
    )

    uses_toolchain = libc_headers == LIBC_HEADERS_TOOLCHAIN
    stages_nothing = libc_headers == LIBC_HEADERS_NONE

    # Whether the built gzip has to be on PATH: either the main archive asked
    # for it, or one of the extra archives is a .gz, which the unpack lines
    # above decompress with it rather than with the seed's inflate.
    needs_gnu_gzip = decompressor == DECOMPRESS_GNU or any([
        extra_tarball_compression.get(archive, "gz") == "gz"
        for archive in extra_tarballs
    ])

    # A package that names its own compiler does not get tinycc on PATH; the
    # point of naming one is that this is not a tinycc build.
    if not cc:
        tool_dir(
            name = name + "_tcc",
            tools = {"tcc": toolchain_tcc if uses_toolchain else tcc},
        )

    if stages_nothing:
        libc_directories = {}
        libc_srcs = []
    elif uses_toolchain:
        libc_directories = {"toolchain": toolchain}
        libc_srcs = [toolchain]
    else:
        libc_directories = {
            "tcc_libs": tcc_libs,
            "tcc_include": tcc_include,
            "mes_arch_include": "//tools/mes:arch_include_dir",
            "mes_include": "//tools/mes:header_dir",
        }
        libc_srcs = [
            tcc_src,
            "//tools/mes:arch_headers",
            "//tools/mes:header_dir",
        ]

    kaem_run(
        name = name,
        script = name + ".kaem",
        substitutions = dict(
            {
                "tarball": tarball,
                "driver": name + "_build.sh",
            },
            **dict(
                extra_tarballs,
                **dict(
                    extra_files,
                    **{_patch_variable(i): patches[i] for i in range(len(patches))}
                )
            )
        ),
        directory_substitutions = dict(libc_directories, **extra_directories),
        # The driver's first job is to rewrite PATH as absolute paths, so the
        # per-level copies kaem would otherwise add are dead weight -- and
        # this is where the tool list is longest, which is where kaem's
        # 4096-character limit on an environment variable bites first.
        path_levels = 1,
        make_concurrency = make_concurrency,
        srcs = [
            name + "_build.sh",
        ] + libc_srcs + extra_directories.values() + extra_files.values() + srcs,
        # Order matters: earlier directories win. coreutils has to come before
        # mescc-tools-extra, whose rm, cp and mkdir are single-purpose
        # stand-ins that take no options -- `rm -f` reaches the wrong one
        # otherwise and tries to delete a file called "-f".
        # A caller's extra tools come before the defaults so that a newer
        # build of something can replace the bootstrap one: sed 4.2 has to win
        # over sed 4.0.9 for any package whose configure autoconf generated.
        tools = ([] if cc else [
            name + "_tcc",
        ]) + tools + ([
            "//tools/pkg/gzip:bin",
        ] if needs_gnu_gzip else []) + [
            "//tools/pkg/coreutils:bin",
            "//tools/pkg/bash:bin",
            "//tools/pkg/gnugrep:bin",
            "//tools/pkg/gnumake:bin",
            "//tools/pkg/gnupatch:bin",
            "//tools/pkg/gnused:bin",
            "//tools/mescc-tools-extra:bin",
        ],
        **kwargs
    )
