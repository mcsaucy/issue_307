#!/bin/bash

set -e

mapfile OUR_VMS < <(virsh --connect qemu:///system list | grep issue_329_node0)
DOMAIN_ID="$(echo "${OUR_VMS[0]}" | awk '{print $1}')"
IP=$(virsh --connect qemu:///system domifaddr "$DOMAIN_ID" \
    | grep "vnet" | awk '{print $4}' | cut -d/ -f1)

if [[ -z "$IP" ]]; then
    echo "Can't determine IP of node 0. This could be because it's booting."
    echo "Ensure it's running and try again later."
    exit 1
fi

echo "Preparing to ssh to core@$IP"
ssh "core@$IP"
