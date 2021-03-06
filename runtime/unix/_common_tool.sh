#!/bin/bash
#################################################
# _common_tool.sh
#
# Inputs:
#   DKMLDIR: The 'diskuv-ocaml' vendored directory containing '.dkmlroot'.
#   TOPDIR: Optional. The project top directory containing 'dune-project'. If
#     not specified it will be discovered from DKMLDIR.
#   PLATFORM: One of the PLATFORMS defined in TOPDIR/Makefile
#
#################################################

function is_dev_platform () {
    if [[ "$PLATFORM" = "dev" ]]; then
        return 0
    fi
    return 1
}

function is_reproducible_platform () {
    if [[ "$PLATFORM" = "dev" ]]; then
        return 1
    fi
    return 0
}

if [[ ! -e "$DKMLDIR/.dkmlroot" ]]; then echo "FATAL: Not embedded in a 'diskuv-ocaml' repository" >&2 ; exit 1; fi

if [[ -z "${TOPDIR:-}" ]]; then
    # Check at most 10 ancestors
    TOPDIR=$(cd "$DKMLDIR"/.. && pwd)
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" && ! "$TOPDIR" = "/" ]]; then TOPDIR=$(cd "$TOPDIR"/.. && pwd); fi
    if [[ ! -e "$TOPDIR/dune-project" ]]; then echo "FATAL: Not embedded in a Diskuv OCaml local project" >&2 ; exit 1; fi
fi

# Temporary directory that needs to be accessible inside and outside of containers so shell scripts
# can be sent from the outside of a container into a container.
# So we make $WORK be a subdirectory of $TOPDIR.
# Our use of mktemp needs to be portable; docs at:
# * BSD: https://www.freebsd.org/cgi/man.cgi?query=mktemp&sektion=1
# * GNU: https://www.gnu.org/software/autogen/mktemp.html
# Use $WORK in all situations except:
# * Use $WORK_EXPAND to communicate the location of a temporary shell script as an argument to `exec_in_platform`
# * Use $WORK_EXPAND_UNIX to communicate the location of a temporary shell script as a UNIX-path argument to `exec_in_platform`
TMPPARENTDIR_RELTOP="build/_tmp"
TMPPARENTDIR_BUILDHOST="$TOPDIR/$TMPPARENTDIR_RELTOP"
install -d "$TMPPARENTDIR_BUILDHOST"
if [[ -x /usr/bin/setfacl ]]; then /usr/bin/setfacl --remove-all --remove-default "$TMPPARENTDIR_BUILDHOST"; fi
WORK=$(env TMPDIR="$TMPPARENTDIR_BUILDHOST" mktemp -d)
trap 'rm -rf "$WORK"' EXIT
WORK_BASENAME=$(basename "$WORK")
# shellcheck disable=SC2034
WORK_EXPAND="@@EXPAND_TOPDIR@@/$TMPPARENTDIR_RELTOP/$WORK_BASENAME"
# shellcheck disable=SC2034
WORK_EXPAND_UNIX="@@EXPAND_TOPDIR_UNIX@@/$TMPPARENTDIR_RELTOP/$WORK_BASENAME"
unset WORK_BASENAME

# shellcheck disable=SC1091
source "$DKMLDIR/etc/contexts/linux-build/crossplatform-functions.sh"

# shellcheck disable=SC2034
TOOLSDIR="build/_tools/$PLATFORM"
# shellcheck disable=SC2034
TOOLSCOMMONDIR="build/_tools/common"
# shellcheck disable=SC2034
MULTIARCHTOOLSDIR="build/_tools/_multiarch"
# shellcheck disable=SC2034
OPAMROOT_IN_CONTAINER="$TOOLSDIR"/opam-root

