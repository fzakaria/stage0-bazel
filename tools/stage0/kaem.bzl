"""Run a build script under the bootstrapped kaem shell.

Everything after tinycc is built by `./configure && make`, which means the
bootstrap needs a way to run scripts. nixpkgs' minimal-bootstrap solves this
with one primitive, `kaem.runCommand`, and every one of its twenty-nine
packages is expressed in terms of it. This is that primitive for Bazel.

kaem is not a POSIX shell. It has no pipes, no redirection, no globbing, no
conditionals and no substitution beyond `${var}`; a line is a command and its
arguments. Anything more has to be a program, which is what mescc-tools-extra
provides.

The output is a directory rather than a set of files, because a `make install`
run decides its own file names. Bazel models that as a TreeArtifact.
"""

load("//tools/stage0:files.bzl", "ToolDirInfo")

# How many jobs a parallel make gets.
#
# One number serves two purposes and they have to be the same number: it is
# what `make -j` is told, and it is how many CPUs the action reserves from
# Bazel's local pool. If only the first were set, Bazel would still believe the
# action costs one CPU and would schedule fifteen more beside it.
#
# Eight rather than every core on the machine. A build host has other actions
# to run -- the bootstrap has long serial stretches where a second package can
# proceed in parallel -- and GCC's link steps are where the memory goes, so
# leaving headroom is worth more than the last few percent of a single package.
MAKE_JOBS = 8

# Roughly what one GCC compilation costs at peak, in megabytes. cc1plus on
# LLVM-sized translation units is the worst case in this repository; declaring
# it keeps Bazel from starting several parallel-make actions at once and
# handing the whole set to the OOM killer.
_MEGABYTES_PER_JOB = 1024

# Whether a package's make runs one recipe at a time or MAKE_JOBS of them.
#
# Serial is the default because most of these packages are small and some are
# old enough to have makefiles that were never tested in parallel. A package
# opts in when it is big enough for the difference to matter, and says so.
MAKE_SERIAL = "serial"

MAKE_PARALLEL = "parallel"

_MAKE_CONCURRENCY = [
    MAKE_SERIAL,
    MAKE_PARALLEL,
]

def _parallel_resources(os, inputs_size):
    """Returns what a parallel-make action reserves from Bazel's local pool.

    The signature is Bazel's: a resource_set callback cannot see the rule's
    attributes, which is why the job count is a module constant rather than
    something a caller can choose freely.

    Args:
        os: The execution platform's operating system. Unused; the bootstrap
            builds on Linux only.
        inputs_size: How many input files the action has. Unused; what this
            action costs is set by the compiler it runs, not by the size of
            the tree it reads.

    Returns:
        A resource dictionary for ctx.actions.run.
    """
    return {
        "cpu": MAKE_JOBS,
        "memory": MAKE_JOBS * _MEGABYTES_PER_JOB,
    }

# Prefixes that make an execroot-relative path work from a subdirectory. Three
# levels covers every recursive make in the bootstrap; a prefix that resolves
# to nothing is simply ignored by the tools that read these paths.
RELATIVE_PREFIXES = [
    "",
    "../",
    "../../",
    "../../../",
]

