# We don't actually need to use Alpine for the Docker container itself.
# Technically only the Build Sandbox needs to be musl-based. But using Alpine
# simplifies the Docker container.
ARG DOCKER_IMAGE=alpine:3.14
FROM ${DOCKER_IMAGE}

# http://nl.alpinelinux.org/alpine/MIRRORS.txt
ARG ALPINE_MIRROR=http://dl-cdn.alpinelinux.org/alpine
# Which target system; either `linux` or `windows` or `android` or `ios`
ARG TARGET_KERNEL
# Which hardware architecture to target. See http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/
ARG TARGET_ALPINE_ARCH
# Which version of Alpine should we run in the build sandbox?
# You should update **/CMakeLists.txt :: cmake_minimum_required() if you update this default.
ARG TARGET_ALPINE_VERSION=3.14

# --------------------------
# Get all the tools we need to create the Build Sandbox
# https://wiki.alpinelinux.org/wiki/Alpine_Linux_in_a_chroot

RUN apk add --no-cache curl bash

RUN install -d /tmp/work
WORKDIR /tmp/work

# --------------------------
# Create the Build Sandbox
# https://wiki.alpinelinux.org/wiki/Alpine_Linux_in_a_chroot

# Since we don't know the exact apk-tools-static version number (it can change weekly) we use the APKINDEX which looks like:
#    C:Q1p8jEUNAed/lCYStsOnr3cNi414k=
#    P:apk-tools-static
#    V:2.12.7-r0
#    A:x86
RUN set -x && curl -LO ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main/${TARGET_ALPINE_ARCH}/APKINDEX.tar.gz && \
    tar xvfz APKINDEX.tar.gz APKINDEX && \
    APK_TOOLS_STATIC=`awk 'BEGIN{FS=":"} /^P:apk-tools-static\$/{found=1} found && /^V:/ {print \$2; exit 0}' APKINDEX` && \
    curl -LO "${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main/${TARGET_ALPINE_ARCH}/apk-tools-static-$APK_TOOLS_STATIC.apk" && \
    tar -xvzf "apk-tools-static-$APK_TOOLS_STATIC.apk"

ENV chroot_dir /opt/diskuv-ocaml-build-chroot

RUN ./sbin/apk.static \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main \
    -U --allow-untrusted \
    -p ${chroot_dir} \
    --initdb add alpine-base

# Sandbox packages (you can use separate RUN statements so we don't have to rebuild the entire Docker image each change)
# https://pkgs.alpinelinux.org/packages has package list

# 'main' repository is built by Alpine team.
# apk-tools (`apk` to let developer install more packages)
# bash (needed by Opam/Dune and needs for developers)
# build-base (`gcc`/`g++`/`musl-dev` etc.)
# cmake (needed for C/C++ builds)
# curl (needed for C/C++ builds built by vcpkg)
# git (needed by Opam and to sync src/build-tools/vendor/vcpkg/ in a sandbox specific dir)
# m4 (opam recommends this since 'most packages rely on these')
# ninja (needed for C/C++ builds, especially those that use cmake)
# npm (Node.js incl. package manager)
# rsync (opam says won't be able to use 'rsync and local repositories' without this)
# su-exec (so we can run as a regular user after we enter the sandbox)
RUN ./sbin/apk.static \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main \
    -U --allow-untrusted \
    -p ${chroot_dir} \
    add \
    apk-tools \
    bash \
    build-base \
    cmake \
    curl \
    git \
    m4 \
    ninja \
    npm \
    rsync \
    su-exec

# 'community' repository is coordinated by Alpine team but comes from a contributor, so caution is
# needed adding these. https://wiki.alpinelinux.org/wiki/Enable_Community_Repository
# ~~capnproto-dev~~ (Cap n' Proto compiler) (we use cmake submodule, but only because we implemented that first to bind easily to capnproto-java which is not in Alpine)
# ocaml (Ocaml)
# opam (package manager for Ocaml)
RUN ./sbin/apk.static \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/community \
    -U --allow-untrusted \
    -p ${chroot_dir} \
    add \
    ocaml \
    opam