#####
# BEGIN Opam in Windows
#
# Terminology: "port" is msvc or mingw, and described in https://discuss.ocaml.org/t/ann-ocaml-opam-images-for-docker-for-windows/8179
#
# We want to consistently use MSVC compiled libraries and executables so we don't have to debug hard-to-resolve cross-compiler
# issues ... we are using MSVC elsewhere (especially CMake) since it is far more widely adopted; it has way more package support.
# The only exception is when we are trying to compile a native Windows opam.exe within Cygwin. When using our Cygwin setup and the
# 4.12.0+msvc64 variant the ./autoconf for the package `ocaml-variants` detects the MSVC compiler and the Cygwin ld.exe which causes
# the build to break. So for bootstrapping opam.exe we use MinGW. (We don't expect this to happen with MSYS2 since MSYS2 is tested
# for this common cross-compiling on Windows scenario).
#
# We are downloading (install-world.ps1 / moby-download-docker-image.sh) the Docker `amd64`
# architecture (https://hub.docker.com/r/ocaml/opam/tags?page=1&ordering=last_updated&name=windows)
# for our binaries.
# shellcheck disable=SC2034
OPAM_ARCH_IN_WINDOWS=amd64
#
# shellcheck disable=SC2034
OPAM_PORT_FOR_OPAM_EXE_IN_WINDOWS=mingw # This should match OCAML_VARIANT_FOR_OPAM_EXE_IN_WINDOWS!
#
# The variant used for producing a native Windows opam.exe.
#
# Should match the build/_tools/common/ocaml-opam/$OPAM_PORT_FOR_OPAM_EXE_IN_WINDOWS-$OPAM_ARCH_IN_WINDOWS/Dockerfile.ocaml's variant
# that looks something like: `opam switch create 4.12 --packages=ocaml-variants.4.12.0+msvc64`.
# Variants were downloaded inside the Docker build for `ocaml-opam` from the repository at https://github.com/fdopen/opam-repository-mingw/tree/opam2/packages/ocaml-variants
# shellcheck disable=SC2034
OCAML_VARIANT_FOR_OPAM_EXE_IN_WINDOWS=4.12.0+mingw64c
#
# Which port we will use for all the switches in Windows except OCAML_VARIANT_FOR_OPAM_EXE_IN_WINDOWS.
#
# shellcheck disable=SC2034
OPAM_PORT_FOR_SWITCHES_IN_WINDOWS=msvc
#
# Which variant we will use for all the switches in Windows except OCAML_VARIANT_FOR_OPAM_EXE_IN_WINDOWS.
# Pick from a msys2 variant in $DiskuvOCamlHome/etc/opam-repositories/diskuv-opam-repo
# that aligns with the OPAM_PORT_FOR_SWITCHES_IN_WINDOWS.
# shellcheck disable=SC2034
OCAML_VARIANT_FOR_SWITCHES_IN_WINDOWS=4.12.0+msvc64+msys2
#
# END Opam in Windows
#####

# Execute a command either for the dev environment or for the
# reproducible sandbox corresponding to `$PLATFORM`
# which must be defined.
#
# When the optional `$BUILDTYPE` is non-empty the build type and
# corresponding environment variables (`DK_BUILD_TYPE`) will
# be available in the platform.
#
# Inputs:
#   env:PLATFORM          - required. which platform to run in
#   env:BUILDTYPE         - optional
#   env:COMPILATION       - optional. if set to OFF then no compilation tools
#                           like vcvars64.bat will be added to the environment
#                           which can be time consuming if not needed
#   env:PLATFORM_EXEC_PRE - optional. acts as hook.
#                           the specified bash statements, if any, are executed
#                           and their standard output captured. that standard
#                           output is 'eval'-d _before_ the command line
#                           arguments are executed.
#                           You can think of it behaving like:
#                             eval "$PLATFORM_EXEC_PRE" > /tmp/eval.sh
#                             eval /tmp/eval.sh
#   $@                    - the command line arguments that will be executed
#
# The text of the arguments $@ and PLATFORM_EXEC_PRE have any macros expanded:
#
#   @@EXPAND_WINDOWS_DISKUVOCAMLHOME@@: The directory containing dkmlvars.sh.
#     Only available when `is_windows_build_machine` is true (return code 0).
#     When running in MSYS2 the directory will be Windows style (ex. C:\)
#   @@EXPAND_WINDOWS_DISKUVOCAMLHOME_UNIX@@: The directory containing dkmlvars.sh.
#     Only available when `is_windows_build_machine` is true (return code 0).
#     The directory will always be Unix style (ex. /home/user).
#   @@EXPAND_WINDOWS_DISKUVOCAMLHOME_MIXED@@: The directory containing bin/ocaml.
#     Only available when `is_windows_build_machine` is true (return code 0).
#     The directory will always be mixed style (ex. C:/home/user).
#   @@EXPAND_TOPDIR@@: The top project directory containing `dune-project`.
#     When running in MSYS2 the directory will be Windows style (ex. C:\)
#   @@EXPAND_TOPDIR_UNIX@@: The top project directory containing `dune-project`.
#     The directory will always be Unix style (ex. /home/user).
#   @@EXPAND_DKMLDIR@@: The directory containing the vendored `diskuv-ocaml/.dkmlroot`.
#     When running in MSYS2 the directory will be Windows style (ex. C:\)
#   @@EXPAND_DKMLDIR_UNIX@@: The directory containing the vendored `diskuv-ocaml/.dkmlroot`.
#     The directory will always be Unix style (ex. /home/user).
function exec_in_platform () {
    _exec_dev_or_arch_helper "$PLATFORM" "$@"
}

