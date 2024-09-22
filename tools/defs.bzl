"""def.bzl contains public definitions for stage0 rules.

"""

load(
    "//tools/internal:rules.bzl",
    _hex0_binary = "hex0_binary",
)

hex0_binary = _hex0_binary