# libucontext (for capnproto to fix https://github.com/capnproto/capnproto/issues/1167)
# linux-headers (for [core] OCaml package)
# ~~openssl (for capnproto)~~
# pkgconf (for [conf-pkg-config << bigarray-compat << astring] OCaml package)
# zlib-dev (for capnproto)
RUN ./sbin/apk.static \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main \
    -U --allow-untrusted \
    -p ${chroot_dir} \
    add \
    libucontext \
    linux-headers \
    pkgconf \
    zlib-dev



# For Windows we will use the WINE+MXE strategy of dockcross.
# Reference: https://github.com/dockcross/dockcross/blob/315089192bba1db404400d566a0bbdbfaa8a5bd4/common/common.windows
# * `wine` is only available in the x86 and x86_64 architectures. We could compile `wine` but we can simply say Linux
# * machines must be used as the build hosts.
RUN if test "${TARGET_KERNEL}" = "windows"; then \
    # > WINE is used as an emulator for try_run and tests with CMake.
    #
    # > Other dependencies are from the listed MXE requirements:
    # >   http://mxe.cc/#requirements
    ./sbin/apk.static \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main \
    -U --allow-untrusted \
    -p ${chroot_dir} \
    add \
    autoconf \
    automake \
    bash \
    binutils \
    bison \
    bzip2 \
    flex \
    g++ \
    gdk-pixbuf \
    gettext \
    git \
    gperf \
    intltool \
    libtool \
    linux-headers \
    lzip \
    make \
    openssl \
    openssl-dev \
    p7zip \
    patch \
    perl \
    python3 \
    ruby \
    unzip \
    wget \
    xz \
    zlib \
    ; \
    fi

RUN if test "${TARGET_KERNEL}" = "windows"; then \
    #
    # Install Wine
    #
    # beckford@: Install runtime dependencies not modeled in `wine` package.
    # * gnutls - 'gnutls_initialize failed to load libgnutls, no support for encryption'
    # * xvfb-run - not strictly needed, but complains about 'Application tried to create a window, but no driver could be loaded.' 'Make sure that your X server is running and that $DISPLAY is set correctly.'
    ./sbin/apk.static \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main \
    -X ${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/community \
    -X ${ALPINE_MIRROR}/edge/testing \
    -U --allow-untrusted \
    -p ${chroot_dir} \
    add wine \
    winetricks \
    gnutls \
    xvfb-run \
    ; \
    fi

# Setup the chroot (except the mounting which we do at container start time)
# https://wiki.alpinelinux.org/wiki/Alpine_Linux_in_a_chroot

RUN mknod -m 666 ${chroot_dir}/dev/full c 1 7 && \
    mknod -m 666 ${chroot_dir}/dev/ptmx c 5 2 && \
    mknod -m 666 ${chroot_dir}/dev/tty c 5 0

RUN cp -L /etc/resolv.conf ${chroot_dir}/etc/

RUN mkdir -p ${chroot_dir}/etc/apk && \
    echo "${ALPINE_MIRROR}/v${TARGET_ALPINE_VERSION}/main" > ${chroot_dir}/etc/apk/repositories

# Prepare the entry points
RUN install -d ${chroot_dir}/build-sandbox
COPY container-entrypoint.sh /opt/linux-build/container-entrypoint.sh
COPY sandbox-entrypoint.sh ${chroot_dir}/opt/build-sandbox/sandbox-entrypoint.sh
COPY crossplatform-functions.sh ${chroot_dir}/opt/build-sandbox/crossplatform-functions.sh

# Cleanup
WORKDIR /
RUN rm -rf /tmp/work

# Done
ENTRYPOINT ["/opt/linux-build/container-entrypoint.sh"]