# Execute a command either for the dev environment or for the
# reproducible sandbox corresponding to the build machine's architecture.
#
# When the optional `$BUILDTYPE` is non-empty the build type and
# corresponding environment variables (`DK_BUILD_TYPE`) will
# be available in the platform.
#
# Can do macro replacement of the arguments:
# @@EXPAND_WINDOWS_DISKUVOCAMLHOME@@: The directory containing bin/ocaml.
#   Only available when `is_windows_build_machine` is true (return code 0).
#   When running in MSYS2 the directory will be Windows style (ex. C:\)
# @@EXPAND_WINDOWS_DISKUVOCAMLHOME_UNIX@@: The directory containing bin/ocaml.
#   Only available when `is_windows_build_machine` is true (return code 0).
#   The directory will always be Unix style (ex. /home/user).
# @@EXPAND_WINDOWS_DISKUVOCAMLHOME_MIXED@@: The directory containing bin/ocaml.
#   Only available when `is_windows_build_machine` is true (return code 0).
#   The directory will always be mixed style (ex. C:/home/user).
# @@EXPAND_TOPDIR@@: The top directory containing dune-project.
#   When running in MSYS2 the directory will be Windows style (ex. C:\)
# @@EXPAND_TOPDIR_UNIX@@: The top project directory containing `dune-project`.
#   The directory will always be Unix style (ex. /home/user).
# @@EXPAND_DKMLDIR@@: The directory containing the vendored `diskuv-ocaml/.dkmlroot`.
#   When running in MSYS2 the directory will be Windows style (ex. C:\)
# @@EXPAND_DKMLDIR_UNIX@@: The directory containing the vendored `diskuv-ocaml/.dkmlroot`.
#   The directory will always be Unix style (ex. /home/user).
function exec_dev_or_multiarch () {
    build_machine_arch
    _exec_dev_or_arch_helper "$BUILDHOST_ARCH" "$@"
}

