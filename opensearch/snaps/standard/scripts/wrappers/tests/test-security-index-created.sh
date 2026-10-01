#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: test-security-index-created.sh --admin-auth-password <password>
Tests if the security index has been successfully created.
--admin-auth-password  (Required) Password of the admin user for basic auth with the opensearch rest api
--help                 Shows help menu
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
        echo "ERROR: --admin-auth-password is required. Refer to the help menu." >&2
        exit 1
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
