#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: setup.sh -E <setting>=<value> [-E <setting>=<value> ...]
Reconfigures this instance: every setting is written to opensearch.yml.
-E <setting>=<value>   Sets an OpenSearch setting, e.g. -Ecluster.name=my-cluster.
                       The value is written as is, as a string. As upstream,
                       list settings accept comma separated values,
                       e.g. -Enode.roles=cluster_manager,data
                       A value in brackets is a YAML list: quote entries that
                       contain commas, e.g.
                       -Eplugins.security.nodes_dn='["CN=a,OU=x","CN=b,OU=x"]'
                       -Enode.roles=[] makes a coordinating-only node.
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
EOF
}

# Handle --help argument before snap-logger
for arg in "$@"; do
    if [ "${arg}" == "--help" ]; then
        usage
        exit 0
    fi
done

# The configuration and the logs are only writable by root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: opensearch.setup must be run as root: sudo opensearch.setup $*" >&2
    exit 1
fi


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


# Validate every setting before writing any: values in brackets must be
# YAML lists, converted here to JSON for jq.
declare -a keys=() kinds=() values=()
for setting in "${settings[@]}"; do
    key="${setting%%=*}"
    value="${setting#*=}"
    if [ -z "${value}" ]; then
        kind="remove"
    elif [[ "${value}" == \[*\] ]]; then
        kind="list"
        if ! value="$(printf '%s' "${value}" | "${SNAP}"/usr/bin/yq -c '.' 2>/dev/null)" \
            || [ "$(printf '%s' "${value}" | "${SNAP}"/usr/bin/yq -r 'type')" != "array" ]; then
            echo "ERROR: '${setting#*=}' of ${key} is not a valid YAML list." >&2
            echo "Quote entries that contain commas, e.g. -E${key}='[\"CN=a,OU=x\"]'" >&2
            exit 1
        fi
    else
        kind="string"
    fi
    keys+=("${key}")
    kinds+=("${kind}")
    values+=("${value}")
done

# Tell users what values we are using for the configuration
echo "Configuring OpenSearch with the following values:"
for i in "${!keys[@]}"; do
    case "${kinds[i]}" in
        remove) echo "${keys[i]}: (removed)" ;;
        *)      echo "${keys[i]}: ${values[i]}" ;;
    esac
done


source "${OPS_ROOT}"/helpers/snap-logger.sh "setup"
source "${OPS_ROOT}"/helpers/set-conf.sh

opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"
for i in "${!keys[@]}"; do
    case "${kinds[i]}" in
        remove) remove_yaml_prop "${opensearch_yaml}" "${keys[i]}" ;;
        list)   set_yaml_prop_json "${opensearch_yaml}" "${keys[i]}" "${values[i]}" ;;
        string) set_yaml_prop "${opensearch_yaml}" "${keys[i]}" "${values[i]}" ;;
    esac
done

echo "Restart the daemon to apply: snap restart opensearch.daemon"
