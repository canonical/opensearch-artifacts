#!/usr/bin/env bash

set -eux

CLUSTER_NAME="${CLUSTER_NAME:-opensearch-dev}"
NODE_NAME="${NODE_NAME:-node-0}"
NODE_ROLES="${NODE_ROLES:-cluster_manager,data}"
INITIAL_CM_NODES="${INITIAL_CM_NODES:-}"
# Like upstream, listen on all the interfaces by default
NETWORK_HOST="${NETWORK_HOST:-0.0.0.0}"
SEED_HOSTS="${SEED_HOSTS:-}"

# Generated passwords, readable by the opensearch user only
PASSWORDS_FILE="${OPENSEARCH_PATH_CONF}/init_users_pass.yaml"


function set_yaml_prop() {
    local target_file="${1}"
    local key="${2}"
    local value="${3}"

    /usr/bin/python3 /usr/bin/set_conf.py --file "${target_file}" --key "${key}" --value "${value}"
}

function network_host() {
    formatted_hosts=""

    IFS=',' read -r -a hosts <<< "${NETWORK_HOST}"
    for host in "${hosts[@]}"; do
        if [ -n "${formatted_hosts}" ]; then
            formatted_hosts="${formatted_hosts}, "
        fi
        formatted_hosts="${formatted_hosts}\"$(echo -e "${host}" | tr -d '[:space:]')\""
    done

    echo "[ ${formatted_hosts} ]"
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

# Password of each internal user (admin, kibanaserver, ...): the value of
# OPENSEARCH_INITIAL_<USER>_PASSWORD when set, generated otherwise and stored
# in ${PASSWORDS_FILE}. Done once, on the first start, which creates the
# security index from internal_users.yml: ${PASSWORDS_FILE} existing (empty
# when all the passwords are given) means it is done. The demo configuration
# sets the admin password, the others are set here.
function set_initial_passwords() {
    local internal_users="${OPENSEARCH_PATH_CONF}/opensearch-security/internal_users.yml"
    local hash_tool="${OPENSEARCH_PLUGINS}/opensearch-security/tools/hash.sh"
    local user var hash
    local -a users

    if [ -f "${PASSWORDS_FILE}" ]; then
        return
    fi

    mapfile -t users < <(/usr/bin/python3 /usr/bin/init_users.py users --file "${internal_users}")

    # moved into place once the demo configuration is installed
    (umask 077 && : > "${PASSWORDS_FILE}.tmp")

    # keep the passwords out of the xtrace output
    { set +x; } 2>/dev/null
    for user in "${users[@]}"; do
        var="OPENSEARCH_INITIAL_$(echo "${user}" | tr '[:lower:]-' '[:upper:]_')_PASSWORD"
        if [ -z "${!var:-}" ]; then
            export "${var}=$(/usr/bin/python3 /usr/bin/init_users.py generate-password)"
            # quoted: the password stays a string
            printf '%s: "%s"\n' "${user}" "${!var}" >> "${PASSWORDS_FILE}.tmp"
        fi

        if [ "${user}" = "admin" ]; then
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

    echo "Initial passwords not given are generated in ${PASSWORDS_FILE}"
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
        if [ -f "${PASSWORDS_FILE}.tmp" ]; then
            mv "${PASSWORDS_FILE}.tmp" "${PASSWORDS_FILE}"
        fi
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

setup_security_plugin

cat "${conf}"

# The initial passwords are only needed to set up the users
while IFS='=' read -r envvar_key _; do
    if [[ "${envvar_key}" =~ ^OPENSEARCH_INITIAL_[A-Z0-9_]+_PASSWORD$ ]]; then
        unset "${envvar_key}"
    fi
done < <(env)

exec "${OPENSEARCH_BIN}"/opensearch "${opensearch_opts[@]}"
