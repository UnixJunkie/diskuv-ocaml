#!/bin/bash
# -------------------------------------------------------
# init-opam-root.sh PLATFORM
#
# Purpose:
# 1. Install an OPAMROOT (`opam init`) in $env:USERPROFILE/.opam or
#    the PLATFORM's opam-root/ folder.
# 2. Especially for Windows, optionally install a working
#    global Opam switch.
#
# When invoked?
# On Windows as part of `setup-userprofile.ps1`
# which is itself invoked by `install-world.ps1`. On both
# Windows and Unix it is also invoked as part of `build-sandbox-init.sh`.
#
# Prerequisites: A working build/_tools/common/ directory.
#
# -------------------------------------------------------
set -euf -o pipefail

# shellcheck disable=SC2034
PLATFORM=$1
shift

DKMLDIR=$(dirname "$0")
DKMLDIR=$(cd "$DKMLDIR/../.." && pwd)

# shellcheck disable=SC1091
source "$DKMLDIR"/runtime/unix/_common_tool.sh
# shellcheck disable=SC1091
source "$DKMLDIR"/.dkmlroot

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the TOPDIR (just like the container
# sets the directory to be /work mounted to TOPDIR)
cd "$TOPDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# BEGIN         ON-DEMAND VERSIONED GLOBAL INSTALLS
#
# The user experience for Unix is that `./makeit build-dev` should just work.
# Anything that is in DiskuvOCamlHome is really just for platforms like Windows
# that must have pre-installed software (for Windows that is MSYS2 or we couldn't
# even run this script).
#
# So ... try to do as much as possible in this section (or "ON-DEMAND OPAM ROOT INSTALLATIONS" below).

# TODO: These implementation won't work in containers; needs a mount point for the opam repositories, and
# an @@EXPAND_DKMLPARENTHOME@@ macro
set_dkmlparenthomedir

# Make versioned opam-repositories
#
# Q: Why is opam-repositories here rather than in DiskuvOCamlHome?
# The opam-repositories are required for Unix, not just Windows.
#
# Q: Why aren't we using an HTTP(S) site?
# Yep, we could have done `opam admin index`
# and followed the https://opam.ocaml.org/doc/Manual.html#Repositories instructions.
# It is not hard _but_ we want a) versioning of the repository to coincide with
# the version of Diskuv OCaml and b) ability to
# edit the repository for `AdvancedToolchain.rst` patching. We could have done
# both with HTTP(S) but simpler is usually better.

# shellcheck disable=SC2154
install -d "$DKMLPARENTHOME_BUILDHOST/opam-repositories/$dkml_root_version"
RSYNC_OPTS=(-a); if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then RSYNC_OPTS+=(--progress); fi
if is_windows_build_machine; then
    OPAMREPOS_MIXED=$(cygpath -am "$DKMLPARENTHOME_BUILDHOST\\opam-repositories\\$dkml_root_version")
    OPAMREPOS_UNIX=$(cygpath -au "$DKMLPARENTHOME_BUILDHOST\\opam-repositories\\$dkml_root_version")
    # shellcheck disable=SC2154
    DISKUVOCAMLHOME_UNIX=$(cygpath -au "$DiskuvOCamlHome")
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
    rsync "${RSYNC_OPTS[@]}" \
        "$DISKUVOCAMLHOME_UNIX/tools/ocaml-opam/$OPAM_PORT_FOR_SWITCHES_IN_WINDOWS-$OPAM_ARCH_IN_WINDOWS"/cygwin64/home/opam/opam-repository/ \
        "$OPAMREPOS_UNIX"/fdopen-mingw
    set +x
else
    OPAMREPOS_MIXED="$DKMLPARENTHOME_BUILDHOST/opam-repositories/$dkml_root_version"
    OPAMREPOS_UNIX="$OPAMREPOS_MIXED"
fi
if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
rsync "${RSYNC_OPTS[@]}" "$DKMLDIR"/etc/opam-repositories/ "$OPAMREPOS_UNIX"
set +x

# END           ON-DEMAND VERSIONED GLOBAL INSTALLS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# -----------------------
# BEGIN opam init

# Windows does not have a non-deprecated working Opam solution, so we choose
# to have $USERPROFILE/.opam be the Opam root for the dev platform. That is
# aligned with ~/.opam for Unix-y Opam. For Windows we also don't have a
# package manager that comes with `opam` pre-compiled, so we bootstrap an
# Opam installation from our Moby Docker downloaded of ocaml/opam image
# (see install-world.ps1).

# Set OPAMROOTDIR_BUILDHOST and OPAMROOTDIR_EXPAND
set_opamrootdir

# `opam init`.
#
# --disable-sandboxing: Can't nest Opam sandboxes inside of our Build Sandbox because nested chroots are not supported
# --no-setup: Don't modify user shell configuration (ex. ~/.profile). The home directory inside the Docker container
#             is not persistent anyways, so anything else would be useless.
OPAM_INIT_ARGS=(--disable-sandboxing --no-setup)
REPONAME_PENDINGREMOVAL=pendingremoval-opam-repo
if is_windows_build_machine; then
    # For Windows we set `opam init --bare` so we can configure its settings before adding the OCaml system compiler.
    # We'll use `pendingremoval` as a signal that we can remove it later if it is the 'default' repository
    OPAM_INIT_ARGS+=(--kind local --bare "$OPAMREPOS_MIXED/$REPONAME_PENDINGREMOVAL")
fi
if ! is_minimal_opam_root_present "$OPAMROOTDIR_BUILDHOST"; then
    "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" init "${OPAM_INIT_ARGS[@]}"
fi

# If and only if we have Windows Opam root we have to configure its global options
# to tell it to use `wget` instead of `curl`
if is_windows_build_machine && is_minimal_opam_root_present "$OPAMROOTDIR_BUILDHOST"; then
    WINDOWS_DOWNLOAD_COMMAND=wget

    # MSYS curl does not work with Opam. After debugging with `platform-opam-exec ... reinstall ocaml-variants --debug` found it was calling:
    #   C:\source\...\build\_tools\common\MSYS2\usr\bin\curl.exe --write-out %{http_code}\n --retry 3 --retry-delay 2 --user-agent opam/2.1.0 -L -o C:\Users\...\.opam\4.12\.opam-switch\sources\ocaml-variants\4.12.0.tar.gz.part -- https://github.com/ocaml/ocaml/archive/4.12.0.tar.gz
    # yet erroring with:
    #   [ERROR] Failed to get sources of ocaml-variants.4.12.0+msvc64: curl error code %http_coden
    # Seems like Windows command line processing is stripping braces and backslash (upstream bugfix: wrap --write-out argument with single quotes?).
    # Goes away with wget!! With wget has no funny symbols ... it is like:
    #   C:\source\...\build\_tools\common\MSYS2\usr\bin\wget.exe --content-disposition -t 3 -O C:\Users\...\AppData\Local\Temp\opam-29232-cc6ec1\inline-flexdll.patch.part -U opam/2.1.0 -- https://gist.githubusercontent.com/fdopen/fdc645a61a208552ebac76a67eafd3ee/raw/9f521e91c8f0e9490652651ccdbfae88da701919/inline-flexdll.patch
    if ! grep -q '^download-command: wget' "$OPAMROOTDIR_BUILDHOST/config"; then
        "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" option --yes --global download-command=$WINDOWS_DOWNLOAD_COMMAND
    fi
fi

# Make a `default` repo that is actually an overlay of diskuv-opam-repo and fdopen (only on Windows) and finally the offical Opam repository.
# If we don't we get make a repo named "default" in opam 2.1.0 the following will happen:
#     #=== ERROR while compiling ocamlbuild.0.14.0 ==================================#
#     Sys_error("C:\\Users\\user\\.opam\\repo\\default\\packages\\ocamlbuild\\ocamlbuild.0.14.0\\files\\ocamlbuild-0.14.0.patch: No such file or directory")
if [[ ! -e "$OPAMROOTDIR_BUILDHOST/repo/diskuv-$dkml_root_version" && ! -e "$OPAMROOTDIR_BUILDHOST/repo/diskuv-$dkml_root_version.tar.gz" ]]; then
    OPAMREPO_DISKUV="$OPAMREPOS_MIXED/diskuv-opam-repo"
    "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" repository add diskuv-"$dkml_root_version" "$OPAMREPO_DISKUV" --yes --dont-select --rank=1
fi
if is_windows_build_machine && [[ ! -e "$OPAMROOTDIR_BUILDHOST/repo/fdopen-mingw-$dkml_root_version" && ! -e "$OPAMROOTDIR_BUILDHOST/repo/fdopen-mingw-$dkml_root_version.tar.gz" ]]; then
    # Use the snapshot of fdopen-mingw (https://github.com/fdopen/opam-repository-mingw) that comes with ocaml-opam Docker image.
    # `--kind local` is so we get file:/// rather than git+file:/// which would waste time with git
    OPAMREPO_WINDOWS_OCAMLOPAM="$OPAMREPOS_MIXED/fdopen-mingw"
    "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" repository add fdopen-mingw-"$dkml_root_version" "$OPAMREPO_WINDOWS_OCAMLOPAM" --yes --dont-select --kind local --rank=2
fi
# check if we can remove 'default' if it was pending removal.
# sigh, we have to parse non-machine friendly output. we'll do safety checks.
if [[ -e "$OPAMROOTDIR_BUILDHOST/repo/default" || -e "$OPAMROOTDIR_BUILDHOST/repo/default.tar.gz" ]]; then
    DKML_BUILD_TRACE=OFF "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" repository list --all > "$WORK"/list
    awk '$1=="default" {print $2}' "$WORK"/list > "$WORK"/default
    _NUMLINES=$(awk 'END{print NR}' "$WORK"/default)
    if [[ "$_NUMLINES" -ne 1 ]]; then
        echo "FATAL: build-sandbox-init.sh does not understand the Opam repo format used at $OPAMROOTDIR_BUILDHOST/repo/default" >&2
        echo "FATAL: Details A:" >&2
        ls "$OPAMROOTDIR_BUILDHOST"/repo >&2
        echo "FATAL: Details B:" >&2
        cat "$WORK"/default
        echo "FATAL: Details C:" >&2
        cat "$WORK"/list
        exit 1
    fi
    if grep -q "/$REPONAME_PENDINGREMOVAL"$ "$WORK"/default; then
        # ok. is like file://C:/source/xxx/etc/opam-repositories/pendingremoval-opam-repo
        "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" repository remove default --yes --all --dont-select
    fi
fi
# add back the default we want if a default is not there
if [[ ! -e "$OPAMROOTDIR_BUILDHOST/repo/default" && ! -e "$OPAMROOTDIR_BUILDHOST/repo/default.tar.gz" ]]; then
    "$DKMLDIR"/runtime/unix/platform-opam-exec -p "$PLATFORM" repository add default https://opam.ocaml.org --yes --dont-select --rank=3
fi

# END opam init
# -----------------------

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# BEGIN         ON-DEMAND OPAM ROOT INSTALLATIONS

# We use the Opam plugin directory to hold our root-specific installations.
# http://opam.ocaml.org/doc/Manual.html#opam-root

# -----------------------

# Make versioned package config
#
# Q: Why is pkg-config here rather than in DiskuvOCamlHome?
#
# PKG_CONFIG_PATH is an Opam environment value that is logically tied to an Opam root.
# Each Opam root may belong to a different architecture, and PKG_CONFIG_PATH (especially
# cflags) should be able to vary based on architecture.
#
# We are forced to set it with in each switch because `opam option setenv=` is only
# available on the switch level (a limitation of Opam today), but the value is the same for
# all switches in the same Opam root.

PKGCONFIG_UNIX="$DKMLPLUGIN_BUILDHOST/pkgconfig/$dkml_root_version"
# shellcheck disable=SC2154
install -d "$PKGCONFIG_UNIX"
if is_windows_build_machine; then
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
    if [[ ! -e "$PKGCONFIG_UNIX"/libffi.pc ]]; then
        "$DiskuvOCamlHome"/tools/apps/dkml-templatizer.exe -o "$PKGCONFIG_UNIX"/libffi.pc.tmp "$DKMLDIR"/etc/pkgconfig/windows/libffi.pc
        mv "$PKGCONFIG_UNIX"/libffi.pc.tmp "$PKGCONFIG_UNIX"/libffi.pc
    fi
    set +x
fi

# END           ON-DEMAND OPAM ROOT INSTALLATIONS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
