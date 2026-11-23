#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/read-option-value.sh
usage() {
cat << EOF
usage: test-cluster-health-green.sh --admin-auth-password <password>
Tests if the cluster's health status is green.
--admin-auth-password  (Required) Password of the admin user for basic auth with the opensearch rest api
--help                            Shows help menu
EOF
}


# Args
admin_auth_password=""


# Args handling
function parse_args () {
    while [ "$#" -gt 0 ]; do
        case "$1" in
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
    if [ -z "${admin_auth_password}" ]; then
        echo "ERROR: --admin-auth-password is required. Refer to the help menu." >&2
        exit 1
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
