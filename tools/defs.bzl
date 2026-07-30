"""Public API of the stage0-bazel module.

Everything a downstream module needs is re-exported here, so consumers depend
on one stable label instead of reaching into tools/stage0/. The rules fall
into two groups: the stage0 primitives, which turn hex and macro assembly into
binaries, and the mescc rules, which compile C.
"""

load(
    "//tools/stage0:bloodelf.bzl",
    _blood_elf = "blood_elf",
)
load(
    "//tools/stage0:catm.bzl",
    _cat_files = "cat_files",
)
load(
    "//tools/stage0:files.bzl",
    _ToolDirInfo = "ToolDirInfo",
    _patched_tree = "patched_tree",
    _relocate_files = "relocate_files",
    _tool_dir = "tool_dir",
)
load(
    "//tools/stage0:hex0.bzl",
    _hex0_binary = "hex0_binary",
)
load(
    "//tools/stage0:hex1.bzl",
    _hex1_binary = "hex1_binary",
)
load(
    "//tools/stage0:hex2_1.bzl",
    _hex2_binary = "hex2_binary",
)
load(
    "//tools/stage0:m1.bzl",
    _m1_expand = "m1_expand",
)
load(
    "//tools/stage0:m2.bzl",
    _m2_compile = "m2_compile",
)
load(
    "//tools/stage0:kaem.bzl",
    _kaem_run = "kaem_run",
)
load(
    "//tools/stage0:mes.bzl",
    _MesInfo = "MesInfo",
    _mes_distribution = "mes_distribution",
    _mes_scheme_test = "mes_scheme_test",
)
load(
    "//tools/stage0:mesoplanet.bzl",
    _m2_mesoplanet_binary = "m2_mesoplanet_binary",
)
load(
    "//tools/stage0:mescc.bzl",
    _MesccInfo = "MesccInfo",
    _mescc_archive = "mescc_archive",
    _mescc_binary = "mescc_binary",
    _mescc_library = "mescc_library",
    _mescc_object = "mescc_object",
    _mescc_toolchain = "mescc_toolchain",
)

# Stage0 primitives. Use these to extend the bootstrap itself; ordinary code
# should use the mescc rules below.
blood_elf = _blood_elf
cat_files = _cat_files
hex0_binary = _hex0_binary
hex1_binary = _hex1_binary
hex2_binary = _hex2_binary
m1_expand = _m1_expand
m2_compile = _m2_compile

# Staging source trees, and collecting tools under the names that programs
# written for the bootstrap look them up by.
ToolDirInfo = _ToolDirInfo
patched_tree = _patched_tree
relocate_files = _relocate_files
tool_dir = _tool_dir

# M2-Mesoplanet, the C compiler driver used for small standalone programs.
m2_mesoplanet_binary = _m2_mesoplanet_binary

# kaem, the shell every package past tinycc is built with.
kaem_run = _kaem_run

# Mes, the Scheme interpreter the bootstrap hands off to.
MesInfo = _MesInfo
mes_distribution = _mes_distribution
mes_scheme_test = _mes_scheme_test

# mescc, the C compiler. README.md describes the subset of C it accepts.
MesccInfo = _MesccInfo
mescc_archive = _mescc_archive
mescc_binary = _mescc_binary
mescc_library = _mescc_library
mescc_object = _mescc_object
mescc_toolchain = _mescc_toolchain
