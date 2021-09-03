#!/bin/bash
######################################
# crossplatform-functions.sh
#
# Meant to be `source`-d.
#
# Can be run within a container or outside of a container.
#

# Is a Windows build machine if we are in a MSYS2 or Cygwin environment
function is_windows_build_machine () {
    if [[ "${MSYSTEM:-}" = "MSYS" || -e /usr/bin/cygpath ]]; then
        return 0
    fi
    return 1
}

# Tries to find the ARCH (defined in TOPDIR/Makefile corresponding to the build machine)
# For now only tested in Linux/Windows x86/x86_64.
# Outputs:
# - env:BUILDHOST_ARCH will contain the correct ARCH
function build_machine_arch () {
    local MACHINE
    MACHINE=$(uname -m)
    # list from https://en.wikipedia.org/wiki/Uname and https://stackoverflow.com/questions/45125516/possible-values-for-uname-m
    case "${MACHINE}" in
        "armv7*")
            BUILDHOST_ARCH=linux_arm32v7;;
        "armv6*" | "arm")
            BUILDHOST_ARCH=linux_arm32v6;;
        "aarch64" | "arm64" | "armv8*")
            BUILDHOST_ARCH=linux_arm64;;
        "i386" | "i686")
            if is_windows_build_machine; then
                BUILDHOST_ARCH=windows_x86
            else
                BUILDHOST_ARCH=linux_x86
            fi
            ;;
        "x86_64")
            if is_windows_build_machine; then
                BUILDHOST_ARCH=windows_x86_64
            else
                # shellcheck disable=SC2034
                BUILDHOST_ARCH=linux_x86_64
            fi
            ;;
        *)
            echo "FATAL: Unsupported build machine type obtained from 'uname -m': $MACHINE" >&2
            exit 1
            ;;
    esac
}

# Tries to find the VCPKG_TRIPLET (defined in TOPDIR/Makefile corresponding to the build machine)
# For now only tested in Linux/Windows x86/x86_64.
# Inputs:
# - env:PLATFORM
# Outputs:
# - env:BUILDHOST_ARCH will contain the correct ARCH
# - env:PLATFORM_VCPKG_TRIPLET will contain the correct vcpkg triplet
function platform_vcpkg_triplet () {
    build_machine_arch
    # TODO: This static list is brittle. Should parse the Makefile or better yet
    # place in a different file that can be used by this script and the Makefile.
    case "$PLATFORM-$BUILDHOST_ARCH" in
        "dev-windows_x86")    PLATFORM_VCPKG_TRIPLET=x86-windows ;;
        "dev-windows_x86_64") PLATFORM_VCPKG_TRIPLET=x64-windows ;;
        "dev-linux_x86")      PLATFORM_VCPKG_TRIPLET=x86-linux ;;
        "dev-linux_x86_64")
            # shellcheck disable=SC2034
            PLATFORM_VCPKG_TRIPLET=x64-linux ;;
        *)
            echo "FATAL: Unsupported vcpkg triplet for PLATFORM: $PLATFORM" >&2
            exit 1
            ;;
    esac
}

