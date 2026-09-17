#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: setup.sh -E <setting>=<value> [-E <setting>=<value> ...]
Reconfigures this instance: every setting is written to opensearch.yml.
-E <setting>=<value>   Sets an OpenSearch setting, e.g. -Ecluster.name=my-cluster.
                       List settings take comma separated values, as upstream,
                       e.g. -Enode.roles=cluster_manager,data
                       An empty value removes the setting, e.g. -Ehttp.port=
--help                 Shows help menu

The daemon must be restarted for the new settings to be applied:
  snap restart opensearch.daemon

Examples:
  setup.sh -Ecluster.name=logs -Enode.name=node-1 \\
      -Enode.roles=cluster_manager,data \\
      -Enetwork.host=_local_,_site_ \\
      -Ediscovery.seed_hosts=10.0.0.1,10.0.0.2 \\
      -Ecluster.initial_cluster_manager_nodes=node-1

  # node joining an already bootstrapped cluster
  setup.sh -Ediscovery.seed_hosts=10.0.0.1 -Ecluster.initial_cluster_manager_nodes=
EOF
}

# Handle --help argument before snap-logger
for arg in "$@"; do
    if [ "${arg}" == "--help" ]; then
        usage
        exit 0
    fi
done


# Args
declare -a settings=()


# Args handling
function parse_args() {
    local setting
    while [ $# -gt 0 ]; do
        case $1 in
            -E)
                shift
                if [ $# -eq 0 ]; then
                    echo "ERROR: -E requires a <setting>=<value> argument." >&2
                    exit 1
                fi
                setting="$1"
                ;;
            -E*)
                setting="${1#-E}"
                ;;
            *)
                echo "ERROR: unexpected argument '$1'. Settings are passed as -E <setting>=<value>." >&2
                exit 1
                ;;
        esac

        if [[ "${setting}" != *=* ]] || [ -z "${setting%%=*}" ]; then
            echo "ERROR: '${setting}' is not of the form <setting>=<value>." >&2
            exit 1
        fi
        settings+=("${setting}")

        shift
    done

    if [ "${#settings[@]}" -eq 0 ]; then
        echo "ERROR: at least one -E <setting>=<value> is required. Refer to the help menu." >&2
        exit 1
    fi
}


parse_args "$@"

# Tell users what values we are using for the configuration
echo "Configuring OpenSearch with the following values:"
for setting in "${settings[@]}"; do
    key="${setting%%=*}"
    value="${setting#*=}"
    if [ -z "${value}" ]; then
        echo "${key}: (removed)"
    else
        echo "${key}: ${value}"
    fi
done


source "${OPS_ROOT}"/helpers/snap-logger.sh "setup"
source "${OPS_ROOT}"/helpers/set-conf.sh

opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"
for setting in "${settings[@]}"; do
    key="${setting%%=*}"
    value="${setting#*=}"
    if [ -z "${value}" ]; then
        remove_yaml_prop "${opensearch_yaml}" "${key}"
    elif [[ "${value}" == *,* ]]; then
        set_yaml_prop "${opensearch_yaml}" "${key}" "[${value}]"
    else
        set_yaml_prop "${opensearch_yaml}" "${key}" "${value}"
    fi
done

echo "Restart the daemon to apply: snap restart opensearch.daemon"
