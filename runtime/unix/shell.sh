#!/bin/bash
set -euf -o pipefail

PLATFORM=$1
shift
BUILDTYPE=$1 # may be empty
shift

DKMLDIR=$(dirname "$0")
DKMLDIR=$(cd "$DKMLDIR/../.." && pwd)
if [[ ! -e "$DKMLDIR/.dkmlroot" ]]; then echo "FATAL: Not embedded in a 'diskuv-ocaml' repository" >&2 ; exit 1; fi
TOPDIR=$(git -C "$DKMLDIR/.." rev-parse --show-toplevel)
TOPDIR=$(cd "$TOPDIR" && pwd)
if [[ ! -e "$TOPDIR/dune-project" ]]; then echo "FATAL: Not embedded in a Diskuv OCaml local project" >&2 ; exit 1; fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# shellcheck disable=1091
source "$DKMLDIR/runtime/unix/_common_tool.sh"
# shellcheck disable=SC1091
source "$DKMLDIR"/.dkmlroot # set $dkml_root_version

# _common_tool.sh functions expect us to be in $TOPDIR. We'll change directories later.
cd "$TOPDIR"

# Set PLATFORM_VCPKG_TRIPLET
platform_vcpkg_triplet

# Set OPAMROOTDIR_BUILDHOST and OPAMROOTDIR_EXPAND
set_opamrootdir

# If and only the Opam root exists ...
if is_minimal_opam_root_present "$OPAMROOTDIR_BUILDHOST"; then
    # Dump all the environment variables that Opam tells us
    SHELL_WINDOWS=$(cygpath -aw "$SHELL")
    if [[ -n "${BUILDTYPE:-}" ]]; then
        DKML_BUILD_TRACE=OFF "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" -b "$BUILDTYPE" exec -- "$SHELL_WINDOWS" -c set > "$WORK/1.sh"
    else
        DKML_BUILD_TRACE=OFF "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" exec -- "$SHELL_WINDOWS" -c set > "$WORK/1.sh"
    fi

    # Remove environment variables that are readonly (like UID) or simply should come from our
    # environment rather than platform-opam-exec (like DKML_BUILD_TRACE and TERM)
    grep -Ev '^(BASH.*|DKML_BUILD_TRACE|DKMAKE_.*|DIRSTACK|EUID|GROUPS|LOGON.*|MAKE.*|PPID|SHELLOPTS|TEMP|TERM|UID|USERDOMAIN.*|_)=' "$WORK/1.sh" |
        grep -E '^[A-Za-z0-9_]+=' |
        sed 's/^/export /' > "$WORK/2.sh"

    # Read the remaining environment variables into this shell
    # shellcheck disable=SC1091
    source "$WORK/2.sh"
fi

# Add tools to the PATH
PATH="$TOPDIR/$TOOLSDIR/local/bin:$TOPDIR/$TOOLSCOMMONDIR/local/bin:$PATH"

# Add vcpkg packages to the PATH
# shellcheck disable=SC2154
VCPKG_INSTALLED="$DKMLPLUGIN_BUILDHOST/vcpkg/$dkml_root_version/installed/$PLATFORM_VCPKG_TRIPLET"
if is_windows_build_machine; then VCPKG_INSTALLED=$(cygpath -au "$VCPKG_INSTALLED"); fi
PATH="$VCPKG_INSTALLED/bin:$VCPKG_INSTALLED/tools/pkgconf:$PATH"

# On Windows ...
if [[ -n "${LOCALAPPDATA:-}" ]]; then
    # Add VS Code to the PATH (if it exists)
    LOCALAPPDATA_UNIX=$(cygpath -au "$LOCALAPPDATA")
    if [[ -e "$LOCALAPPDATA_UNIX/Programs/Microsoft VS Code/bin/code" ]]; then
        PATH="$LOCALAPPDATA_UNIX/Programs/Microsoft VS Code/bin:$PATH"
    fi
fi

# Basic command prompt
if [[ -n "${BUILDTYPE:-}" ]]; then
    LABEL="$PLATFORM-$BUILDTYPE"
else
    LABEL="$PLATFORM"
fi
PS1='\[\e]0;\[\033[01;32m\]'$LABEL'@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
export PS1

# Change directory to where we were invoked
if [[ -n "${DKMAKE_CALLING_DIR:-}" ]]; then
    cd "$DKMAKE_CALLING_DIR"
fi


# Get rid of environment variables that shouldn't be seen
unset DKMAKE_CALLING_DIR DKMAKE_INTERNAL_MAKE MAKEFLAGS MAKE_TERMERR MAKELEVEL

# Must clean WORK because we are about to do an exec
rm -rf "$WORK"

exec "$SHELL" --noprofile --norc -i