def _directory_root(target):
    """Returns the directory a target names.

    Args:
        target: A Target providing either a directory artifact or a set of
            files sharing a root.

    Returns:
        The path of that directory.
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

def _kaem_run_impl(ctx):
    tool_dirs = [target[ToolDirInfo] for target in ctx.attr.tools]
    out = ctx.actions.declare_directory(ctx.attr.output_dir or ctx.label.name)

    # kaem substitutes ${name} from its environment, so the script refers to
    # its inputs by name and the rule resolves those names to exec paths. That
    # keeps output paths, which are not knowable when the script is written,
    # out of the script itself.
    # Every tool directory appears once per directory level. Bazel cannot name
    # the execroot absolutely at analysis time, so PATH has to be relative --
    # and a build that descends, as a recursive make does, would otherwise
    # lose every tool it has. A relative PATH entry that does not resolve is
    # skipped, so the extra entries cost nothing at the top level.
    #
    # Earlier directories win, so a stage's own compiler shadows any tool of
    # the same name from the shared utility set.
    # A script that never descends -- or that rewrites PATH before it does --
    # needs only the plain entry, and kaem caps an environment variable at
    # 4096 characters. That is a real ceiling once this repository is a
    # dependency and every path grows an external/<module>+/ prefix.
    prefixes = RELATIVE_PREFIXES[:ctx.attr.path_levels]
    search_path = []
    for d in tool_dirs:
        for prefix in prefixes:
            search_path.append(prefix + d.path)

    env = {
        "PATH": ":".join(search_path),
        "out": out.path,
    }
    for name, target in ctx.attr.substitutions.items():
        files = target[DefaultInfo].files.to_list()
        if len(files) != 1:
            fail("%s produces %d files; a script variable must name exactly one" %
                 (target.label, len(files)))
        env[name] = files[0].path

    for name, directory in ctx.attr.directory_substitutions.items():
        env[name] = _directory_root(directory)

    env.update(ctx.attr.env)

    ctx.actions.run(
        outputs = [out],
        inputs = depset(
            direct = ctx.files.srcs + [ctx.file.script],
            transitive = [d.files for d in tool_dirs] + [
                target[DefaultInfo].files
                for target in ctx.attr.substitutions.values() +
                              ctx.attr.directory_substitutions.values()
            ],
        ),
        executable = ctx.executable.kaem,
        arguments = ["--verbose", "--strict", "--file", ctx.file.script.path],
        env = env,
        mnemonic = "KaemRun",
        progress_message = "Running %{label} under kaem",
        # A serial action keeps Bazel's default of one CPU; only a package
        # that actually runs make in parallel asks for more.
        resource_set = (
            _parallel_resources if ctx.attr.make_concurrency == MAKE_PARALLEL else None
        ),
    )

    return [DefaultInfo(files = depset([out]))]

kaem_run = rule(
    implementation = _kaem_run_impl,
    attrs = {
        "script": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The kaem script to run.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Files the script reads that it does not reach through a substitution.",
        ),
        "substitutions": attr.string_keyed_label_dict(
            allow_files = True,
            doc = "Script variables bound to the path of a single-file target.",
        ),
        "directory_substitutions": attr.string_keyed_label_dict(
            allow_files = True,
            doc = "Script variables bound to the root directory of a multi-file target.",
        ),
        "env": attr.string_dict(
            doc = "Literal environment entries, applied after the substitutions.",
        ),
        "make_concurrency": attr.string(
            default = MAKE_SERIAL,
            values = _MAKE_CONCURRENCY,
            doc = "MAKE_PARALLEL if the script runs make with -j MAKE_JOBS," +
                  " so that the action reserves that many CPUs. This changes" +
                  " only what Bazel reserves; the script itself has to pass" +
                  " the flag, which configure_package does.",
        ),
        "path_levels": attr.int(
            default = len(RELATIVE_PREFIXES),
            doc = "How many directory levels PATH has to work from. One means" +
                  " the script stays at the execroot, or fixes PATH itself" +
                  " before descending.",
        ),
        "output_dir": attr.string(
            doc = "Name of the output directory; defaults to the target name.",
        ),
        "tools": attr.label_list(
            providers = [ToolDirInfo],
            mandatory = True,
            doc = "Directories of programs the script may call, in PATH order.",
        ),
        "kaem": attr.label(
            executable = True,
            cfg = "exec",
            default = "//tools/stage0/phase11:kaem",
            doc = "The kaem shell.",
        ),
    },
    doc = """Runs a kaem script and captures the directory it populates.

The script gets `${out}`, an empty directory it is expected to fill, plus a
variable for every entry in `substitutions` and `directory_substitutions`.
`PATH` lists exactly the `tools` directories, so a script can only call
programs this repository built.""",
)