function _exec_dev_or_arch_helper () {
    local SANDBOX_PLATFORM
    SANDBOX_PLATFORM=$1
    shift
    local ARGS=()
    if [[ -n "${BUILDTYPE:-}" ]]; then
        ARGS+=(-b "$BUILDTYPE")
    fi
    if [[ "${COMPILATION:-}" = OFF ]]; then
        ARGS+=(-n)
    fi
    if is_dev_platform; then
        local ACTUALTOPDIR
        local ACTUALTOPDIR_UNIX
        if is_windows_build_machine && [[ -z "${DiskuvOCamlHome:-}" ]]; then
            echo "FATAL: You must run $DKMLDIR/installtime/windows/install-world.ps1 at least once" >&2
            exit 79
        fi
        if is_windows_build_machine; then
            ACTUALTOPDIR=$(cygpath -aw "$TOPDIR")
            ACTUALTOPDIR_UNIX=$(cygpath -au "$TOPDIR")
            ACTUALDKMLDIR=$(cygpath -aw "$DKMLDIR")
            ACTUALDKMLDIR_UNIX=$(cygpath -au "$DKMLDIR")
            ACTUALDISKUVOCAMLHOME=$(cygpath -aw "$DiskuvOCamlHome")
            ACTUALDISKUVOCAMLHOME_UNIX=$(cygpath -au "$DiskuvOCamlHome")
            ACTUALDISKUVOCAMLHOME_MIXED=$(cygpath -am "$DiskuvOCamlHome")
        else
            ACTUALTOPDIR="$TOPDIR"
            ACTUALTOPDIR_UNIX="$TOPDIR"
            ACTUALDKMLDIR="$DKMLDIR"
            ACTUALDKMLDIR_UNIX="$DKMLDIR"
        fi
        local ARG
        for ARG in "$@"; do
            ARG="${ARG//@@EXPAND_TOPDIR@@/$ACTUALTOPDIR}"
            ARG="${ARG//@@EXPAND_TOPDIR_UNIX@@/$ACTUALTOPDIR_UNIX}"
            ARG="${ARG//@@EXPAND_DKMLDIR@@/$ACTUALDKMLDIR}"
            ARG="${ARG//@@EXPAND_DKMLDIR_UNIX@@/$ACTUALDKMLDIR_UNIX}"
            if is_windows_build_machine; then
                ARG="${ARG//@@EXPAND_WINDOWS_DISKUVOCAMLHOME@@/$ACTUALDISKUVOCAMLHOME}"
                ARG="${ARG//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_UNIX@@/$ACTUALDISKUVOCAMLHOME_UNIX}"
                ARG="${ARG//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_MIXED@@/$ACTUALDISKUVOCAMLHOME_MIXED}"
            fi
            ARGS+=("$ARG")
        done
        if [[ -n "${PLATFORM_EXEC_PRE:-}" ]]; then
            ACTUAL_PRE_HOOK="$PLATFORM_EXEC_PRE"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_TOPDIR@@/$ACTUALTOPDIR}"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_TOPDIR_UNIX@@/$ACTUALTOPDIR_UNIX}"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_DKMLDIR@@/$ACTUALDKMLDIR}"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_DKMLDIR_UNIX@@/$ACTUALDKMLDIR_UNIX}"
            if is_windows_build_machine; then
                ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_WINDOWS_DISKUVOCAMLHOME@@/$ACTUALDISKUVOCAMLHOME}"
                ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_UNIX@@/$ACTUALDISKUVOCAMLHOME_UNIX}"
                ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_MIXED@@/$ACTUALDISKUVOCAMLHOME_MIXED}"
            fi
        fi
        if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
        "$DKMLDIR"/runtime/unix/within-dev -1 "${ACTUAL_PRE_HOOK:-}" "${ARGS[@]}"
        set +x
    else
        local 
        for ARG in "$@"; do
            ARG="${ARG//@@EXPAND_TOPDIR@@//work}"
            ARG="${ARG//@@EXPAND_TOPDIR_UNIX@@//work}"
            ARG="${ARG//@@EXPAND_WINDOWS_DISKUVOCAMLHOME@@//opt/diskuv-ocaml}"
            ARG="${ARG//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_UNIX@@//opt/diskuv-ocaml}"
            ARG="${ARG//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_MIXED@@//opt/diskuv-ocaml}"
            ARGS+=("$ARG")
        done
        if [[ -n "${PLATFORM_EXEC_PRE:-}" ]]; then
            ACTUAL_PRE_HOOK="$PLATFORM_EXEC_PRE"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_TOPDIR@@//work}"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_TOPDIR_UNIX@@//work}"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_WINDOWS_DISKUVOCAMLHOME@@//opt/diskuv-ocaml}"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_UNIX@@//opt/diskuv-ocaml}"
            ACTUAL_PRE_HOOK="${ACTUAL_PRE_HOOK//@@EXPAND_WINDOWS_DISKUVOCAMLHOME_MIXED@@//opt/diskuv-ocaml}"
        fi
        if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
        "$DKMLDIR"/runtime/unix/within-sandbox -p "$SANDBOX_PLATFORM" -1 "${ACTUAL_PRE_HOOK:-}" "${ARGS[@]}"
        set +x
    fi
}

