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

# Tries to find the ARCH (defined in TOPDIR/Makefile corresponding to the build machine
# For now only works in Linux x86/x86_64.
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

# Detects Visual Studio and sets its variables.
# Works in MSYS2 or Cygwin.
#
# Example:
#  autodetect_vcvars && env "${ENV_ARGS[@]}" PATH="$VCVARS_PATH" run-something.sh
#
# Inputs:
# - env:WORK - Optional. If provided will be used as temporary directory
# - array:ENV_ARGS - Optional. An array of environment variables which will be modified by this function
# Outputs:
# - env:BUILDHOST_ARCH will contain the correct ARCH
# - env:VCVARS_ENV if and only if the vcvars could be detected (aka. on a Windows machine, and it is installed)
# - array:ENV_ARGS - An array of environment variables for Visual Studio, including any provided at
#   the start of the function
# Return Values:
# - 0: Success
# - 1: Not a Windows machine
# - 2: Windows machine without proper Diskuv OCaml installation (typically you should exit)
function autodetect_vcvars () {
    local TEMPDIR=${WORK:-$TMP}
    # Autodetect BUILDHOST_ARCH
    build_machine_arch
    if [[ ! "$BUILDHOST_ARCH" = windows_* ]]; then
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

    if [[ "$BUILDHOST_ARCH" = windows_x86 ]]; then
        VCVARSBATCHFILE=vcvars32.bat
    else
        VCVARSBATCHFILE=vcvars64.bat
    fi

    # FIRST, create a file that calls vcvarsxxx.bat and then adds a `set` dump.
    # Example:
    #     @call "C:\DiskuvOCaml\BuildTools\VC\Auxiliary\Build\vcvars64.bat" %*
    #     set > "C:\the-WORK-directory\vcvars.txt"
    # to the bottom of it so we can inspect the environment variables.
    # (Less hacky version of https://help.appveyor.com/discussions/questions/18777-how-to-use-vcvars64bat-from-powershell)
    VCVARSBATCHFILE_WIN=$(cygpath -aw "$MSBUILDDIR/$VCVARSBATCHFILE")
    echo '@call "'"$VCVARSBATCHFILE_WIN"'" %*' > "$TEMPDIR"/vcvars-and-printenv.bat
    # shellcheck disable=SC2046
    echo 'set > "'$(cygpath -aw "$TEMPDIR")'\vcvars.txt"' >> "$TEMPDIR"/vcvars-and-printenv.bat

    # SECOND, we run the batch file
    PATH_UNIX=$(cygpath -au --path "$PATH")
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then
        env PATH="$PATH_UNIX" "$TEMPDIR"/vcvars-and-printenv.bat >&2 # use stderr to not mess up stdout which calling script may care about.
    else
        env PATH="$PATH_UNIX" "$TEMPDIR"/vcvars-and-printenv.bat > /dev/null
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
    ' "$TEMPDIR"/vcvars.txt > "$TEMPDIR"/mostvars.eval.sh

    # Add all but PATH to ENV_ARGS
    while IFS='' read -r line; do ENV_ARGS+=("$line"); done < "$TEMPDIR"/mostvars.eval.sh

    # FOURTH, set VCVARS_PATH to the provided PATH
    awk '
    BEGIN{FS="="}

    $1 == "PATH" {name=$1; value=$0; sub(/^[^=]*=/,"",value); print value}
    ' "$TEMPDIR"/vcvars.txt > "$TEMPDIR"/winpath.txt
    # shellcheck disable=SC2086
    cygpath --path "$(cat $TEMPDIR/winpath.txt)" > "$TEMPDIR"/unixpath.txt
    # shellcheck disable=SC2086 disable=SC2034
    VCVARS_PATH=$(cat "$TEMPDIR"/unixpath.txt)

    return 0
}
