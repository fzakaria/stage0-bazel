"""Proves that the bootstrap graph never invokes a host toolchain.

A bootstrap is only worth the name if the set of binaries it trusts is
knowable. This aspect makes that set explicit: it walks every action reachable
from a target and asserts that the program each action executes was itself
produced by an earlier action in the same graph, with the single documented
exception of the hand-auditable hex0 seed.

Any host compiler, assembler, linker or shell that crept into the graph shows
up here as an executable living outside `bazel-out/`, and analysis fails.
"""

# Bazel places every generated file under this prefix. An action whose
# executable lives here was, by construction, built by this repository.
_GENERATED_PREFIX = "bazel-out/"

# The one binary we take on trust. It is 357 bytes of hand-checkable machine
# code from oriansj/bootstrap-seeds and is the root of the whole chain.
_SEED_SUFFIXES = [
    "POSIX/x86/hex0-seed",
    "POSIX/AMD64/hex0-seed",
]

# Actions Bazel performs itself (symlinking, writing a file, expanding a
# template). They run inside the Bazel server rather than executing a program,
# so they have no argv to inspect and cannot smuggle in a host tool.
_INTERNAL_MNEMONICS = [
    "Symlink",
    "SymlinkFile",
    "SolibSymlink",
    "ExecutableSymlink",
    "FileWrite",
    "TemplateExpand",
    "SourceSymlinkManifest",
    "SymlinkTree",
    "Middleman",
    "ActionFileWrite",
]

TrustInfo = provider(
    doc = "Executables an action subgraph depends on, split by trustworthiness.",
    fields = {
        "violations": "depset of strings describing actions that ran an untrusted program",
        "trusted_seeds": "depset of exec paths of allowlisted seed binaries that were executed",
        "inputs": "depset[File]: every file any action in the subgraph consumed",
    },
)

def _is_seed(path):
    """Reports whether `path` is one of the allowlisted bootstrap seeds.

    Args:
        path: The exec path of an action's executable.

    Returns:
        True when the path names a seed binary from `_SEED_SUFFIXES`.
    """
    for suffix in _SEED_SUFFIXES:
        if path.endswith(suffix):
            return True
    return False

def _describe_violation(label, action, program):
    """Builds the human-readable message for a single untrusted execution.

    Args:
        label: The label of the target that registered the action.
        action: The offending action.
        program: The exec path of the program the action runs.

    Returns:
        A one-line description naming the target, mnemonic and program.
    """
    return "%s: action %s runs untrusted program %s" % (label, action.mnemonic, program)

def _no_native_toolchain_aspect_impl(target, ctx):
    violations = []
    seeds = []
    action_inputs = []

    # Inspect the program each action actually execs. Internal actions have an
    # empty argv and are handled by Bazel itself, so they are skipped.
    for action in target.actions:
        # Inputs are collected for every action, including the internal ones:
        # an attestation about what the build reads has to cover the files
        # Bazel itself copies and expands, not only the ones it execs on.
        action_inputs.append(action.inputs)

        if action.mnemonic in _INTERNAL_MNEMONICS:
            continue

        argv = action.argv
        if not argv:
            continue

        program = argv[0]
        if program.startswith(_GENERATED_PREFIX):
            continue

        if _is_seed(program):
            seeds.append(program)
            continue

        violations.append(_describe_violation(str(target.label), action, program))

    # Fold in whatever the dependencies found, so the root target sees the
    # verdict for the entire transitive graph.
    transitive_violations = []
    transitive_seeds = []
    transitive_inputs = []
    for attr_name in dir(ctx.rule.attr):
        for dep in _deps_of(ctx.rule.attr, attr_name):
            if TrustInfo in dep:
                transitive_violations.append(dep[TrustInfo].violations)
                transitive_seeds.append(dep[TrustInfo].trusted_seeds)
                transitive_inputs.append(dep[TrustInfo].inputs)

    return [TrustInfo(
        violations = depset(violations, transitive = transitive_violations),
        trusted_seeds = depset(seeds, transitive = transitive_seeds),
        inputs = depset(transitive = action_inputs + transitive_inputs),
    )]

def _deps_of(rule_attr, attr_name):
    """Normalises an attribute value into a list of Targets.

    Attributes may hold a single Target, a list of Targets, a label-keyed dict,
    or a plain value such as a string or bool. Only the Target-bearing shapes
    are of interest here.

    Args:
        rule_attr: The `ctx.rule.attr` struct being inspected.
        attr_name: Name of the attribute to normalise.

    Returns:
        A list of Targets, empty when the attribute holds no dependency.
    """
    value = getattr(rule_attr, attr_name, None)
    if type(value) == "Target":
        return [value]
    if type(value) == "list":
        return [item for item in value if type(item) == "Target"]
    if type(value) == "dict":
        return [item for item in value.values() if type(item) == "Target"]
    return []

no_native_toolchain_aspect = aspect(
    implementation = _no_native_toolchain_aspect_impl,
    attr_aspects = ["*"],
    provides = [TrustInfo],
    doc = "Collects the set of programs executed by a target's transitive actions.",
)

def _no_native_toolchain_audit_impl(ctx):
    violations = []
    seeds = []
    for dep in ctx.attr.targets:
        violations.extend(dep[TrustInfo].violations.to_list())
        seeds.extend(dep[TrustInfo].trusted_seeds.to_list())

    # Fail during analysis rather than at test time: a host compiler in the
    # graph is a defect in the build description, not a runtime surprise.
    if violations:
        fail("Bootstrap graph invokes programs it did not build:\n  " + "\n  ".join(sorted(violations)))

    report = ctx.actions.declare_file("%s.report" % ctx.label.name)
    ctx.actions.write(
        output = report,
        content = "\n".join([
            "Bootstrap trust report",
            "",
            "Every action in the checked graph runs a program built by this",
            "repository, except for these audited seed binaries:",
            "",
        ] + sorted(_unique(seeds)) + [""]),
    )

    return [DefaultInfo(files = depset([report]))]

def _unique(values):
    """Returns `values` with duplicates removed, preserving no particular order.

    Args:
        values: A list of strings.

    Returns:
        A list containing each distinct element of `values` once.
    """
    seen = {}
    for value in values:
        seen[value] = True
    return seen.keys()

no_native_toolchain_audit = rule(
    implementation = _no_native_toolchain_audit_impl,
    attrs = {
        "targets": attr.label_list(
            mandatory = True,
            aspects = [no_native_toolchain_aspect],
            doc = "Roots of the bootstrap graph to audit.",
        ),
    },
    doc = """Fails analysis if the bootstrap graph executes an unbuilt program.

Building this target is the check; it emits a report listing the seed
binaries that were trusted.""",
)