# Set the parent directory of DiskuvOCamlHome.
#
# Always defined, even on Unix. It is your responsibility to check if it exists.
#
# Outputs:
# - env:DKMLPARENTHOME_BUILDHOST
function set_dkmlparenthomedir () {
    if is_windows_build_machine; then
        DKMLPARENTHOME_BUILDHOST="$LOCALAPPDATA\\Programs\\DiskuvOCaml"
    else
        # shellcheck disable=SC2034
        DKMLPARENTHOME_BUILDHOST="${XDG_DATA_HOME:-$HOME/.local/share}/diskuv-ocaml"
    fi
}

# Detects DiskuvOCaml and sets its variables.
#
# If the environment variables already exist they are not overwritten.
# Setting these variables is useful for example _during_ a deployment, where the
# version of dkmlvars.sh in the filesystem is either pre-deployment (too old) or not present.
#
# Inputs:
# - env:DiskuvOCamlVarsVersion - optional
# - env:DiskuvOCamlHome - optional
# - env:DiskuvOCamlBinaryPaths - optional
# Outputs:
# - env:DKMLPARENTHOME
# - env:DiskuvOCamlVarsVersion
# - env:DiskuvOCamlHome
# - env:DiskuvOCamlBinaryPaths
function autodetect_dkmlvars () {
    local DiskuvOCamlVarsVersion_Override=${DiskuvOCamlVarsVersion:-}
    local DiskuvOCamlHome_Override=${DiskuvOCamlHome:-}
    local DiskuvOCamlBinaryPaths_Override=${DiskuvOCamlBinaryPaths:-}
    set_dkmlparenthomedir
    if is_windows_build_machine; then
        if [[ -e "$DKMLPARENTHOME_BUILDHOST\\dkmlvars.sh" ]]; then
            # shellcheck disable=SC1090
            source "$DKMLPARENTHOME_BUILDHOST\\dkmlvars.sh"
        fi
    else
        if [[ -e "$DKMLPARENTHOME_BUILDHOST/dkmlvars.sh" ]]; then
            # shellcheck disable=SC1091
            source "$DKMLPARENTHOME_BUILDHOST/dkmlvars.sh"
        fi
    fi
    # Overrides
    if [[ -n "${DiskuvOCamlVarsVersion_Override:-}" ]]; then DiskuvOCamlVarsVersion="$DiskuvOCamlVarsVersion_Override"; fi
    if [[ -n "${DiskuvOCamlHome_Override:-}" ]]; then DiskuvOCamlHome="$DiskuvOCamlHome_Override"; fi
    if [[ -n "${DiskuvOCamlBinaryPaths_Override:-}" ]]; then DiskuvOCamlBinaryPaths="$DiskuvOCamlBinaryPaths_Override"; fi
    # Check if any vars are still unset
    if [[ -z "${DiskuvOCamlVarsVersion:-}" ]]; then return 1; fi
    if [[ -z "${DiskuvOCamlHome:-}" ]]; then return 1; fi
    if [[ -z "${DiskuvOCamlBinaryPaths:-}" ]]; then return 1; fi
    return 0
}

