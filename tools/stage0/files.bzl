"""File-shuffling rules that do not need a shell.

genrule and skylib's copy_file both run `cp` through the host shell, which the
bootstrap graph is not allowed to touch. Bazel can create symlinks itself, so
these rules do the same work as an internal action.
"""

def _relocate_impl(ctx):
    outputs = []
    for src in ctx.files.srcs:
        out = ctx.actions.declare_file(ctx.attr.prefix + "/" + src.basename)
        ctx.actions.symlink(output = out, target_file = src)
        outputs.append(out)

    return [DefaultInfo(files = depset(outputs))]

relocate_files = rule(
    implementation = _relocate_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Files to make visible under a different directory.",
        ),
        "prefix": attr.string(
            mandatory = True,
            doc = "Package-relative directory the files appear in, keeping their basenames.",
        ),
    },
    doc = """Exposes files under a different directory, by basename.

Mes source refers to its architecture headers as `arch/syscall.h` and friends;
upstream's ./configure satisfies that by copying the headers for the selected
target into an `arch` directory. This rule is the same trick without a shell.""",
)

ToolDirInfo = provider(
    doc = "A directory of executables, suitable for putting on PATH.",
    fields = {
        "path": "string: execroot-relative directory holding the tools",
        "files": "depset[File]: the tool symlinks and everything they need",
    },
)

def _tool_dir_impl(ctx):
    links = []
    for name, target in ctx.attr.tools.items():
        executable = target[DefaultInfo].files_to_run.executable
        if executable == None:
            fail("%s is not executable, so it cannot go in a tool directory" % target.label)

        # The name matters: M2-Mesoplanet and kaem look their helpers up by
        # bare name, so `M2-Planet` has to be called exactly that regardless of
        # which phase built it.
        link = ctx.actions.declare_file(ctx.label.name + "/" + name)
        ctx.actions.symlink(output = link, target_file = executable, is_executable = True)
        links.append(link)

    if not links:
        fail("a tool directory with no tools is never what was meant")

    return [
        ToolDirInfo(
            path = links[0].dirname,
            # The symlinks alone are not enough: an action that puts this
            # directory on PATH has to have the programs they point at staged
            # as well, along with anything those programs need at runtime.
            files = depset(links, transitive = [
                depset(
                    transitive = [
                        target[DefaultInfo].files,
                        target[DefaultInfo].default_runfiles.files,
                    ],
                )
                for target in ctx.attr.tools.values()
            ]),
        ),
        DefaultInfo(files = depset(links)),
    ]

tool_dir = rule(
    implementation = _tool_dir_impl,
    attrs = {
        "tools": attr.string_keyed_label_dict(
            allow_files = True,
            cfg = "exec",
            mandatory = True,
            doc = "Map of the name a tool must be found under to the target providing it.",
        ),
    },
    provides = [ToolDirInfo],
    doc = """Collects executables into one directory under their expected names.

Tools written for the bootstrap find each other through PATH by bare name:
M2-Mesoplanet spawns `M2-Planet`, `blood-elf`, `M1` and `hex2`, and kaem
scripts call `cp` and `mkdir`. Nothing in this repository is named that way on
disk, so this rule builds the directory those lookups expect.""",
)

def _source_path(f):
    """Returns a file's path relative to the repository that declares it.

    Args:
        f: A File.

    Returns:
        The repository-relative path, which for a file exported by
        `exports_files(glob(["**"]))` is exactly its label's name.
    """
    owner = f.owner
    if owner == None:
        return f.basename
    if owner.package:
        return owner.package + "/" + owner.name
    return owner.name

def _patched_tree_impl(ctx):
    # Substitutions are keyed by repository-relative path so a patch that no
    # longer applies is an error rather than a silent no-op.
    remaining = dict(ctx.attr.substitutions)

    outputs = []
    for src in ctx.files.srcs:
        relative = _source_path(src)
        out = ctx.actions.declare_file(ctx.attr.prefix + "/" + relative)
        outputs.append(out)

        pairs = ctx.attr.substitutions.get(relative)
        if pairs == None:
            ctx.actions.symlink(output = out, target_file = src)
            continue

        if len(pairs) % 2 != 0:
            fail("substitutions for %s must alternate match and replacement" % relative)
        replacements = {pairs[i]: pairs[i + 1] for i in range(0, len(pairs), 2)}

        # expand_template performs literal string replacement inside Bazel
        # itself, which is how a patch gets applied here without `patch`, `sed`
        # or a shell.
        ctx.actions.expand_template(
            template = src,
            output = out,
            substitutions = replacements,
        )
        remaining.pop(relative)

    if remaining:
        fail("no source matched these patch targets: %s" % sorted(remaining.keys()))

    return [DefaultInfo(files = depset(outputs))]

patched_tree = rule(
    implementation = _patched_tree_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Every file of the source tree, keeping its repository-relative layout.",
        ),
        "prefix": attr.string(
            mandatory = True,
            doc = "Package-relative directory the tree is staged under.",
        ),
        "substitutions": attr.string_list_dict(
            doc = """Patches, keyed by repository-relative path.

Each value is a flat list of alternating match and replacement strings, since
Starlark attributes cannot hold a dict of dicts.""",
        ),
    },
    doc = """Stages a source tree with literal string patches applied.

Upstream bootstraps apply these edits with a `replace` utility or with `sed`.
Neither exists yet at this point in the chain, and both would be host tools,
so the edits are done by Bazel's own template expansion instead.""",
)
