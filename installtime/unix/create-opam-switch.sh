#!/bin/bash
# -------------------------------------------------------
# create-opam-switch.sh [-b BUILDTYPE -p PLATFORM | [-b BUILDTYPE] -s]
#
# Purpose: 
# 1. Create an OPAMSWITCH (`opam switch create`) as
#    a local switch that corresponds to the PLATFORM's BUILDTYPE
#    or to the 'diskuv-system' switch. The created switch will have a working
#    OCaml system compiler.
#
# Prerequisites:
# * An OPAMROOT created by `init-opam-root.sh`
#
# -------------------------------------------------------
set -euf -o pipefail

PINNED_PACKAGES=(
    # The format is `PACKAGE_NAME,PACKAGE_VERSION`. Notice the **comma**!
    "dune-configurator,2.9.0"
    "bigstringaf,0.8.0"
    "ppx_expect,v0.14.1"
    "digestif,1.0.1"
)

# ------------------
# BEGIN Command line processing

function usage () {
    echo "Usage:" >&2
    echo "    create-opam-switch.sh -h                        Display this help message." >&2
    echo "    create-opam-switch.sh -b BUILDTYPE -p PLATFORM  Create the Opam switch." >&2
    echo "    create-opam-switch.sh [-b BUILDTYPE] -s         Create the diskuv-system switch." >&2
    echo "Options:" >&2
    echo "       -p PLATFORM: The target platform or 'dev'" >&2
    echo "       -s: Select the 'diskuv-system' switch" >&2
    echo "       -b BUILDTYPE: Optional. The build type. If specified will create the switch" >&2
    echo "            in the build directory that corresponds to BUILDTYPE. Otherwise creates" >&2
    echo "            a global switch" >&2
}

PLATFORM=
BUILDTYPE=
DISKUV_SYSTEM_SWITCH=OFF
while getopts ":h:b:p:s" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        p )
            PLATFORM=$OPTARG
        ;;
        b )
            BUILDTYPE=$OPTARG
        ;;
        s )
            DISKUV_SYSTEM_SWITCH=ON
        ;;
        \? )
            echo "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [[ -z "$PLATFORM" && "$DISKUV_SYSTEM_SWITCH" = OFF ]]; then
    usage
    exit 1
elif [[ -n "$PLATFORM" && -z "$BUILDTYPE" ]]; then
    usage
    exit 1
fi

# END Command line processing
# ------------------

DKMLDIR=$(dirname "$0")
DKMLDIR=$(cd "$DKMLDIR/../.." && pwd)
if [[ ! -e "$DKMLDIR/.dkmlroot" ]]; then echo "FATAL: Not embedded in a 'diskuv-ocaml' repository" >&2 ; exit 1; fi

# `diskuv-system` is the host architecture, so use `dev` as its platform
if [[ "$DISKUV_SYSTEM_SWITCH" = ON ]]; then
    PLATFORM=dev
fi

# shellcheck disable=SC1091
if [[ -n "${BUILDTYPE:-}" ]]; then
    # shellcheck disable=SC1091
    source "$DKMLDIR"/runtime/unix/_common_build.sh
else
    # shellcheck disable=SC1091
    source "$DKMLDIR"/runtime/unix/_common_tool.sh
