#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/read-option-value.sh


usage() {
cat << EOF
usage: test-node-up.sh --node-name cm0 --admin-auth-password admin
Tests if the passed node is up and running.
--node-name             (Optional)  Name of the node to check the status, default "cm0"
--admin-auth-password   (Optional)  Password for basic auth with the opensearch rest api, default "admin"
--help                              Shows help menu
EOF
}


# Args
node_name=""
admin_auth_password=""


# Args handling
function parse_args () {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --node-name|--node-name=*)
                read_option_value "$@" || return 1
                node_name="$option_value"
                shift "$option_arguments"
                ;;
            --admin-auth-password|--admin-auth-password=*)
                read_option_value "$@" || return 1
                admin_auth_password="$option_value"
                shift "$option_arguments"
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                return 1
                ;;
        esac
    done
}

function set_defaults () {
    if [ -z "${node_name}" ]; then
        node_name="cm0"
    fi

    if [ -z "${admin_auth_password}" ]; then
        admin_auth_password="admin"
    fi
}


parse_args "$@"
set_defaults


# Check node name
endpoint="https://localhost:9200"

cluster_resp=$(${SNAP_CURRENT}/usr/bin/curl -sk -XGET "${endpoint}" -u "admin:${admin_auth_password}")
echo -e "Cluster Response: \n ${cluster_resp}"

node_name_resp=$(echo "${cluster_resp}" | ${SNAP_CURRENT}/usr/bin/yq  -r .name)
if [ "${node_name_resp}" != "${node_name}" ]; then
    exit 1
fi

echo "PASSED."
