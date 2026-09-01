#!/usr/bin/env bash

set -eu


# source "${OPS_ROOT}"/helpers/snap-logger.sh "daemon"
source "${OPS_ROOT}"/helpers/snap-interfaces.sh
source "${OPS_ROOT}"/sys/set-sys-config.sh


usage() {
cat << EOF
usage: start.sh --init-security yes --admin-password ...
To be ran / setup once per cluster.
--init-security   (Optional)    Enum of either: yes (default), no . Should be ran ONCE per cluster IF security enabled.
--admin-password  (Optional)    Passphrase of the admin key
--help                          Shows help menu
EOF
}


# Args
init_security=""
admin_password=""


# Args handling
function parse_args () {
    # init-security boolean - from the charm, this should be based on a flag on the app data bag.
    init_security="$(snapctl get init-security)"
    admin_password="$(snapctl get admin-password)"
}

function set_defaults () {
    if [ -z "${init_security}" ] || [ "${init_security}" != "no" ]; then
        init_security="yes"
    fi
}

# Since the daemon is running under snap_daemon:snap_daemon
# It cannot access the QAT VFIO devices that are owned by
# root:qat.
# One solution would be adding the group qat to the user
# snap_daemon but as of now, snapd does not allow to do that.
# The solution is to give the group snap_daemon this access
# by ACL.
# All VFIO devices owned by the group qat will be configured
# to allow RW access for snap_daemon group.
function configure_qat() {
    [ "${SNAP_ARCH}" = "amd64" ] || return 0

    qat_group="qat"
    if $(getent group "${qat_group}" >/dev/null); then
      find /dev/vfio/ -maxdepth 1 -group "${qat_group}" \
        -exec ${SNAP}/usr/bin/setfacl -m group:snap_daemon:rw {} \;
    fi
}

function start_opensearch () {
    # This is a must for starting the snap 
    # since the snap is confined and cannot access the host system
    exit_if_missing_perm "mount-observe"

    warn_if_missing_perm "log-observe"
    warn_if_missing_perm "sys-fs-cgroup-service"
    warn_if_missing_perm "system-observe"
    # This is not autoconnected
    warn_if_missing_perm "process-control"

    configure_qat

    "${SNAP}"/usr/bin/setpriv \
        --clear-groups \
        --reuid snap_daemon \
        --regid snap_daemon -- \
        "${OPENSEARCH_BIN}"/opensearch
}


parse_args
set_defaults

start_opensearch
