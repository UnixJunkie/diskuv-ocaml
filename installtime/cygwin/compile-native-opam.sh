#!/bin/bash
# ----------------------------
# compile-native-opam.sh DKMLDIR GIT_TAG INSTALLDIR

set -euf -o pipefail

DKMLDIR=$1
shift
if [[ ! -e "$DKMLDIR/.dkmlroot" ]]; then echo "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2; fi

GIT_TAG=$1
shift

OPAMBOOTSTRAP=$1
shift

INSTALLDIR=$1
shift

# shellcheck disable=SC2034
PLATFORM=dev # not actually in the dev platform but we are just pulling the "common" tool functions (so we can choose whatever platform we like)

# shellcheck disable=SC1091
source "$DKMLDIR/runtime/unix/_common_tool.sh"

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the DKMLDIR (just like the container
# sets the directory to be /work)
cd "$DKMLDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# Bootstrapping vars
OPAMSRC=$OPAMBOOTSTRAP/src

# Output vars
# We chose not to use `$TOOLSCOMMONDIR/local/` because putting libstdc++-6.dll DLL in the shared tool path
# is risking future DLL conflicts.
OPAMBIN=$OPAMBOOTSTRAP/bin 

# Get Diskuv's Opam 2.1.0 if not present already
if [[ ! -e "$OPAMSRC/Makefile" ]]; then
    rm -rf "$OPAMSRC" # clean any partial downloads
    git clone -b "$GIT_TAG" https://github.com/diskuv/opam "$OPAMSRC"
else
    if git -C "$OPAMSRC" tag -l "$GIT_TAG" | awk 'BEGIN{nonempty=0} NF>0{nonempty+=1} END{exit nonempty==0}'; then git -C "$OPAMSRC" tag -d "$GIT_TAG"; fi # allow tag to move (for development and for emergency fixes)
    git -C "$OPAMSRC" fetch --tags
    git -C "$OPAMSRC" -c advice.detachedHead=false checkout "$GIT_TAG"
fi

POST_BOOTSTRAP_PATH="$OPAMSRC"/bootstrap/ocaml/bin:/usr/bin:/bin:/bin/Opam.Runtime.amd64:"$PATH"

if [[ "${DKML_BUILD_TRACE:-ON}" = ON ]]; then set -x; fi

# Running through the `make compiler`, `make lib-pkg` + `configure` process should be done
# as one atomic unit. A failure in an intermediate step can cause subsequent `make compiler`
# or `make lib-pkg` or `configure` to fail. So we completely clean (`distclean`) until
# we have successfully completed a single run all the way to `configure`.
if [[ ! -e "$OPAMSRC/src/ocaml-flags-configure.sexp"  ]]; then
    make -C "$OPAMSRC" distclean

    # Let Opam create its own Ocaml compiler which Opam will use to compile
    # all of its required Ocaml dependencies
    make -C "$OPAMSRC" compiler OCAML_PORT=mingw64 -j 4

    # Install Opam's dependencies as findlib packages to the bootstrap compiler
    # Note: We could add `OPAM_0INSTALL_SOLVER_ENABLED=true` but unclear if that is a good idea.
    make -C "$OPAMSRC" lib-pkg -j 4

    # Standard autotools ./configure
    cd "$OPAMSRC"
    env PATH="$POST_BOOTSTRAP_PATH" ./configure --prefix="$INSTALLDIR"
    cd "$DKMLDIR"
fi

# At this point we have compiled _all_ of Opam dependencies ...
# Now we need to build Opam itself.

# We don't actually want to build the whole project ... we don't need to invest the time for that ...
# simply just build the opam executable called `opamMain.exe` (the Dune public name of that is the familiar `opam.exe`).
# So we just Dune rather than the Makefile to do that.
#
# 1. We use `--root` so that dune does not get confused about the `dune-project` higher up in the
# directory tree.
#
# 2. ./_build/install/default/bin/opam.exe will be built with a dependency on libstdc++-6.dll
# which is available at /bin/Opam.Runtime.amd64. Not entirely clear it is not linked correctly
# but it may be due to /bin and /lib being mounted as /usr/bin and /usr/lib, respectively,
# in the real `ocaml-opam` Docker container's Cygwin mounts. We can mitigate by just adding
# the PATH.
#
OPAMSRC_CYG=$(cygpath -am "$OPAMSRC")
env PATH="$POST_BOOTSTRAP_PATH" \
    dune build --root "$OPAMSRC_CYG" \
    src/client/opamMain.exe

# Bundle up the DLLs and the binary into a single install location
install -d "$OPAMBIN"
install "$OPAMSRC"/_build/default/src/client/opamMain.exe "$OPAMBIN"/opam.exe
rsync -a /bin/Opam.Runtime.amd64/ "$OPAMBIN"/
