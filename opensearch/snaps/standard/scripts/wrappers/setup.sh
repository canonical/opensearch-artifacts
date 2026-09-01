#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: setup.sh --root-password password ...
To be ran / setup once per cluster.
--cluster-name            (Optional)  Name of the cluster
--node-name               (Optional)  Name of the current node, default: opensearch-12345678
--node-roles              (Optional)  Type of the node, array combination of: [cluster_manager, data, voting_only, ..]
--node-host               (Optional)  IP address used to bind the node, default: [ _local_, _site_ ]
--seed-hosts              (Optional)  Private IP of all the cluster-manager eligible nodes, default: ["127.0.0.1", "[::1]"]
--security-disabled       (Optional)  Enum of either yes, no (default). Enables or disables the security plugin.
--tls-self-managed        (Optional)  Enum of either yes (default), no. Generates and self-signs the certificates.
--tls-init-setup          (Optional)  Enum of either yes, no (default). Creates a root and admin certs if set to yes.
--tls-priv-key-root-pass  (Optional)  Password for encrypting the root key. If unset, the keys are generated unencrypted.
--tls-root-subject        (Optional)  Subject for the root
--tls-priv-key-admin-pass (Optional)  Password for encrypting the admin key. If unset, the key is generated unencrypted.
--tls-admin-subject       (Optional)  Subject for the admin certificate
--tls-priv-key-node-pass  (Optional)  Password for encrypting the node key. If unset, the key is generated unencrypted.
--tls-node-subject        (Optional)  Subject for the node certificate
--tls-for-rest            (Optional)  Enum of either: yes (default), no. Enables the certificate for both the transport and rest layers or just the former
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

security_disabled=""

tls_self_managed=""
tls_init_setup=""
tls_priv_key_root_pass=""
tls_root_subject=""
tls_priv_key_admin_pass=""
tls_admin_subject=""
tls_priv_key_node_pass=""
tls_node_subject=""
tls_for_rest=""

# Args handling
function parse_args() {
    local LONG_OPTS_LIST=(
        "cluster-name"
        "node-name"
        "node-roles"
        "node-host"
        "seed-hosts"
        "security-disabled"
        "tls-self-managed"
        "tls-init-setup"
        "tls-priv-key-root-pass"
        "tls-root-subject"
        "tls-priv-key-admin-pass"
        "tls-admin-subject"
        "tls-priv-key-node-pass"
        "tls-node-subject"
        "tls-for-rest"
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
            --security-disabled) shift
                security_disabled=$1
                ;;
            --tls-self-managed) shift
                tls_self_managed=$1
                ;;
            --tls-init-setup) shift
                tls_init_setup=$1
                ;;
            --tls-priv-key-root-pass) shift
                tls_priv_key_root_pass=$1
                ;;
            --tls-priv-key-admin-pass) shift
                tls_priv_key_admin_pass=$1
                ;;
            --tls-priv-key-node-pass) shift
                tls_priv_key_node_pass=$1
                ;;
            --tls-root-subject) shift
                tls_root_subject=$1
                ;;
            --tls-admin-subject) shift
                tls_admin_subject=$1
                ;;
            --tls-node-subject) shift
                tls_node_subject=$1
                ;;
            --tls-for-rest) shift
                tls_for_rest=$1
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

    if [ -z "${security_disabled}" ] || [ "${security_disabled}" != "yes" ]; then
        security_disabled="no"
    fi

    if [ -z "${tls_self_managed}" ] || [ "${tls_self_managed}" != "no" ]; then
        tls_self_managed="yes"
    fi

    if [ -z "${tls_init_setup}" ] || [ "${tls_init_setup}" != "yes" ]; then
        tls_init_setup="no"
    fi

    if [ -z "${tls_for_rest}" ] || [ "${tls_for_rest}" != "no" ]; then
        tls_for_rest="yes"
    fi

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
echo "plugins.security.disabled: ${security_disabled}"
if [ "${tls_self_managed}" == "yes" ]; then
    echo "TLS certificates will be self-managed."
    if [ "${tls_init_setup}" == "yes" ]; then
        echo "Root and admin certificates will be generated."
    else
        echo "Root and admin certificates will not be generated."
    fi
    echo "Node certificate will be generated."
else
    echo "TLS certificates will not be self-managed. If this is a reconfiguration, existing certificates will be cleaned up."
fi



source "${OPS_ROOT}"/helpers/snap-logger.sh "setup"
source "${OPS_ROOT}"/helpers/set-conf.sh
source "${OPS_ROOT}"/helpers/io.sh

opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"
set_yaml_prop "${opensearch_yaml}" "cluster.name" "${cluster_name}"
set_yaml_prop "${opensearch_yaml}" "node.name" "${node_name}"
set_yaml_prop "${opensearch_yaml}" "node.roles" "${node_roles}"
set_yaml_prop "${opensearch_yaml}" "network.host" "${node_host}"
set_yaml_prop "${opensearch_yaml}" "discovery.seed_hosts" "${seed_hosts}"

if [ -n "${initial_cluster_manager_nodes}" ]; then
    set_yaml_prop "${opensearch_yaml}" "cluster.initial_cluster_manager_nodes" "${initial_cluster_manager_nodes}"
fi

if [ "${security_disabled}" == "yes" ]; then
    set_yaml_prop "${opensearch_yaml}" "plugins.security.disabled" "true"
else
    set_yaml_prop "${opensearch_yaml}" "plugins.security.disabled" "false"
fi

TLS_DIR="${OPS_ROOT}/security/tls"
if [ "${tls_self_managed}" == "yes" ]; then

    if [ "${tls_init_setup}" == "yes" ]; then
        # create root and admin certs
        source \
            "${TLS_DIR}"/self-managed-init.sh \
                --root-password "${tls_priv_key_root_pass}" \
                --admin-password "${tls_priv_key_admin_pass}" \
                --root-subject "${tls_root_subject}" \
                --admin-subject "${tls_admin_subject}" \
                --rest-with-tls "${tls_for_rest}" \
                --target-dir "${OPENSEARCH_PATH_CERTS}"

        keys=("root-ca" "root-ca-key" "admin" "admin-key")
        for key in "${keys[@]}"; do
            set_access_restrictions "${OPENSEARCH_PATH_CERTS}/${key}.pem" 664
        done
    else
        # If tls-init-setup is set to "no" we clean up only the admin certificates
        # since the root CA is still needed for signing node certificates.
        source "${TLS_DIR}"/cleanup.sh

        cleanup_admin_certs
    fi

    # create node cert
    source \
        "${TLS_DIR}"/self-managed-node.sh \
            --name "${node_name}" \
            --root-password "${tls_priv_key_root_pass}" \
            --node-password "${tls_priv_key_node_pass}" \
            --node-subject "${tls_node_subject}" \
            --rest-with-tls "${tls_for_rest}" \
            --target-dir "${OPENSEARCH_PATH_CERTS}"

    keys=("node-${node_name}" "node-${node_name}-key")
    for key in "${keys[@]}"; do
        set_access_restrictions "${OPENSEARCH_PATH_CERTS}/${key}.pem" 664
    done
else
    source "${TLS_DIR}"/cleanup.sh

    cleanup_root_certs
    cleanup_admin_certs
    cleanup_node_certs
fi