# Detects Visual Studio and sets its variables.
# Works in MSYS2 or Cygwin.
#
# Inputs:
# - env:PLATFORM
# - env:ENV_PATH_PREFIX - Optional. If provided, will be placed in the front of ENV_PATH_FULL on successful detection
# Outputs:
# - env:ENV_PATH_FULL if and only if the vcvars could be detected (aka. on a Windows machine, and it is installed)
# Return Values:
# - 0: Success
# - 1: Not a Windows machine
# - 2: Windows machine without proper Diskuv OCaml installation (typically you should exit)
function autodetect_vcvars () {
    # Autodetect VCVARS
    if ! is_windows_build_machine; then
        return 1
    fi
    if [[ -z "${SYSTEMDRIVE:-}" ]]; then
        return 2
    fi

    # MSYS2 detection. Path is /c/DiskuvOCaml/BuildTools/VC/Auxiliary/Build/vcvarsall.bat
    if [[ -e /${SYSTEMDRIVE/:}/DiskuvOCaml/BuildTools/VC/Auxiliary/Build/vcvarsall.bat ]]; then
        MSBUILDDIR="/${SYSTEMDRIVE/:}/DiskuvOCaml/BuildTools/VC/Auxiliary/Build"
    elif [[ -e /c/DiskuvOCaml/BuildTools/VC/Auxiliary/Build/vcvarsall.bat ]]; then
        MSBUILDDIR="/c/DiskuvOCaml/BuildTools/VC/Auxiliary/Build"
    # Cygwin detection. Path is /cygdrive/c/DiskuvOCaml/BuildTools/VC/Auxiliary/Build/vcvarsall.bat
    elif [[ -e /cygdrive/${SYSTEMDRIVE/:}/DiskuvOCaml/BuildTools/VC/Auxiliary/Build/vcvarsall.bat ]]; then
        MSBUILDDIR="/cygdrive/${SYSTEMDRIVE/:}/DiskuvOCaml/BuildTools/VC/Auxiliary/Build"
    elif [[ -e /cygdrive/c/DiskuvOCaml/BuildTools/VC/Auxiliary/Build/vcvarsall.bat ]]; then
        MSBUILDDIR="/cygdrive/c/DiskuvOCaml/BuildTools/VC/Auxiliary/Build"
    else
        return 2
    fi
    make --quiet show-vcvars-"$PLATFORM" OUT_VCVARS_BAT="$WORK"/show-vcvars
    if [[ ! -e "$WORK"/show-vcvars ]]; then
        echo "The $PWD/Makefile does not have the show-vcvars-$PLATFORM target. '$PLATFORM' does not appear to be a supported Diskuv platform, or you have not included base.mk" >&2
        return 2
    fi
    VCVARSBATCHFILE=$(< "$WORK"/show-vcvars)
    if [[ "$VCVARSBATCHFILE" = "notapplicable" ]]; then
        return 2
    fi

    # FIRST, create a file that calls vcvarsxxx.bat and then adds a `set` dump.
    # Example:
    #     @call "C:\DiskuvOCaml\BuildTools\VC\Auxiliary\Build\vcvars64.bat" %*
    #     set > "C:\the-WORK-directory\vcvars.txt"
    # to the bottom of it so we can inspect the environment variables.
    # (Less hacky version of https://help.appveyor.com/discussions/questions/18777-how-to-use-vcvars64bat-from-powershell)
    VCVARSBATCHFILE_WIN=$(cygpath -aw "$MSBUILDDIR/$VCVARSBATCHFILE")
    echo '@call "'"$VCVARSBATCHFILE_WIN"'" %*' > "$WORK"/vcvars-and-printenv.bat
    # shellcheck disable=SC2046
    echo 'set > "'$(cygpath -aw "$WORK")'\vcvars.txt"' >> "$WORK"/vcvars-and-printenv.bat

    # SECOND, we run the batch file
    PATH_UNIX=$(cygpath -au --path "$PATH")
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then
        env PATH="$PATH_UNIX" "$WORK"/vcvars-and-printenv.bat >&2 # use stderr to not mess up stdout which calling script may care about.
    else
        env PATH="$PATH_UNIX" "$WORK"/vcvars-and-printenv.bat > /dev/null
    fi

    # THIRD, we add everything to the environment except:
    # - PATH (we need to cygpath this, and we need to replace any existing PATH)
    # - _
    # - !ExitCode
    # - TEMP, TMP
    # - PWD
    # - PROMPT
    # - LOGON* (LOGONSERVER)
    # - *APPDATA (LOCALAPPDATA, APPDATA)
    # - ALLUSERSPROFILE
    # - CYGWIN
    # - CYGPATH
    # - HOME* (HOME, HOMEDRIVE, HOMEPATH)
    # - USER* (USERNAME, USERPROFILE, USERDOMAIN, USERDOMAIN_ROAMINGPROFILE)

    awk '
    BEGIN{FS="="}

    $1 != "PATH" &&
    $1 !~ /^!ExitCode/ &&
    $1 !~ /^_$/ && $1 != "TEMP" && $1 != "TMP" && $1 != "PWD" &&
    $1 != "PROMPT" && $1 !~ /^LOGON/ && $1 !~ /APPDATA$/ &&
    $1 != "ALLUSERSPROFILE" && $1 != "CYGWIN" && $1 != "CYGPATH" &&
    $1 !~ /^HOME/ &&
    $1 !~ /^USER/ {name=$1; value=$0; sub(/^[^=]*=/,"",value); print name "=" value}
    ' "$WORK"/vcvars.txt > "$WORK"/mostvars.eval.sh

    # Add all but PATH to ENV_ARGS
    while IFS='' read -r line; do ENV_ARGS+=("$line"); done < "$WORK"/mostvars.eval.sh

    # FOURTH, Overwrite ENV_PATH with the provided PATH
    awk '
    BEGIN{FS="="}

    $1 == "PATH" {name=$1; value=$0; sub(/^[^=]*=/,"",value); print value}
    ' "$WORK"/vcvars.txt > "$WORK"/winpath.txt
    # shellcheck disable=SC2086
    cygpath --path "$(cat $WORK/winpath.txt)" > "$WORK"/unixpath.txt
    if [[ -n "${ENV_PATH_PREFIX:-}" ]]; then
        # shellcheck disable=SC2086 disable=SC2034
        ENV_PATH_FULL="$ENV_PATH_PREFIX":"$(cat $WORK/unixpath.txt)"
    else
        # shellcheck disable=SC2086 disable=SC2034
        ENV_PATH_FULL=$(cat "$WORK"/unixpath.txt)
    fi

    return 0
}

