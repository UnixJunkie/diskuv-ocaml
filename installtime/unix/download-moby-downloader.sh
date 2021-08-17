#!/bin/bash
# ----------------------------
# download-moby-downloader.sh MOBYDIR
#
# Downloads and patches `download-frozen-image-v2.sh` and places it in MOBYDIR

set -euf -o pipefail

MOBYDIR=$1
shift

if [[ -x "$MOBYDIR"/download-frozen-image-v2.sh ]]; then
    exit 0
fi

install -d "$MOBYDIR"
cd "$MOBYDIR"

rm -f _download-frozen-image-v2.sh __download-frozen-image-v2.sh
curl -s https://raw.githubusercontent.com/moby/moby/6a60efc39bdb6d465d0a56d254fc0f889fa43dce/contrib/download-frozen-image-v2.sh -o _download-frozen-image-v2.sh

# replace 'case ... application/vnd.docker.image.rootfs.diff.tar.gzip)' with 'case ... application/vnd.docker.image.rootfs.diff.tar.gzip | application/vnd.docker.image.rootfs.foreign.diff.tar.gzip)'
sed 's#application/vnd.docker.image.rootfs.diff.tar.gzip)#application/vnd.docker.image.rootfs.diff.tar.gzip | application/vnd.docker.image.rootfs.foreign.diff.tar.gzip)#g' \
    _download-frozen-image-v2.sh > __download-frozen-image-v2.sh

install __download-frozen-image-v2.sh "$MOBYDIR"/download-frozen-image-v2.sh
rm -f _download-frozen-image-v2.sh __download-frozen-image-v2.sh
