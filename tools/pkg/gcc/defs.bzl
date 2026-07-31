"""Shared pieces of the GCC packages."""

def stamp_support_libraries(names):
    """Returns setup lines giving the in-tree support libraries one timestamp.

    GCC builds gmp, mpfr, mpc and isl in-tree when it finds them under those
    names, and kaem unpacks them beside the main tree rather than inside it.
    The driver's walk that evens out timestamps runs before the symlinks that
    reach them exist, so without this they keep the timestamps untar gave them
    -- which is the order they appear in their archive, turned into an order
    in time.

    That matters because a release tarball ships generated files beside the
    sources they were generated from: Makefile.in beside Makefile.am,
    configure beside configure.ac, aclocal.m4 beside both. Whichever of a pair
    lands later is newer, so make decides the generated file is stale and
    reaches for automake, autoconf or aclocal, none of which exist here. In
    mpfr 2.4.2 it surfaces as a re-run of configure that then fails its own
    sanity check:

        mpfr/missing: line 52: aclocal-1.11: command not found
        configure: error: newly created file is older than distributed files!

    and in isl 0.24 as a rule that cannot run at all:

        make[2]: *** [../.././isl/Makefile.in] Error 1

    Whether it happens depends on how the archive's writes fall against the
    clock, so it varies from package to package and from run to run. One
    timestamp for each tree settles all of it, exactly as the driver already
    does for the main tree.

    Args:
        names: The symlink names to stamp, as they appear in the GCC tree.

    Returns:
        A list of shell lines, to be used inside extra_setup after the
        symlinks have been made.
    """
    return [
        "# See stamp_support_libraries in //tools/pkg/gcc:defs.bzl.",
        "shopt -s dotglob",
        "for support_library in %s; do" % " ".join(names),
        "  prepare_source_tree \"$support_library\"",
        "done",
        "shopt -u dotglob",
    ]

# Fold libsupc++.a into libstdc++.a, which is where it belongs.
#
# A normally configured GCC builds libstdc++.a out of libtool convenience
# archives and libsupc++convenience.la is one of them, so the libstdc++.a it
# installs already carries the exception machinery, the type information and
# operator new and delete. The libstdc++.a these packages install does not:
#
#     $ ar t libstdc++.a | wc -l      # 73 members
#     $ ar t libsupc++.a | wc -l      # 48 members, none of them shared
#     $ nm libstdc++.a | grep -c ' T _ZdlPv'     # 0
#
# so any C++ link that says only -lstdc++ ends with operator delete and
# __cxa_pure_virtual undefined. That is survivable for a caller this
# repository controls -- //toolchain could name -lsupc++ itself -- and not
# survivable for GCC's own build, which links its generator programs with a
# command line no configure flag reaches:
#
#     ld: build/read-md.o: in function `md_reader::~md_reader()':
#     read-md.c:(.text+0xce): undefined reference to `operator delete(void*)'
#     make[2]: *** [Makefile:2916: build/genmddeps] Error 1
#
# Merging the two archives afterwards makes libstdc++.a what every other GCC
# ships, and then nothing downstream has to know about any of this. The member
# names do not overlap, so no object is replaced.
#
# Which directory holds them depends on the release and on whether multilib
# was configured, so both spellings are tried rather than guessed at.
MERGE_LIBSUPCXX_INTO_LIBSTDCXX = [
    "# See MERGE_LIBSUPCXX_INTO_LIBSTDCXX in //tools/pkg/gcc:defs.bzl.",
    "for libdir in \"$out/lib64\" \"$out/lib\"; do",
    "  if [ -f \"$libdir/libsupc++.a\" ] && [ -f \"$libdir/libstdc++.a\" ]; then",
    "    (",
    "      supcxx_objects=\"$TMPDIR/libsupc++-objects\"",
    "      rm -rf \"$supcxx_objects\"",
    "      mkdir -p \"$supcxx_objects\"",
    "      cd \"$supcxx_objects\"",
    "      ar x \"$libdir/libsupc++.a\"",
    "      # D zeroes the timestamps and uids, so the same objects give the",
    "      # same archive.",
    "      ar rcsD \"$libdir/libstdc++.a\" *.o",
    "    )",
    "  fi",
    "done",
]