# Inputs:
# - env:PLATFORM
# Outputs:
# - env:OPAMROOTDIR_BUILDHOST - The path to the Opam root directory that is usable only on the
#     build machine (not from within a container)
# - env:OPAMROOTDIR_EXPAND - The path to the Opam root directory switch that works as an
#     argument to `exec_in_platform`
function set_opamrootdir () {
    if is_dev_platform; then
        if [[ -n "${OPAMROOT:-}" ]]; then
            # If the developer sets OPAMROOT with an environment variable, then we will respect that
            # just like `opam` would do.
            OPAMROOTDIR_BUILDHOST="$OPAMROOT"
        elif is_windows_build_machine; then
            # Windows does not have a non-deprecated working Opam solution, so we go with our choice in
            # build-sandbox-init.sh to have $USERPROFILE/.opam be the Opam root for the dev platform
            OPAMROOTDIR_BUILDHOST="${USERPROFILE}\\.opam"
        else
            OPAMROOTDIR_BUILDHOST="${HOME}/.opam"
        fi
        OPAMROOTDIR_EXPAND="$OPAMROOTDIR_BUILDHOST"
    else
        # In a reproducible container ...
        OPAMROOTDIR_BUILDHOST="$OPAMROOT_IN_CONTAINER"
        # shellcheck disable=SC2034
        OPAMROOTDIR_EXPAND="@@EXPAND_TOPDIR@@/$OPAMROOTDIR_BUILDHOST"
    fi
}

# Select the 'diskuv-system' switch.
#
# Inputs:
# - env:DiskuvOCamlHome - Typically you get this from `autodetect_dkmlvars`
# Outputs:
# - env:OPAMSWITCHFINALDIR_BUILDHOST - Either:
#     The path to the switch that represents the build directory that is usable only on the
#     build machine (not from within a container). For an external (aka local) switch the returned path will be
#     a `.../_opam`` folder which is where the final contents of the switch live. Use OPAMSWITCHDIR_EXPAND
#     if you want an XXX argument for `opam --switch XXX` rather than this path which is not compatible.
# - env:OPAMSWITCHDIR_EXPAND - Either
#     The path to the switch **not including any _opam subfolder** that works as an argument to `exec_in_platform` -OR-
#     The name of a global switch that represents the build directory.
#     OPAMSWITCHDIR_EXPAND works inside or outside of a container.
function set_opamswitchdir_of_system () {
    # Set OPAMSWITCHFINALDIR_BUILDHOST and OPAMSWITCHDIR_EXPAND
    # shellcheck disable=SC2034
    OPAMSWITCHFINALDIR_BUILDHOST="$DiskuvOCamlHome/system/_opam"
    # shellcheck disable=SC2034
    OPAMSWITCHDIR_EXPAND="@@EXPAND_WINDOWS_DISKUVOCAMLHOME@@/system"
}

