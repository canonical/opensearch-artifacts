#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/read-option-value.sh

usage() {
cat << EOF
usage: test-security-index-created.sh --admin-auth-password admin
Tests if the security index has been successfully created.
--admin-auth-password  (Optional) Password for basic auth with the opensearch rest api, default "admin"
--help                 Shows help menu
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
        admin_auth_password="admin"
    fi
}


parse_args "$@"
set_defaults


# Check cluster health
endpoint="https://localhost:9200/.opendistro_security"

sec_index_resp=$(${SNAP_CURRENT}/usr/bin/curl -k -I -s -o /dev/null -w "%{http_code}" "${endpoint}" -u "admin:${admin_auth_password}")
echo -e "Security index response: \n ${sec_index_resp}"

if [ "${sec_index_resp}" != "200" ]; then
    exit 1
fi

echo "PASSED."
