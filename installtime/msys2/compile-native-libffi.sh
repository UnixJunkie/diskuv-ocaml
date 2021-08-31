#!/bin/bash
# ----------------------------
# compile-native-libffi.sh DKMLDIR LIBFFI_VERSION WORKDIR INSTALLDIR

set -euf -o pipefail

DKMLDIR=$1
shift
if [[ ! -e "$DKMLDIR/.dkmlroot" ]]; then echo "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2; fi

LIBFFI_VERSION=$1
shift

WORKDIR=$1
shift

INSTALLDIR=$1
shift

# shellcheck disable=SC1091
source "$DKMLDIR/etc/contexts/linux-build/crossplatform-functions.sh"

# Set ENV_ARGS, VCVARS_PATH and VCVARS_ARCH
autodetect_vcvars

# WORKDIRping vars
LIBFFI_WORK="$WORKDIR/libffi-$LIBFFI_VERSION"

# Get tarball. Don't both with the source tarball or git clone since would have to do autoconf.
install -d "$WORKDIR"
if [[ ! -e "$LIBFFI_WORK/configure" ]]; then
    wget https://github.com/libffi/libffi/releases/download/v"$LIBFFI_VERSION"/libffi-"$LIBFFI_VERSION".tar.gz -O "$WORKDIR/libffi-$LIBFFI_VERSION.tar.gz"
    rm -rf "$LIBFFI_WORK" # clean any partial downloads
    tar xCfz "$WORKDIR" "$LIBFFI_WORK.tar.gz"
fi

INSTALLDIR_UNIX=$(cygpath -au "$INSTALLDIR")

cd "$WORKDIR/libffi-$LIBFFI_VERSION"

# item arrays specifying what we want to build.
# we do static separately from shared because libffi forces us to (for Windows at least)
ITEM_CPPFLAGS=("-DFFI_BUILDING_DLL" "-DFFI_BUILDING")
ITEM_DIR=(shared static)
ITEM_ENABLEFLAG=(--enable-shared --disable-shared)
ITEM_HACK_COPYIMPORTLIB=(ON OFF)

for i in 0 1; do
    # distclean (or else configure won't set everything that it should)
    if [[ -e "Makefile" ]]; then
        env "${ENV_ARGS[@]}" PATH="$VCVARS_PATH" \
            make -C "$LIBFFI_WORK" distclean
    fi

    # configure
    env "${ENV_ARGS[@]}" PATH="$VCVARS_PATH" LIBFFI_TMPDIR="$WORKDIR" \
        ./configure --prefix="$INSTALLDIR_UNIX/${ITEM_DIR[$i]}" --build=x86_64-w64-mingw"$VCVARS_ARCH" \
        "${ITEM_ENABLEFLAG[$i]}" \
        CC="$LIBFFI_WORK"/msvcc.sh \
        CXX="$LIBFFI_WORK"/msvcc.sh \
        CFLAGS="-m$VCVARS_ARCH -O2" \
        CXXFLAGS="-m$VCVARS_ARCH" \
        LD=link \
        CPP="cl -nologo -EP" \
        CPPFLAGS="${ITEM_CPPFLAGS[$i]}" \
        CXXCPP="cl -nologo -EP"

    # make
    env "${ENV_ARGS[@]}" PATH="$VCVARS_PATH" \
        make -C "$LIBFFI_WORK"

    # total hack for 'shared' since a static library will not be created, but `make install`
    # does not know that and will fail. we'll use the import library (which is _not_ the true
    # static library) instead
    if [[ "${ITEM_HACK_COPYIMPORTLIB[$i]}" = ON ]]; then
        set +f
        cp x86_64-w64-mingw"$VCVARS_ARCH"/.libs/libffi-*.lib x86_64-w64-mingw"$VCVARS_ARCH"/.libs/libffi.lib
        set -f
    fi

    # make install
    env "${ENV_ARGS[@]}" PATH="$VCVARS_PATH" \
        make -C "$LIBFFI_WORK" install
done
