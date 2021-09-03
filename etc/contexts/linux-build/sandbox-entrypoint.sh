#!/bin/bash
set -euf -o pipefail
cd /work

# shellcheck disable=SC1091
source "/opt/build-sandbox/crossplatform-functions.sh"

# ------------
# BEGIN stop exporting any non-public variables exported by Dockerfile and `docker run --env`

# Dockerfile
export -n BUILDER_GID
export -n BUILDER_GROUP
export -n BUILDER_UID
export -n BUILDER_USER
export -n chroot_dir

# docker run --env (from `within-sandbox`)
export -n SANDBOX_PRE_HOOK

# END stop exporting any non-public variables exported by Dockerfile and `docker run --env`
# ------------

# ------------
# BEGIN essentially the .bashrc of the container.

if [[ -e "/usr/bin/opam" && -n "${OPAMROOT:-}" && -e "$OPAMROOT"/config && -n "${OPAMSWITCH:-}" ]]; then
    eval "$(/usr/bin/opam env)"
fi

if [[ "$BUILDER_UID" -ne 0 && -d ~ && ! -e ~/.bash_history && -w /mnt/bash_history && ! -d /mnt/bash_history ]]; then
    ln -s /mnt/bash_history ~/.bash_history
fi

if [[ -n "${DKML_TOOLS_DIR:-}" ]]; then
    # We only add to PATH and not LD_LIBRARY_PATH because all the tools should be statically linked executables. If not, use compile time rpath or similar.
    export PATH="$DKML_TOOLS_DIR/local/bin:$DKML_TOOLSCOMMON_DIR/local/bin:$PATH"
fi

# On Windows add C:\Windows\System32 to end of PATH
if is_windows_build_machine; then
    SYSTEM32=$(cygpath -au "$SYSTEMROOT"\\System32)
    export PATH="$PATH:$SYSTEM32"
fi

# On Windows always disable the Automatic Unix ⟶ Windows Path Conversion
# described at https://www.msys2.org/docs/filesystem-paths/ 
disambiguate_filesystem_paths

# END essentially the .bashrc of the container.
# ------------

# add compilation tools
# (TODO: these will need to be mounted into the container and autodetected)
# (only necessary for Windows at the moment, and we don't support Windows containers yet or perhaps never)
if [[ "${SANDBOX_COMPILATION:-ON}" = ON ]]; then
    if is_windows_build_machine; then
        if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then echo "+ [todo] add compilation tools like vcvars" >&2; fi
    fi
fi

# run any prehooks (the PATH has already been setup)
if [[ -n "$SANDBOX_PRE_HOOK" ]]; then
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then echo "+ [eval] $SANDBOX_PRE_HOOK" >&2; fi
    # shellcheck disable=SC1090
    source <(eval "$SANDBOX_PRE_HOOK")
fi

# Add vcpkg packages to the PATH especially now that prehooks may have set OPAMROOT
if [[ -n "${DKML_VCPKG_TRIPLET:-}" && -n "${OPAMROOT:-}" ]]; then
    VCPKG_INSTALLED="$OPAMROOT/plugins/diskuvocaml/vcpkg/$DKML_ROOT_VERSION/installed/$DKML_VCPKG_TRIPLET"
    # shellcheck disable=SC2154
    PATH="$VCPKG_INSTALLED/bin:$VCPKG_INSTALLED/tools/pkgconf:$PATH"
fi

# print PATH for troubleshooting
if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then echo "+ [PATH] $PATH" >&2; fi

# run the requested command
if [[ $# -eq 0 ]]; then
    # interactive login shell
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
    exec bash -i -l
else
    # run whatever the developer told us
    if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi
    exec "$@"
fi