# Fix the MSYS2 ambiguity problem described at https://github.com/msys2/MSYS2-packages/issues/2316. Our error is running:
#   cl -nologo -O2 -Gy- -MD -Feocamlrun.exe prims.obj libcamlrun.lib advapi32.lib ws2_32.lib version.lib /link /subsystem:console /ENTRY:wmainCRTStartup
# would warn
#   cl : Command line warning D9002 : ignoring unknown option '/subsystem:console'
#   cl : Command line warning D9002 : ignoring unknown option '/ENTRY:wmainCRTStartup'
# because the slashes (/) could mean Windows paths or Windows options. We force the latter.
#
# This is described in Automatic Unix ⟶ Windows Path Conversion
# at https://www.msys2.org/docs/filesystem-paths/
function disambiguate_filesystem_paths () {
    if is_windows_build_machine; then
        export MSYS2_ARG_CONV_EXCL='*'
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

# Detects Visual Studio and sets its variables.
# autodetect_vsdev [EXTRA_PREFIX]
#
# Includes EXTRA_PREFIX as a prefix for /include and and /lib library paths.
#
# Example:
#  autodetect_vsdev /usr/local && env "${ENV_ARGS[@]}" PATH="$VSDEV_PATH" run-something.sh
#
# Inputs:
# - $1 - Optional. If provided, then $1/include and $1/lib are added to INCLUDE and LIB, respectively
# - env:WORK - Optional. If provided will be used as temporary directory
# - array:ENV_ARGS - Optional. An array of environment variables which will be modified by this function
# Outputs:
# - env:DKMLPARENTHOME_BUILDHOST
# - env:BUILDHOST_ARCH will contain the correct ARCH
# - env:VSDEV_PATH is new PATH if and only if the vcvars could be detected (aka. on a Windows machine, and it is installed)
# - env:VSDEV_ARCH is 32 or 64 if and only if the vcvars could be detected
# - array:ENV_ARGS - An array of environment variables for Visual Studio, including any provided at
#   the start of the function
# Return Values:
# - 0: Success
# - 1: Not a Windows machine
# - 2: Windows machine without proper Diskuv OCaml installation (typically you should exit)
function autodetect_vsdev () {
    local TEMPDIR=${WORK:-$TMP}

    # Get the extra prefix with backslashes escaped for Awk, if specified
    if [[ "$#" -ge 1 ]]; then
        local EXTRA_PREFIX_ESCAPED="$1"
        if is_windows_build_machine; then EXTRA_PREFIX_ESCAPED=$(cygpath -aw "$EXTRA_PREFIX_ESCAPED"); fi
        EXTRA_PREFIX_ESCAPED=${EXTRA_PREFIX_ESCAPED//\\/\\\\}
        shift
    else
        local EXTRA_PREFIX_ESCAPED=""
    fi

    # Autodetect BUILDHOST_ARCH
    build_machine_arch
    if [[ ! "$BUILDHOST_ARCH" = windows_* ]]; then
        return 1
    fi

    # Set DKMLPARENTHOME_BUILDHOST
    set_dkmlparenthomedir

    local VSSTUDIO_DIRFILE="$DKMLPARENTHOME_BUILDHOST/vsstudio.dir.txt"
    if [[ ! -e "$VSSTUDIO_DIRFILE" ]]; then
        return 2
    fi
    local VSSTUDIODIR
    VSSTUDIODIR=$(awk 'BEGIN{RS="\r\n"} {print; exit}' "$VSSTUDIO_DIRFILE")
    if is_windows_build_machine; then
        VSSTUDIODIR=$(cygpath -au "$VSSTUDIODIR")
    fi

    # MSYS2 detection. Path is /c/DiskuvOCaml/BuildTools/Common7/Tools/VsDevCmd.bat
    if [[ -e "$VSSTUDIODIR"/Common7/Tools/VsDevCmd.bat ]]; then
        VSDEVCMD="$VSSTUDIODIR/Common7/Tools/VsDevCmd.bat"
    else
        return 2
    fi

    VSDEV_OPTS=(-no_logo)
    if [[ "$BUILDHOST_ARCH" = windows_x86 ]]; then
        VSDEV_OPTS+=(-arch=x86)
        VSDEV_ARCH=32
    else
        VSDEV_OPTS+=(-arch=x64)
        # shellcheck disable=SC2034
        VSDEV_ARCH=64
    fi

    # FIRST, create a file that calls vsdevcmd.bat and then adds a `set` dump.
    # Example:
    #     @call "C:\DiskuvOCaml\BuildTools\Common7\Tools\VsDevCmd.bat" %*
    #     set > "C:\the-WORK-directory\vcvars.txt"
    # to the bottom of it so we can inspect the environment variables.
    # (Less hacky version of https://help.appveyor.com/discussions/questions/18777-how-to-use-vcvars64bat-from-powershell)
    VSDEVCMDFILE_WIN=$(cygpath -aw "$VSDEVCMD")
    echo '@call "'"$VSDEVCMDFILE_WIN"'" %*' > "$TEMPDIR"/vsdevcmd-and-printenv.bat
    # shellcheck disable=SC2046
    echo 'set > "'$(cygpath -aw "$TEMPDIR")'\vcvars.txt"' >> "$TEMPDIR"/vsdevcmd-and-printenv.bat

    # SECOND, we run the batch file
    PATH_UNIX=$(cygpath -au --path "$PATH")
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then
        env PATH="$PATH_UNIX" VSCMD_SKIP_SENDTELEMETRY=1 VSCMD_DEBUG=1 "$TEMPDIR"/vsdevcmd-and-printenv.bat "${VSDEV_OPTS[@]}" >&2 # use stderr to not mess up stdout which calling script may care about.
    else
        env PATH="$PATH_UNIX" VSCMD_SKIP_SENDTELEMETRY=1 "$TEMPDIR"/vsdevcmd-and-printenv.bat "${VSDEV_OPTS[@]}" > /dev/null
    fi

    # THIRD, we add everything to the environment except:
    # - PATH (we need to cygpath this, and we need to replace any existing PATH)
    # - INCLUDE (we will add our own vcpkg include path)
    # - LIB (we will add our own vcpkg library path)
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
    if [[ -n "${EXTRA_PREFIX_ESCAPED:-}" ]]; then
        local VCPKG_PREFIX_INCLUDE_ESCAPED="$EXTRA_PREFIX_ESCAPED\\\\include;"
        local VCPKG_PREFIX_LIB_ESCAPED="$EXTRA_PREFIX_ESCAPED\\\\lib;"
    else
        local VCPKG_PREFIX_INCLUDE_ESCAPED=""
        local VCPKG_PREFIX_LIB_ESCAPED=""
    fi
    awk \
        -v VCPKG_PREFIX_INCLUDE="$VCPKG_PREFIX_INCLUDE_ESCAPED" \
        -v VCPKG_PREFIX_LIB="$VCPKG_PREFIX_LIB_ESCAPED" '
    BEGIN{FS="="}

    $1 != "PATH" &&
    $1 != "INCLUDE" &&
    $1 != "LIB" &&
    $1 !~ /^!ExitCode/ &&
    $1 !~ /^_$/ && $1 != "TEMP" && $1 != "TMP" && $1 != "PWD" &&
    $1 != "PROMPT" && $1 !~ /^LOGON/ && $1 !~ /APPDATA$/ &&
    $1 != "ALLUSERSPROFILE" && $1 != "CYGWIN" && $1 != "CYGPATH" &&
    $1 !~ /^HOME/ &&
    $1 !~ /^USER/ {name=$1; value=$0; sub(/^[^=]*=/,"",value); print name "=" value}

    $1 == "INCLUDE" {name=$1; value=$0; sub(/^[^=]*=/,"",value); print name "=" VCPKG_PREFIX_INCLUDE value}
    $1 == "LIB" {name=$1; value=$0; sub(/^[^=]*=/,"",value); print name "=" VCPKG_PREFIX_LIB value}
    ' "$TEMPDIR"/vcvars.txt > "$TEMPDIR"/mostvars.eval.sh

    # Add all but PATH, INCLUDE and LIB to ENV_ARGS
    while IFS='' read -r line; do ENV_ARGS+=("$line"); done < "$TEMPDIR"/mostvars.eval.sh

    # FOURTH, set VSDEV_PATH to the provided PATH
    awk '
    BEGIN{FS="="}

    $1 == "PATH" {name=$1; value=$0; sub(/^[^=]*=/,"",value); print value}
    ' "$TEMPDIR"/vcvars.txt > "$TEMPDIR"/winpath.txt
    # shellcheck disable=SC2086
    cygpath --path -f - < "$TEMPDIR/winpath.txt" > "$TEMPDIR"/unixpath.txt
    # shellcheck disable=SC2034
    VSDEV_PATH=$(< "$TEMPDIR"/unixpath.txt)

    # FIFTH, set VSDEV_UNIQ_PATH so that it is only the _unique_ entries
    # (the set {VSDEV_UNIQ_PATH} - {PATH}) are used. But maintain the order
    # that Microsoft places each path entry.
    echo "$VSDEV_PATH" | awk 'BEGIN{RS=":"} {print}' > "$TEMPDIR"/vcvars_entries.txt
    comm \
        -23 \
        <(sort -u "$TEMPDIR"/vcvars_entries.txt) \
        <(echo "$PATH" | awk 'BEGIN{RS=":"} {print}' | sort -u) \
        > "$TEMPDIR"/vcvars_uniq.txt
    VSDEV_UNIQ_PATH=""
    while IFS='' read -r line; do
        # if and only if the $line matches one of the lines in vcvars_uniq.txt
        if ! echo "$line" | comm -12 - "$TEMPDIR"/vcvars_uniq.txt | awk 'NF>0{exit 1}'; then
            if [[ -z "$VSDEV_UNIQ_PATH" ]]; then
                VSDEV_UNIQ_PATH="$line"
            else
                VSDEV_UNIQ_PATH="$VSDEV_UNIQ_PATH:$line"
            fi
        fi
    done < "$TEMPDIR"/vcvars_entries.txt

    return 0
}
