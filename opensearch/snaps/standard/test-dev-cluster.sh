#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: test-dev-cluster.sh --admin-auth-password <password>
Tests if the OpenSearch cluster is well configured.
--admin-auth-password  (Optional) Password of the admin user, defaults to the one generated on install, else "admin"
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


function run_tests () {
    local -a auth_args=()
    if [ -n "${admin_auth_password}" ]; then
        auth_args=(--admin-auth-password "${admin_auth_password}")
    fi

    # Check if cluster is healthy (green):
    echo "Running: test-cluster-health-green..."
    sudo snap run opensearch.test-cluster-health-green "${auth_args[@]}"

    echo -e "\n\n---------------\n\n"

    # Check if node is up:
    echo "Running: test-node-up..."
    sudo snap run opensearch.test-node-up "${auth_args[@]}"

    echo -e "\n\n---------------\n\n"

    # Check if the security index is well initialised:
    echo "Running: test-security-index-created..."
    sudo snap run opensearch.test-security-index-created "${auth_args[@]}"
}


parse_args "$@"
run_tests
