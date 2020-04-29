#!/bin/bash

set -e

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRATCH="$HERE/scratch"
mkdir -p "$SCRATCH"
cd "$HERE"

[[ -z "$NUM_NODES" ]] && NUM_NODES=1
if (( NUM_NODES < 1 )); then
    echo "If set, env var NUM_NODES must contain a number >= 1" >&2
    exit 1
fi

bash "$HERE/teardown.sh"

echo "Going to create $NUM_NODES node(s)..."

QCOW="$SCRATCH/fedora-coreos-qemu.qcow2"

if [[ ! -f "$QCOW" || "$(wc -c < "$QCOW")" -eq 0 ]]; then
    IMG_LOC="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/31.20200407.3.0/x86_64/fedora-coreos-31.20200407.3.0-qemu.x86_64.qcow2.xz"

    echo "Fetching and decompressing image. This may take a minute..."
    curl -sfL "$IMG_LOC" | xzcat > "$QCOW"
else
    echo "Reusing $QCOW"
fi

AUTH_ME="$(tr -d "\n" < "$HOME/.ssh/id_rsa.pub")"
K3S_TOKEN="$(uuidgen | base64 -w 0)"

for NODE_NUMBER in $(seq 0 "$(( NUM_NODES - 1 ))"); do
    IGN="$SCRATCH/node$NODE_NUMBER.ign"

    sed < "$HERE/base.yaml" \
        -e "s|YOUR_KEY_HERE|$AUTH_ME|g" \
        -e "s|K3S_TOKEN|$K3S_TOKEN|g" \
        -e "s|NODE_NUMBER|$NODE_NUMBER|g" \
    | podman run -i quay.io/coreos/fcct:release --pretty --strict \
        > "$IGN"

    NQ="$SCRATCH/fcos.node$NODE_NUMBER.qcow2"
    if [[ -f "$NQ" ]]; then
        rm -f "$NQ"
    fi
    rm -f "$SCRATCH/disk.node$NODE_NUMBER.0" "$SCRATCH/disk.node$NODE_NUMBER.1"
    qemu-img create -f qcow2 -b "$QCOW" "$NQ"

    VM_NAME="issue_307_node$NODE_NUMBER"

    echo "Let's make $VM_NAME"

    virt-install --connect qemu:///system -n "$VM_NAME" \
        -r 2048 --vcpus=2 \
        --os-variant=generic  --import --graphics=none --noautoconsole \
        --disk size=10,backing_store="$NQ" \
        --disk "size=5,path=$SCRATCH/disk.node$NODE_NUMBER.0" \
        --disk "size=5,path=$SCRATCH/disk.node$NODE_NUMBER.1" \
        --qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=$IGN"

    echo "$VM_NAME is booting."

done
