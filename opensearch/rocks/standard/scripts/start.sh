#!/usr/bin/env bash

set -eux

CLUSTER_NAME="${CLUSTER_NAME:-opensearch-dev}"
NODE_NAME="${NODE_NAME:-node-0}"
NODE_ROLES="${NODE_ROLES:-cluster_manager,data}"
INITIAL_CM_NODES="${INITIAL_CM_NODES:-}"
NETWORK_HOST="${NETWORK_HOST:-_local_,_site_}"
SEED_HOSTS="${SEED_HOSTS:-}"


function set_yaml_prop() {
    local target_file="${1}"
    local key="${2}"
    local value="${3}"

    /usr/bin/python3 /usr/bin/set_conf.py --file "${target_file}" --key "${key}" --value "${value}"
}

function network_host() {
    echo "[ \"_site_\", \"$(hostname -i)\" ]"
}

function node_roles() {
    formatted_roles=""

    IFS=',' read -r -a roles <<< "${NODE_ROLES}"
    for role in "${roles[@]}"; do
        if [ -n "${formatted_roles}" ]; then
            formatted_roles="${formatted_roles}, "
        fi
        formatted_roles="${formatted_roles}\"$(echo -e "${role}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted_roles} ]"
}

function init_cm_nodes() {
    formatted_nodes=""

    IFS=',' read -r -a nodes <<< "${INITIAL_CM_NODES}"
    for node in "${nodes[@]}"; do
        if [ -n "${formatted_nodes}" ]; then
            formatted_nodes="${formatted_nodes}, "
        fi
        formatted_nodes="${formatted_nodes}\"$(echo -e "${node}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted_nodes} ]"
}

function seed_hosts() {
    formatted_hosts=""

    if [[ "${NODE_ROLES}" == *"cluster_manager"* ]]; then
        formatted_hosts="\"$(hostname -i)\""
    fi

    IFS=',' read -r -a hosts <<< "${SEED_HOSTS}"
    for host in "${hosts[@]}"; do
        if [ -n "${formatted_hosts}" ]; then
            formatted_hosts="${formatted_hosts}, "
        fi
        formatted_hosts="${formatted_hosts}\"$(echo -e "${host}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted_hosts} ]"
}

function setup_security_plugin() {
    local security_plugin="${OPENSEARCH_PLUGINS}/opensearch-security"

    if [ ! -d "${security_plugin}" ]; then
        echo "OpenSearch Security Plugin does not exist, disable by default"
        return
    fi

    # Installing the demo configuration of a disabled plugin is pointless,
    # and would fail without OPENSEARCH_INITIAL_ADMIN_PASSWORD.
    if [ "${DISABLE_INSTALL_DEMO_CONFIG:-}" = "true" ] \
            || [ "${DISABLE_SECURITY_PLUGIN:-}" = "true" ]; then
        echo "Disabling execution of install_demo_configuration.sh for OpenSearch Security Plugin"
    else
        echo "Enabling execution of install_demo_configuration.sh for OpenSearch Security Plugin"
        /bin/bash "${security_plugin}/tools/install_demo_configuration.sh" -y -i -s
    fi

    if [ "${DISABLE_SECURITY_PLUGIN:-}" = "true" ]; then
        echo "Disabling OpenSearch Security Plugin"
        opensearch_opts+=("-Eplugins.security.disabled=true")
    else
        echo "Enabling OpenSearch Security Plugin"
    fi
}


export OPENSEARCH_JAVA_OPTS="-Dopensearch.cgroups.hierarchy.override=/ ${OPENSEARCH_JAVA_OPTS:-}"

opensearch_opts=()
while IFS='=' read -r envvar_key envvar_value; do
    if [[ "${envvar_key}" =~ ^[a-z0-9_]+\.[a-z0-9_]+ || "${envvar_key}" == "processors" ]]; then
        if [ -n "${envvar_value}" ]; then
            opensearch_opts+=("-E${envvar_key}=${envvar_value}")
        fi
    fi
done < <(env)

conf="${OPENSEARCH_PATH_CONF}/opensearch.yml"

set_yaml_prop "${conf}" "cluster.name" "${CLUSTER_NAME}"
set_yaml_prop "${conf}" "node.name" "${NODE_NAME}"
set_yaml_prop "${conf}" "node.roles" "$(node_roles)"

if [[ -n "${INITIAL_CM_NODES}" ]] && [[ "${NODE_ROLES}" == *"cluster_manager"* ]]; then
    set_yaml_prop "${conf}" "cluster.initial_cluster_manager_nodes" "$(init_cm_nodes)"
fi

set_yaml_prop "${conf}" "network.host" "$(network_host)"
set_yaml_prop "${conf}" "discovery.seed_hosts" "$(seed_hosts)"
set_yaml_prop "${conf}" "path.data" "${OPENSEARCH_PATH_DATA}"
set_yaml_prop "${conf}" "path.logs" "${OPENSEARCH_PATH_LOGS}"
sed -i "s@=logs/@=${OPENSEARCH_PATH_LOGS}/@" "${OPENSEARCH_PATH_CONF}/jvm.options"
sed -i "s@-javaagent:agent/@-javaagent:${OPENSEARCH_HOME}/agent/@" "${OPENSEARCH_PATH_CONF}/jvm.options"

setup_security_plugin

cat "${conf}"

exec "${OPENSEARCH_BIN}"/opensearch "${opensearch_opts[@]}"
