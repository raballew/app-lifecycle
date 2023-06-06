#!/bin/bash
# include the magic
. magic.sh
TYPE_SPEED=80

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

    for f in $1/* ; do
        image_id=$(get_image_id "$f")
        digest=$(get_digest_of_image_id "$image_id")
        podman pull $image_id
        podman save --format=oci-dir -o $2/$digest $image_id
        config_checksum=$(sha256sum -b "$f" | cut -d " " -f 1)
        mkdir $2/$digest"_"$config_checksum
        cp "$f" $2/$digest"_"$config_checksum
    done

    archive=$(basename $1)
    touch $2/$archive.tar.gz
    sync
    tar --exclude=$archive.tar.gz -czvf $2/$archive.tar.gz -C $2 .
    (cd $2 && sha256sum $archive.tar.gz > $archive.tar.gz.sig)
}

cleanup() {
    used_digests=$(cat /var/quadlets/* | grep -oP '(?<=@sha256:).*')
    for dir in /var/apps/*/ ; do
        echo "dddd: $dir"
        found=false
        for digest in $used_digests ; do
            if [[ $dir =~ "$digest" ]]; then
                found=true
                break
            fi
        done

        if ! $found ; then
            rm -rf $dir
        fi
    done
}

install_tarball() {
    d=$(dirname $1)
    (cd $d && sha256sum -c $1.sig)
    tar -zxvf $1 -C /var/apps/
    transaction_checksum=$(cat $1.sig | cut -d " " -f 1)
    transaction_dir=/var/quadlet_$transaction_checksum
    mkdir -p $transaction_dir

    # link old configs
    link=$(readlink -f /var/quadlets)
    if [[ ! "$link" == "/var/quadlets" && ! -z "$link" ]] ; then
        for f in $link/* ; do
            [ -e "$f" ] || continue
            src=$(find -L "$f" | tail -n1)
            name=$(basename "$src")
            ln -sf "$src" $transaction_dir/$name
        done
    fi

    # copy new configs and replace overwritten old ones
    config_dirs=$(tar -ztf $1 | tree --fromfile . -L 2 -d -if | grep "_" | sed "s#./##g")
    for dd in $config_dirs ; do
        for f in /var/apps/$dd/* ; do
            [ -e "$f" ] || continue
            src=$(find -L "$f" | tail -n1)
            name=$(basename "$src")
            ln -sf "$src" $transaction_dir/$name
        done
    done

    image_dirs=$(tar -ztf $1 | tree --fromfile . -L 2 -d -if | grep -v "_" | sed "s#\/##g" | sed "s#\.##g" | grep -v "directories")

    # podman load -i path/in/tar/digest + podman tag from index.json annotation
    ln -v -snf $transaction_dir /var/quadlets

    cleanup
}

rm -rf /var/apps/
rm -rf /var/quadlets/
rm -rf /var/quadlet_*/
rm -rf /tmp/tmp.*/
mkdir -p /var/apps/

# configure systemd to load quadlet files

pei "# 0 - create tarball A + signature"
a_tmp=$(mktemp -d)
create_tarball_from_dir "apps/a" $a_tmp >/dev/null 2>&1
pei "tar -ztf $a_tmp/a.tar.gz | tree --fromfile ."

pei "# 1 - create tarball B + signature"
b_tmp=$(mktemp -d)
create_tarball_from_dir "apps/b" $b_tmp >/dev/null 2>&1
pei "tar -ztf $b_tmp/b.tar.gz | tree --fromfile ."

pe "# 2 - show current directory structure"
pei "ls -lL /var/apps/"
pei "ls -lL /var/quadlet_*"
pei "ls -lL /var/quadlets"

pe "# 3 - install tarball A"
install_tarball $a_tmp/a.tar.gz >/dev/null 2>&1
pei "# used container image digests in /var/quadlets"
pei "cat /var/quadlets/* | grep "Image=" | sed s#Image=##g"
pei "# directories in /var/apps/"
pei "find /var/apps/ -maxdepth 1 | grep -v "_" | sed s#/var/apps/##g"

pe "# 4 - install tarball B"
install_tarball $b_tmp/b.tar.gz >/dev/null 2>&1
pei "# used container image digests in /var/quadlets"
pei "cat /var/quadlets/* | grep "Image=" | sed s#Image=##g"
pei "# directories in /var/apps/"
pei "find /var/apps/ -maxdepth 1 | grep -v "_" | sed s#/var/apps/##g"
