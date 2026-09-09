#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: setup.sh --cluster-name name --node-name name ...
Reconfigures the cluster and node settings of this instance.
--cluster-name            (Optional)  Name of the cluster, default: opensearch-cluster
--node-name               (Optional)  Name of the current node, default: opensearch-12345678
--node-roles              (Optional)  Type of the node, array combination of: [cluster_manager, data, voting_only, ..]
--node-host               (Optional)  IP address to bind the node, default: [ _local_, _site_ ]
--seed-hosts              (Optional)  Private IP of all the cluster-manager eligible nodes, default: ["127.0.0.1", "[::1]"]
--http-port               (Optional)  Port to bind the REST layer, default: 9200
--transport-port          (Optional)  Port to bind the transport layer, default: 9300
--help                                Shows help menu
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
cluster_name=""
node_name=""
node_roles=""
node_host=""
seed_hosts=""
initial_cluster_manager_nodes=""
http_port=""
transport_port=""

# Args handling
function parse_args() {
    local LONG_OPTS_LIST=(
        "cluster-name"
        "node-name"
        "node-roles"
        "node-host"
        "seed-hosts"
        "http-port"
        "transport-port"
    )
    # shellcheck disable=SC2155
    local opts=$(getopt \
      --longoptions "$(printf "%s:," "${LONG_OPTS_LIST[@]}")" \
      --name "$(readlink -f "${BASH_SOURCE}")" \
      --options "" \
      -- "$@"
    )
    eval set -- "${opts}"

    while [ $# -gt 0 ]; do
        case $1 in
            --cluster-name) shift
                cluster_name=$1
                ;;
            --node-name) shift
                node_name=$1
                ;;
            --node-roles) shift
                node_roles=$1
                ;;
            --node-host) shift
                node_host=$1
                ;;
            --seed-hosts) shift
                seed_hosts=$1
                ;;
            --http-port) shift
                http_port=$1
                ;;
            --transport-port) shift
                transport_port=$1
                ;;
        esac
        shift
    done
}


function set_defaults () {
    if [ -z "${cluster_name}" ]; then
        cluster_name="opensearch-cluster"
    fi

    if [ -z "${node_name}" ]; then
        # Generate random hash suffix
        suffix=$(openssl rand -hex 4)
        node_name="opensearch-${suffix}"
    fi

    if [ -z "${node_roles}" ]; then
        # Default to a single-node-capable set of roles: a node without
        # the data role cannot hold the security index shards.
        node_roles="cluster_manager,data"
    fi

    if [ -z "${node_host}" ]; then
        node_host="[_local_, _site_]"
    fi

    if [ -z "${seed_hosts}" ]; then
        seed_hosts="[ \"127.0.0.1\", \"[::1]\" ]"  # ${node_name}]
    fi

    IFS=',' read -r -a roles <<< "${node_roles}"
    for role in "${roles[@]}"; do
        role=$(echo -e "${role}" | tr -d '[:space:]')
        if [ "${role}" == "cluster_manager" ]; then
            initial_cluster_manager_nodes="[ ${node_name} ]"
            break
        fi
    done

    node_roles="[ ${node_roles} ]"
}

parse_args "$@"
set_defaults

# Tell users what values we are using for the configuration
echo "Configuring OpenSearch with the following values:"
echo "cluster.name: ${cluster_name}"
echo "node.name: ${node_name}"
echo "node.roles: ${node_roles}"
echo "network.host: ${node_host}"
echo "discovery.seed_hosts: ${seed_hosts}"
if [ -n "${initial_cluster_manager_nodes}" ]; then
    echo "cluster.initial_cluster_manager_nodes: ${initial_cluster_manager_nodes}"
fi
if [ -n "${http_port}" ]; then
    echo "http.port: ${http_port}"
fi
if [ -n "${transport_port}" ]; then
    echo "transport.port: ${transport_port}"
fi


source "${OPS_ROOT}"/helpers/snap-logger.sh "setup"
source "${OPS_ROOT}"/helpers/set-conf.sh

opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"
set_yaml_prop "${opensearch_yaml}" "cluster.name" "${cluster_name}"
set_yaml_prop "${opensearch_yaml}" "node.name" "${node_name}"
set_yaml_prop "${opensearch_yaml}" "node.roles" "${node_roles}"
set_yaml_prop "${opensearch_yaml}" "network.host" "${node_host}"
set_yaml_prop "${opensearch_yaml}" "discovery.seed_hosts" "${seed_hosts}"

if [ -n "${initial_cluster_manager_nodes}" ]; then
    set_yaml_prop "${opensearch_yaml}" "cluster.initial_cluster_manager_nodes" "${initial_cluster_manager_nodes}"
fi

if [ -n "${http_port}" ]; then
    set_yaml_prop "${opensearch_yaml}" "http.port" "${http_port}"
fi

if [ -n "${transport_port}" ]; then
    set_yaml_prop "${opensearch_yaml}" "transport.port" "${transport_port}"
fi
