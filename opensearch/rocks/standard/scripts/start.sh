#!/usr/bin/env bash

set -eux

# Settings of opensearch.yml. Those without a default are only set when given,
# OpenSearch defaults apply otherwise. network.host binds the loopback
# interface too, for the tools connecting to localhost.
CLUSTER_NAME="${CLUSTER_NAME:-opensearch-cluster}"
NODE_NAME="${NODE_NAME:-}"
NODE_ROLES="${NODE_ROLES:-}"
INITIAL_CM_NODES="${INITIAL_CM_NODES:-}"
NETWORK_HOST="${NETWORK_HOST:-0.0.0.0}"
SEED_HOSTS="${SEED_HOSTS:-}"

function set_yaml_prop() {
    local target_file="${1}"
    local key="${2}"
    local value="${3}"

    /usr/bin/python3 /usr/bin/set_conf.py --file "${target_file}" --key "${key}" --value "${value}"
}

# Format a comma separated list as a YAML list
function yaml_list() {
    local formatted=""
    local item
    local -a items

    IFS=',' read -r -a items <<< "${1}"
    for item in "${items[@]}"; do
        if [ -n "${formatted}" ]; then
            formatted="${formatted}, "
        fi
        formatted="${formatted}\"$(echo -e "${item}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted} ]"
}

# Password of each internal user (kibanaserver, logstash, ...) given in
# OPENSEARCH_INITIAL_<USER>_PASSWORD, the others keep their demo password.
# Like the admin password, set by the demo configuration, it only counts on
# the first start, which creates the security index from internal_users.yml.
function set_initial_passwords() {
    local internal_users="${OPENSEARCH_PATH_CONF}/opensearch-security/internal_users.yml"
    local hash_tool="${OPENSEARCH_PLUGINS}/opensearch-security/tools/hash.sh"
    local user var hash
    local -a users

    mapfile -t users < <(/usr/bin/python3 /usr/bin/init_users.py users --file "${internal_users}")

    # keep the passwords out of the xtrace output
    { set +x; } 2>/dev/null
    for user in "${users[@]}"; do
        var="OPENSEARCH_INITIAL_$(echo "${user}" | tr '[:lower:]-' '[:upper:]_')_PASSWORD"
        if [ "${user}" = "admin" ] || [ -z "${!var:-}" ]; then
            continue
        fi

        hash="$(bash "${hash_tool}" -env "${var}")"
        if ! [[ "${hash}" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]]; then
            echo "ERROR: could not hash the initial password of ${user}." >&2
            exit 1
        fi
        /usr/bin/python3 /usr/bin/init_users.py set-hash \
            --file "${internal_users}" --user "${user}" --hash "${hash}"
    done
    set -x
}

function setup_security_plugin() {
    local security_plugin="${OPENSEARCH_PLUGINS}/opensearch-security"

    if [ ! -d "${security_plugin}" ]; then
        echo "OpenSearch Security Plugin does not exist, disable by default"
        return
    fi

    # Installing the demo configuration of a disabled plugin is pointless
    if [ "${DISABLE_INSTALL_DEMO_CONFIG:-}" = "true" ] \
            || [ "${DISABLE_SECURITY_PLUGIN:-}" = "true" ]; then
        echo "Disabling execution of install_demo_configuration.sh for OpenSearch Security Plugin"
    else
        set_initial_passwords
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
set_yaml_prop "${conf}" "network.host" "$(yaml_list "${NETWORK_HOST}")"
set_yaml_prop "${conf}" "path.data" "${OPENSEARCH_PATH_DATA}"
set_yaml_prop "${conf}" "path.logs" "${OPENSEARCH_PATH_LOGS}"

if [ -n "${NODE_NAME}" ]; then
    set_yaml_prop "${conf}" "node.name" "${NODE_NAME}"
fi
if [ -n "${NODE_ROLES}" ]; then
    set_yaml_prop "${conf}" "node.roles" "$(yaml_list "${NODE_ROLES}")"
fi

# Without node.roles, a node has the default roles, cluster_manager included
if [[ -n "${INITIAL_CM_NODES}" ]] \
        && [[ -z "${NODE_ROLES}" || "${NODE_ROLES}" == *"cluster_manager"* ]]; then
    set_yaml_prop "${conf}" "cluster.initial_cluster_manager_nodes" "$(yaml_list "${INITIAL_CM_NODES}")"
fi

if [ -n "${SEED_HOSTS}" ]; then
    set_yaml_prop "${conf}" "discovery.seed_hosts" "$(yaml_list "${SEED_HOSTS}")"
fi
sed -i "s@=logs/@=${OPENSEARCH_PATH_LOGS}/@" "${OPENSEARCH_PATH_CONF}/jvm.options"
sed -i "s@-javaagent:agent/@-javaagent:${OPENSEARCH_HOME}/agent/@" "${OPENSEARCH_PATH_CONF}/jvm.options"

setup_security_plugin

cat "${conf}"

# The initial passwords are only needed to set up the users
while IFS='=' read -r envvar_key _; do
    if [[ "${envvar_key}" =~ ^OPENSEARCH_INITIAL_[A-Z0-9_]+_PASSWORD$ ]]; then
        unset "${envvar_key}"
    fi
done < <(env)

exec "${OPENSEARCH_BIN}"/opensearch "${opensearch_opts[@]}"
