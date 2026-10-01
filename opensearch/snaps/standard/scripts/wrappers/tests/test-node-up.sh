#!/usr/bin/env bash

set -eu


usage() {
cat << EOF
usage: test-node-up.sh --node-name cm0 --admin-auth-password <password>
Tests if the passed node is up and running.
--node-name             (Optional)  Name of the node to check the status, default "cm0"
--admin-auth-password   (Required)  Password of the admin user for basic auth with the opensearch rest api
--help                              Shows help menu
EOF
}


# Args
node_name=""
admin_auth_password=""


# Args handling
function parse_args () {
    # init-security boolean - from the charm, this should be based on a flag on the app data bag.
    local LONG_OPTS_LIST=(
        "node-name"
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
            --node-name) shift
                node_name=$1
                ;;
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
    if [ -z "${node_name}" ]; then
        node_name="cm0"
    fi

    if [ -z "${admin_auth_password}" ]; then
        echo "ERROR: --admin-auth-password is required. Refer to the help menu." >&2
        exit 1
    fi
}


parse_args "$@"
set_defaults


# Check node name
endpoint="https://localhost:9200"

cluster_resp=$(${SNAP_CURRENT}/usr/bin/curl -sk -XGET "${endpoint}" -u "admin:${admin_auth_password}")
echo -e "Cluster Response: \n ${cluster_resp}"

node_name_resp=$(echo "${cluster_resp}" | ${SNAP_CURRENT}/usr/bin/yq -r .name)
if [ "${node_name_resp}" != "${node_name}" ]; then
    exit 1
fi

echo "PASSED."
