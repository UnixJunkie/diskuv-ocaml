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
# On exit: BUILDHOST_ARCH will contain the correct ARCH.
function build_machine_arch () {
    local MACHINE
    MACHINE=$(uname -m)
    # list from https://en.wikipedia.org/wiki/Uname and https://stackoverflow.com/questions/45125516/possible-values-for-uname-m
    case "${MACHINE}" in
        "armv7*")
            # shellcheck disable=SC2034
            BUILDHOST_ARCH=linux_arm32v7;;
        "armv6*" | "arm")
            # shellcheck disable=SC2034
            BUILDHOST_ARCH=linux_arm32v6;;
        "aarch64" | "arm64" | "armv8*")
            # shellcheck disable=SC2034
            BUILDHOST_ARCH=linux_arm64;;
        "i386" | "i686")
            # shellcheck disable=SC2034
            BUILDHOST_ARCH=linux_x86;;
        "x86_64")
            # shellcheck disable=SC2034
            BUILDHOST_ARCH=linux_x86_64;;
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