fi
# shellcheck disable=SC1091
source "$DKMLDIR"/.dkmlroot

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the TOPDIR (just like the container
# sets the directory to be /work mounted to TOPDIR)
cd "$TOPDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# --------------------------------
# BEGIN opam switch create

if [[ "$DISKUV_SYSTEM_SWITCH" = ON ]]; then
    # Set $DiskuvOCamlHome and other vars
    autodetect_dkmlvars

    # Set OPAMROOTDIR_BUILDHOST and OPAMROOTDIR_EXPAND
    set_opamrootdir

    # Set OPAMSWITCHFINALDIR_BUILDHOST and OPAMSWITCHDIR_EXPAND of `diskuv-system` switch
    set_opamswitchdir_of_system
elif [[ -n "${BUILDTYPE:-}" ]]; then
    # Set OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_BUILDHOST, OPAMSWITCHDIR_EXPAND, OPAMSWITCHISGLOBAL
    set_opamrootandswitchdir
fi

# We'll set compiler options to:
# * use static builds for Linux platforms running in a (musl-based Alpine) container
# * use flambda optimization if a `Release*` build type
#
# Setting compiler options via environment variables (like CC and LIBS) has been available since 4.8.0 (https://github.com/ocaml/ocaml/pull/1840)
# but still has problems even as of 4.10.0 (https://github.com/ocaml/ocaml/issues/8648).
#
# The following has some of the compiler options we might use for `macos`, `linux` and `windows`:
#   https://github.com/ocaml/opam-repository/blob/bfc07c20d6846fffa49c3c44735905af18969775/packages/ocaml-variants/ocaml-variants.4.12.0%2Boptions/opam#L17-L47
#
# The following is for `macos`, `android` and `ios`:
#   https://github.com/EduardoRFS/reason-mobile/tree/master/sysroot
#
# Notes:
# * `ocaml-option-musl` has a good defaults for embedded systems. But we don't want to optimize for size on a non-embedded system.
#   Since we have fine grained information about whether we are on a tiny system (ie. ARM 32-bit) we set the CFLAGS ourselves.
# * Advanced: You can use OCAMLPARAM through `opam config set ocamlparam` (https://github.com/ocaml/opam-repository/pull/16619) or
#   just set it in `within-dev` or `sandbox-entrypoint.sh`.
OPAM_SWITCH_PREHOOK=
OCAML_OPTIONS=
OPAM_SWITCH_CFLAGS=
OPAM_SWITCH_CC=
OPAM_SWITCH_ASPP=
OPAM_SWITCH_AS=
# if is_reproducible_platform && [[ $PLATFORM = linux* ]]; then
#     # NOTE 2021/08/04: When this block is enabled we get the following error, which means the config is doing something that we don't know how to inspect ...
#
#     # === ERROR while compiling capnp.3.4.0 ========================================#
#     # context     2.0.8 | linux/x86_64 | ocaml-option-static.1 ocaml-variants.4.12.0+options | https://opam.ocaml.org#8b7c0fed
#     # path        /work/build/linux_x86_64/Debug/_opam/.opam-switch/build/capnp.3.4.0
#     # command     /work/build/linux_x86_64/Debug/_opam/bin/dune build -p capnp -j 5
#     # exit-code   1
#     # env-file    /work/build/_tools/linux_x86_64/opam-root/log/capnp-1-ebe0e0.env
#     # output-file /work/build/_tools/linux_x86_64/opam-root/log/capnp-1-ebe0e0.out
#     # ## output ###
#     # [...]
#     # /work/build/linux_x86_64/Debug/_opam/.opam-switch/build/stdint.0.7.0/_build/default/lib/uint56_conv.c:172: undefined reference to `get_uint128'
#     # /usr/lib/gcc/x86_64-alpine-linux-musl/10.3.1/../../../../x86_64-alpine-linux-musl/bin/ld: /work/build/linux_x86_64/Debug/_opam/lib/stdint/libstdint_stubs.a(uint64_conv.o): in function `uint64_of_int128':
#     # /work/build/linux_x86_64/Debug/_opam/.opam-switch/build/stdint.0.7.0/_build/default/lib/uint64_conv.c:111: undefined reference to `get_int128'
#
#     # NOTE 2021/08/03: `ocaml-option-static` seems to do nothing. No difference when running `dune printenv --verbose`
#     OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-static
# fi
if [[ $BUILDTYPE = Release* ]]; then
    OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-flambda
fi
if [[ $PLATFORM = linux_arm32* ]]; then
    # -Os optimizes for size. Useful for CPUs with small cache sizes. Confer https://wiki.gentoo.org/wiki/GCC_optimization
    OPAM_SWITCH_CFLAGS="$OPAM_SWITCH_CFLAGS -Os"
fi
if [[ $PLATFORM = *_x86 ]] || [[ $PLATFORM = linux_arm32* ]]; then
    OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-32bit
fi
if [[ $BUILDTYPE = ReleaseCompatPerf ]]; then
    OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-fp
elif [[ $BUILDTYPE = ReleaseCompatFuzz ]]; then
    OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-afl
fi
OPAM_SWITCH_CREATE_OPTS=(
    --yes
)

# Since there is no ocaml-variants.4.12.0+options+msvc64+msys2 all the compiler options are ignored for Windows!!!
# (There is an action item in etc/opam-repositories/diskuv-opam-repo/packages/ocaml-variants/ocaml-variants.4.12.0+msvc64+msys2/opam)
if is_windows_build_machine; then
    OPAM_SWITCH_CREATE_OPTS+=(
        --repos="diskuv-$dkml_root_version,fdopen-mingw-$dkml_root_version,default"
        --packages="ocaml-variants.$OCAML_VARIANT_FOR_SWITCHES_IN_WINDOWS"
    )
else
    OPAM_SWITCH_CREATE_OPTS+=(
        --repos="diskuv-$dkml_root_version,default"
        --packages="ocaml-variants.4.12.0+options$OCAML_OPTIONS"
    )
fi
if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then OPAM_SWITCH_CREATE_OPTS+=(--debug-level 2); fi

# We'll use the bash builtin `set` which quotes spaces correctly.
OPAM_SWITCH_PREHOOK="echo OPAMSWITCH=" # Ignore any switch the developer gave. We are creating our own.
if [[ -n "${OPAM_SWITCH_CFLAGS:-}" ]]; then OPAM_SWITCH_PREHOOK="$OPAM_SWITCH_PREHOOK; echo ';'; CFLAGS='$OPAM_SWITCH_CFLAGS'; set | grep ^CFLAGS="; fi
if [[ -n "${OPAM_SWITCH_CC:-}" ]]; then     OPAM_SWITCH_PREHOOK="$OPAM_SWITCH_PREHOOK; echo ';';     CC='$OPAM_SWITCH_CC'    ; set | grep ^CC="; fi
if [[ -n "${OPAM_SWITCH_ASPP:-}" ]]; then   OPAM_SWITCH_PREHOOK="$OPAM_SWITCH_PREHOOK; echo ';';   ASPP='$OPAM_SWITCH_ASPP'  ; set | grep ^ASPP="; fi
if [[ -n "${OPAM_SWITCH_AS:-}" ]]; then     OPAM_SWITCH_PREHOOK="$OPAM_SWITCH_PREHOOK; echo ';';     AS='$OPAM_SWITCH_AS'    ; set | grep ^AS="; fi

if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then echo "+ ! is_minimal_opam_switch_present \"$OPAMSWITCHFINALDIR_BUILDHOST\"" >&2; fi
if ! is_minimal_opam_switch_present "$OPAMSWITCHFINALDIR_BUILDHOST"; then
    # clean up any partial install
    "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" switch remove "$OPAMSWITCHDIR_EXPAND" --yes || \
        rm -rf "$OPAMSWITCHFINALDIR_BUILDHOST"
    # do real install
    "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" -1 "$OPAM_SWITCH_PREHOOK" \
        switch create "$OPAMSWITCHDIR_EXPAND" "${OPAM_SWITCH_CREATE_OPTS[@]}"
fi

# END opam switch create
# --------------------------------

# --------------------------------
# BEGIN opam pin add

# Create: pin.sh "$OPAMROOTDIR_EXPAND" "$OPAMSWITCHDIR_EXPAND"
{
    echo '#!/bin/bash'
    echo 'set -euf -o pipefail'
    # shellcheck disable=2016
    echo '_OPAMROOTDIR=$1'
    echo 'shift'
    # shellcheck disable=2016
    echo '_OPAMSWITCHDIR=$1'
    echo 'shift'
    if is_windows_build_machine; then
        # shellcheck disable=2016
        echo '_CYGPATH=$(which cygpath)'
    fi
    # shellcheck disable=2016
    echo 'eval $(opam env --root "$_OPAMROOTDIR" --switch "$_OPAMSWITCHDIR" --set-root --set-switch)'
    if is_windows_build_machine; then
        # PATH may be a Windows path. For now we need it to be a UNIX path or else commands
        # like 'opam' will not be found.
        # Always add in standard /usr/bin:/bin paths as well.
        # shellcheck disable=2016
        echo 'PATH=$($_CYGPATH --path "$PATH"):/usr/bin:/bin'
    fi
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then echo 'set -x'; fi
} > "$WORK"/pin.sh

if [[ "$DISKUV_SYSTEM_SWITCH" = ON ]]; then
    PLATFORM_OPAM_EXEC_OPTS=(-s)
else
    PLATFORM_OPAM_EXEC_OPTS=(-p "$PLATFORM")
fi
if [[ -n "${BUILDTYPE:-}" ]]; then
    PLATFORM_OPAM_EXEC_OPTS+=(-b "$BUILDTYPE")
fi

OPAM_PIN_ADD_OPTS=(--yes)
NEED_TO_PIN=OFF

# For Windows mimic the ocaml-opam Dockerfile by pinning `ocaml-variants` to our custom version
if is_windows_build_machine; then
    if ! get_opam_switch_state_toplevelsection "$OPAMSWITCHFINALDIR_BUILDHOST" pinned | grep -q "ocaml-variants.$OCAML_VARIANT_FOR_SWITCHES_IN_WINDOWS"; then
        echo "opam pin add ${OPAM_PIN_ADD_OPTS[*]} -k version ocaml-variants '$OCAML_VARIANT_FOR_SWITCHES_IN_WINDOWS'" >> "$WORK"/pin.sh
        NEED_TO_PIN=ON
    fi
fi

# Pin the versions of the packages for which we have patches (etc/opam-repositories/diskuv-opam-repo/packages)
# Each ___ in `for package_tuple in __ __ __` is `PACKAGE_NAME,PACKAGE_VERSION`. Notice the **comma**!
# Even though technically we may not need the patches for non-Windows systems, we want the same code
# running in both Unix and Windows, right?!
for package_tuple in "${PINNED_PACKAGES[@]}"; do
    IFS=',' read -r package_name package_version <<< "$package_tuple"
    # accumulate
    if ! get_opam_switch_state_toplevelsection "$OPAMSWITCHFINALDIR_BUILDHOST" pinned | grep -q "$package_name.$package_version"; then
        echo "opam pin add ${OPAM_PIN_ADD_OPTS[*]} -k version '$package_name' '$package_version'" >> "$WORK"/pin.sh
        NEED_TO_PIN=ON
    fi
done

# Execute all of the accumulated `opam pin add` at once
if [[ "$NEED_TO_PIN" = ON ]]; then
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
    "$DKMLDIR"/runtime/unix/platform-opam-exec "${PLATFORM_OPAM_EXEC_OPTS[@]}" exec -- bash "$WORK_EXPAND"/pin.sh "$OPAMROOTDIR_EXPAND" "$OPAMSWITCHDIR_EXPAND"
fi

# END opam pin add
# --------------------------------
