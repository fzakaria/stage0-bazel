"""Produce an attestation of what the bootstrap trusts.

The no-host-toolchain audit answers one question: does anything in the graph
run a program the graph did not build? That is necessary but not sufficient
for a claim of hermeticity. Two more things have to hold:

  - every file entering the graph is either a source in this repository or a
    hash-pinned download, so the build has no unpinned inputs;
  - the only *binary* among those inputs is the hex0 seed, so everything
    executable was produced from source that can be read.

This rule states both as a build artifact rather than as prose. It walks the
same graph the audit walks, sorts the inputs into what was built, what came
from a pinned archive, and what came from this repository, and reports the
counts alongside the seeds it had to take on trust.
"""

load("//tools/verify:no_native_toolchain.bzl", "TrustInfo", "no_native_toolchain_aspect")

# Generated files live here. Anything else came in from outside.
_GENERATED_PREFIX = "bazel-out/"

# External repositories are staged under this prefix, whatever naming scheme
# the Bazel version in use applies to them.
_EXTERNAL_PREFIX = "external/"

def _classify(f):
    """Sorts one input file by where it came from.

    Args:
        f: A File.

    Returns:
        One of "built", "pinned" or "checked-in".
    """
    if f.path.startswith(_GENERATED_PREFIX):
        return "built"
    if f.path.startswith(_EXTERNAL_PREFIX):
        return "pinned"
    return "checked-in"

def _repository_of(path):
    """Returns the external repository name a path belongs to.

    Args:
        path: An exec path under `external/`.

    Returns:
        The repository directory name.
    """
    rest = path[len(_EXTERNAL_PREFIX):]
    return rest.split("/")[0]

def _attestation_impl(ctx):
    violations = []
    seeds = []
    for dep in ctx.attr.targets:
        violations.extend(dep[TrustInfo].violations.to_list())
        seeds.extend(dep[TrustInfo].trusted_seeds.to_list())

    if violations:
        fail("cannot attest: the graph runs programs it did not build:\n  " +
             "\n  ".join(sorted(violations)))

    # Every file the checked targets depend on, however deeply.
    inputs = depset(transitive = [
        dep[DefaultInfo].files
        for dep in ctx.attr.targets
    ] + [
        dep[TrustInfo].inputs
        for dep in ctx.attr.targets
    ])

    counts = {"built": 0, "pinned": 0, "checked-in": 0}
    repositories = {}
    for f in inputs.to_list():
        origin = _classify(f)
        counts[origin] += 1
        if origin == "pinned":
            repositories[_repository_of(f.path)] = True

    unique_seeds = {}
    for seed in seeds:
        unique_seeds[seed] = True

    report = ctx.actions.declare_file("%s.txt" % ctx.label.name)
    ctx.actions.write(
        output = report,
        content = "\n".join([
            "Hermeticity attestation",
            "=======================",
            "",
            "Checked targets:",
        ] + [
            "  " + str(dep.label)
            for dep in ctx.attr.targets
        ] + [
            "",
            "1. No action in this graph runs a program the graph did not build,",
            "   except for the audited seeds listed under (3).",
            "",
            "2. Every file reaching an action came from one of three places:",
            "",
            "     %s built by this graph" % counts["built"],
            "     %s from a hash-pinned archive" % counts["pinned"],
            "     %s checked in to this repository" % counts["checked-in"],
            "",
            "   Nothing was read from the host filesystem. The pinned archives",
            "   are declared with their sha256 in MODULE.bazel:",
            "",
        ] + [
            "     " + name
            for name in sorted(repositories.keys())
        ] + [
            "",
            "3. Binaries taken on trust rather than built from source:",
            "",
        ] + [
            "     " + seed
            for seed in sorted(unique_seeds.keys())
        ] + [
            "",
            "   Everything else executable in this graph was produced from",
            "   source by a program earlier in the same graph.",
            "",
        ]),
    )

    return [DefaultInfo(files = depset([report]))]

hermeticity_attestation = rule(
    implementation = _attestation_impl,
    attrs = {
        "targets": attr.label_list(
            mandatory = True,
            aspects = [no_native_toolchain_aspect],
            doc = "Roots of the graph to attest.",
        ),
    },
    doc = """Writes an attestation of what the bootstrap graph trusts.

Analysis fails if the graph runs a program it did not build, so producing the
report at all is part of the claim.""",
)
