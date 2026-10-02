#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: test-cluster-health-green.sh --admin-auth-password <password>
Tests if the cluster's health status is green.
--admin-auth-password  (Optional) Password of the admin user, defaults to the one generated on install (root only), else "admin"
--help                            Shows help menu
EOF
}


# Args
admin_auth_password=""


# Args handling
function parse_args () {
    # init-security boolean - from the charm, this should be based on a flag on the app data bag.
    local LONG_OPTS_LIST=(
        "admin-auth-password"
        "help"
    )
    local opts=$(getopt \
      --longoptions "$(printf "%s:," "${LONG_OPTS_LIST[@]}")" \
      --name "$(readlink -f "${BASH_SOURCE}")" \
      --options "" \
      -- "$@"
    )
    eval set -- "${opts}"

    while [ $# -gt 0 ]; do
        case $1 in
            --admin-auth-password) shift
                admin_auth_password=$1
                ;;
            --help) usage
                exit
                ;;
        esac
        shift
    done
}

function set_defaults () {
    if [ -z "${admin_auth_password}" ]; then
        # The password generated on install, else the default of the
        # revisions that did not generate one
        admin_auth_password="$(sed -n 's/^admin: "\(.*\)"$/\1/p' "${SNAP_COMMON}/init_users_pass.yaml" 2>/dev/null || true)"
        admin_auth_password="${admin_auth_password:-admin}"
    fi
}


parse_args "$@"
set_defaults


# Check cluster health
endpoint="https://localhost:9200/_cluster/health"

health_resp=$(${SNAP_CURRENT}/usr/bin/curl -sk -XGET "${endpoint}" -u "admin:${admin_auth_password}")
echo -e "Cluster Health Response: \n ${health_resp}"

cluster_status=$(echo "${health_resp}" | ${SNAP_CURRENT}/usr/bin/yq -r .status)
if [ "${cluster_status}" != "green" ]; then
    exit 1
fi

echo "PASSED."
