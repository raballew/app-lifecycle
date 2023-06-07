#!/bin/bash
# todo: fix digests being different
# todo: configure systemd to used /var/quadlets
# todo: selinux policies

. magic.sh
TYPE_SPEED=80

clear

ROOT_DIR=/var

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

    podman image prune --all -f
    archive=$(basename $1)
    touch $2/$archive.tar.gz
    sync
    tar --exclude=$archive.tar.gz -czvf $2/$archive.tar.gz -C $2 .
    (cd $2 && sha256sum $archive.tar.gz > $archive.tar.gz.sig)
}

cleanup() {
    used_digests=$(cat $ROOT_DIR/quadlets/* | grep -oP '(?<=@sha256:).*')
    for dir in $ROOT_DIR/apps/*/ ; do
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

    find $ROOT_DIR/ -xtype l -delete
}

install_tarball() {
    d=$(dirname $1)
    (cd $d && sha256sum -c $1.sig)
    tar -zxvf $1 -C $ROOT_DIR/apps/
    transaction_checksum=$(cat $1.sig | cut -d " " -f 1)
    transaction_dir=$ROOT_DIR/quadlet_$transaction_checksum
    mkdir -p $transaction_dir

    # link old configs
    link=$(readlink -f $ROOT_DIR/quadlets)
    if [[ ! "$link" == "$ROOT_DIR/quadlets" && ! -z "$link" ]] ; then
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
        for f in $ROOT_DIR/apps/$dd/* ; do
            [ -e "$f" ] || continue
            src=$(find -L "$f" | tail -n1)
            name=$(basename "$src")
            ln -sf "$src" $transaction_dir/$name
        done
    done

    image_dirs=$(tar -ztf $1 | tree --fromfile . -L 2 -d -if | grep -v "_" | sed "s#\/##g" | sed "s#\.##g" | grep -v "directories")

    for dir in $image_dirs ; do
        mkdir -p $ROOT_DIR/apps/$dir/imagestore
        podman --root=$ROOT_DIR/apps/$dir/imagestore load -i $ROOT_DIR/apps/$dir
        sync
        target_name=$(jq -r '.manifests[0].annotations."org.opencontainers.image.ref.name"' $ROOT_DIR/apps/$dir/index.json | sed 's/\@.*//')
        podman --root=$ROOT_DIR/apps/$dir/imagestore tag localhost$ROOT_DIR/apps/$dir $target_name
        find $ROOT_DIR/apps/$dir -mindepth 1 ! -regex "^$ROOT_DIR/apps/$dir/imagestore\(/.*\)?" -delete
        mv $ROOT_DIR/apps/$dir/imagestore/* /path/
        mv -f $ROOT_DIR/apps/$dir/imagestore/{.,}* $ROOT_DIR/apps/$dir/
        rm -rf $ROOT_DIR/apps/$dir/imagestore/
    done

    ln -v -snf $transaction_dir $ROOT_DIR/quadlets

    cleanup
    systemctl daemon-reload
}

rm -rf $ROOT_DIR/apps/
rm -rf $ROOT_DIR/quadlets/
rm -rf $ROOT_DIR/quadlet_*/
rm -rf /tmp/tmp.*/
mkdir -p $ROOT_DIR/apps/

# configure systemd to load quadlet files

pei "# 0 - create tarball A + signature"
a_tmp=$(mktemp -d)
create_tarball_from_dir "apps/a" $a_tmp >/dev/null 2>&1
pei "tar -ztf $a_tmp/a.tar.gz | tree --fromfile ."

pei "# 1 - create tarball B + signature"
b_tmp=$(mktemp -d)
create_tarball_from_dir "apps/b" $b_tmp >/dev/null 2>&1
pei "tar -ztf $b_tmp/b.tar.gz | tree --fromfile ."

pei "# 2 - show current directory structure"
pei "ls -lL $ROOT_DIR/apps/"
pei "ls -lL $ROOT_DIR/quadlet_*"
pei "ls -lL $ROOT_DIR/quadlets"

pe "# 3 - install tarball A"
install_tarball $a_tmp/a.tar.gz >/dev/null 2>&1
pei "# used container image digests in $ROOT_DIR/quadlets"
pei "cat $ROOT_DIR/quadlets/* | grep "Image=" | sed s#Image=##g"
pei "# directories in $ROOT_DIR/apps/"
pei "find $ROOT_DIR/apps/ -maxdepth 1 | grep -v "_" | sed s#$ROOT_DIR/apps/##g"

pe "# 4 - install tarball B"
install_tarball $b_tmp/b.tar.gz >/dev/null 2>&1
pei "# used container image digests in $ROOT_DIR/quadlets"
pei "cat $ROOT_DIR/quadlets/* | grep "Image=" | sed s#Image=##g"
pei "# directories in $ROOT_DIR/apps/"
pei "find $ROOT_DIR/apps/ -maxdepth 1 | grep -v "_" | sed s#$ROOT_DIR/apps/##g"