# is_empty_opam_switch_present SWITCHDIR
#
# SWITCHDIR - Must be the `_opam/` subfolder if the switch is an external (aka local)
#    switch. Otherwise the switch is a global switch and must be the subfolder of
#    the Opam root directory (ex. ~/.opam) that has the same name as the global switch.
#
# Returns: True (0) if and only if the switch exists and is at least an `opam switch create --empty` switch.
#          False (1) otherwise.
function is_empty_opam_switch_present () {
    local switchdir_buildhost=$1
    shift
    if [[ -s "$switchdir_buildhost/.opam-switch/switch-config" ]]
    then
        return 0
    else
        return 1
    fi
}

# is_minimal_opam_switch_present SWITCHDIR
#
# SWITCHDIR - Must be the `_opam/` subfolder if the switch is an external (aka local)
#    switch. Otherwise the switch is a global switch and must be the subfolder of
#    the Opam root directory (ex. ~/.opam) that has the same name as the global switch.
#
# Returns: True (0) if and only if the switch exists and has at least an OCaml system compiler.
#          False (1) otherwise.
function is_minimal_opam_switch_present () {
    local switchdir_buildhost=$1
    shift
    if [[ -e "$switchdir_buildhost/bin/ocamlc" || -e "$switchdir_buildhost/bin/ocamlc.exe" ]]
    then
        return 0
    else
        return 1
    fi
}

# is_minimal_opam_root_present ROOTDIR
#
# ROOTDIR - The Opam root directory.
#
# Returns: True (0) if and only if the root exists and has an Opam configuration file.
#          False (1) otherwise.
function is_minimal_opam_root_present () {
    local rootdir_buildhost=$1
    shift
    if [[ -e "$rootdir_buildhost/config" ]]
    then
        return 0
    else
        return 1
    fi
}

# get_opam_switch_state_toplevelsection SWITCHDIR TOPLEVEL_SECTION_NAME
#
# Speedy way to grab sections from Opam. Opam is pretty speedy but
# `opam install utop` for example requires that `vcvars64.bat` is loaded
# on Windows which can take seconds.
#
# Inputs:
#
# SWITCHDIR - Must be the `_opam/` subfolder if the switch is an external (aka local)
#    switch. Otherwise the switch is a global switch and must be the subfolder of
#    the Opam root directory (ex. ~/.opam) that has the same name as the global switch.
# TOPLEVEL_SECTION_NAME - The name of the section. See Examples.
#
# Output: [stdout] The toplevel section of `switch-state` that
#   has the name TOPLEVEL_SECTION_NAME
#
# Examples:
#   If `~/_opam/.opam-switch/switch-state` contained:
#        compiler: ["ocaml-variants.4.12.0+msvc64+msys2"]
#        roots: [
#          "bigstringaf.0.8.0"
#          "digestif.1.0.1"
#          "dune-configurator.2.9.0"
#          "ocaml-lsp-server.1.7.0"
#          "ocaml-variants.4.12.0+msvc64+msys2"
#          "ocamlformat.0.18.0"
#          "ppx_expect.v0.14.1"
#          "utop.2.8.0"
#        ]
#   Then `get_opam_switch_state_toplevelsection ~/_opam compiler` would give:
#        compiler: ["ocaml-variants.4.12.0+msvc64+msys2"]
#   and `get_opam_switch_state_toplevelsection ~/_opam roots` would give:
#        roots: [
#          "bigstringaf.0.8.0"
#          "digestif.1.0.1"
#          "dune-configurator.2.9.0"
#          "ocaml-lsp-server.1.7.0"
#          "ocaml-variants.4.12.0+msvc64+msys2"
#          "ocamlformat.0.18.0"
#          "ppx_expect.v0.14.1"
#          "utop.2.8.0"
#        ]
function get_opam_switch_state_toplevelsection () {
    local switchdir_buildhost=$1
    shift
    local toplevel_section_name=$1
    shift
    if [[ ! -e "${switchdir_buildhost}/.opam-switch/switch-state" ]]; then
        echo "FATAL: There is no Opam switch at ${switchdir_buildhost}" >&2
        exit 71
    fi
    awk -v section="$toplevel_section_name" \
        '$1 ~ ":" {state=0} $1==(section ":") {state=1} state==1{print}' \
        "${switchdir_buildhost}/.opam-switch/switch-state"
}
