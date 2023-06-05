#!/bin/bash
# include the magic
. magic.sh
TYPE_SPEED=50

# hide the evidence
clear

get_image_id() {
    if [[ $# -eq 0 ]] ; then
        exit 1
    fi

    if [ ! -f $1 ] ; then
        exit 1
    else
        iid=$(grep -oP '(?<=Image=).*' $1)
        echo "$iid"
    fi
}

get_digest_of_image_id() {
    if [[ $# -eq 0 ]] ; then
        exit 1
    fi

    digest=$(echo $1 | grep -oP '(?<=@sha256:).*')
    echo "$digest"
}

create_tarball_from_dir() {
    if [[ $# -eq 0 ]] ; then
        exit 1
    fi

    for f in "$1"/* ; do
        echo "f: $f"
        image_id=$(get_image_id "$f")
        digest=$(get_digest_of_image_id "$image_id")
        podman pull $image_id
        podman save --format=oci-dir -o $2/$digest $image_id
        cp "$f" $2/$digest
    done

    archive=$(basename $1)
    touch $2/$archive.tar.gz
    sync
    tar --exclude=$archive.tar.gz -czvf $2/$archive.tar.gz -C $2 .
    (cd $2 && sha256sum $archive.tar.gz > $archive.tar.gz.sig)
}

rm -rf /var/apps/
rm -rf /var/quadlet/
rm -rf /tmp/tmp.*/
mkdir -p /var/apps/
mkdir -p /var/quadlet/

# configure systemd to load quadlet files

pei "# 0 - create tarball A + signature"
a_tmp=$(mktemp -d)
create_tarball_from_dir "apps/a" $a_tmp >/dev/null 2>&1
pe "tar -ztf $a_tmp/a.tar.gz | tree --fromfile ."
pe "cat $a_tmp/a.tar.gz.sig"

pei "# 1 - create tarball B + signature"
b_tmp=$(mktemp -d)
create_tarball_from_dir "apps/b" $b_tmp >/dev/null 2>&1
pe "tar -ztf $b_tmp/b.tar.gz | tree --fromfile ."
pe "cat $b_tmp/b.tar.gz.sig"

pei "# 2 - install tarball A"
# checksum validation
# install to /var/apps/digest with podman load -i path/in/tar/digest + podman tag from index.json annotation
# link to /var/quadlet_<checksum>
# symlink /var/quadlet_<checksum> to /var/quadlet

pei "# 3 - install tarball B"
