#!/usr/bin/env bash

# No xtrace: it would print the passwords and the secret settings
set -eu

# Users of the demo configuration whose initial password can be given in
# OPENSEARCH_INITIAL_<USER>_PASSWORD, besides admin, set by the demo
# configuration itself
DEMO_USERS=(anomalyadmin kibanaro kibanaserver logstash readall snapshotrestore)

# Settings passed to OpenSearch as -E options, which take precedence over
# opensearch.yml: the file is never modified, so it can be mounted read-only
declare -A settings=()


# Set a setting from a comma separated list, without its spaces
function set_list_setting() {
    local key="${1}"
    local value="${2}"

    settings["${key}"]="${value//[[:space:]]/}"
}

# Password of each demo user given in OPENSEARCH_INITIAL_<USER>_PASSWORD, the
# others keep their demo password. Like the admin password, set by the demo
# configuration, it only counts on the first start, which creates the
# security index from internal_users.yml.
function set_initial_passwords() {
    local internal_users="${OPENSEARCH_PATH_CONF}/opensearch-security/internal_users.yml"
    local hash_tool="${OPENSEARCH_PLUGINS}/opensearch-security/tools/hash.sh"
    local user var hash

    for user in "${DEMO_USERS[@]}"; do
        var="OPENSEARCH_INITIAL_${user^^}_PASSWORD"
        if [ -z "${!var:-}" ]; then
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
        # The demo configuration installs into the configuration directory of
        # OPENSEARCH_HOME, whatever the one OpenSearch reads
        if [ "$(realpath -m "${OPENSEARCH_PATH_CONF}")" != "${OPENSEARCH_HOME}/config" ]; then
            echo "ERROR: the demo configuration can only be installed in" \
                "${OPENSEARCH_HOME}/config, not in OPENSEARCH_PATH_CONF." \
                "Set DISABLE_INSTALL_DEMO_CONFIG=true and provide your own" \
                "security configuration." >&2
            exit 1
        fi

        set_initial_passwords
        echo "Enabling execution of install_demo_configuration.sh for OpenSearch Security Plugin"
        /bin/bash "${security_plugin}/tools/install_demo_configuration.sh" -y -i -s
    fi

    if [ "${DISABLE_SECURITY_PLUGIN:-}" = "true" ]; then
        echo "Disabling OpenSearch Security Plugin"
        settings["plugins.security.disabled"]="true"
    else
        echo "Enabling OpenSearch Security Plugin"
    fi
}


export OPENSEARCH_JAVA_OPTS="-Dopensearch.cgroups.hierarchy.override=/ ${OPENSEARCH_JAVA_OPTS:-}"

# Variables overriding a setting of opensearch.yml, when given
if [ -n "${CLUSTER_NAME:-}" ]; then
    settings["cluster.name"]="${CLUSTER_NAME}"
fi
if [ -n "${NODE_NAME:-}" ]; then
    settings["node.name"]="${NODE_NAME}"
fi
if [ -n "${NODE_ROLES:-}" ]; then
    set_list_setting "node.roles" "${NODE_ROLES}"
fi
if [ -n "${NETWORK_HOST:-}" ]; then
    set_list_setting "network.host" "${NETWORK_HOST}"
fi
if [ -n "${SEED_HOSTS:-}" ]; then
    set_list_setting "discovery.seed_hosts" "${SEED_HOSTS}"
fi

# Like upstream, a variable named after a setting, e.g. cluster.name, sets it.
# It takes precedence over the variables above. Each variable is read whole,
# a value can not add other settings, whatever its characters.
while IFS= read -r -d '' entry; do
    key="${entry%%=*}"
    value="${entry#*=}"
    if [[ "${key}" =~ ^[a-z0-9_]+\.[a-z0-9_]+ || "${key}" == "processors" ]] \
            && [ -n "${value}" ]; then
        settings["${key}"]="${value}"
    fi
done < <(env -0)

# Only on nodes that may be cluster manager, which a node without node.roles
# can be
if [[ -n "${INITIAL_CM_NODES:-}" ]] \
        && [[ -z "${settings[node.roles]:-}" \
            || ",${settings[node.roles]}," == *",cluster_manager,"* ]] \
        && [ -z "${settings[cluster.initial_cluster_manager_nodes]:-}" ]; then
    set_list_setting "cluster.initial_cluster_manager_nodes" "${INITIAL_CM_NODES}"
fi

setup_security_plugin

opensearch_opts=()
for key in "${!settings[@]}"; do
    opensearch_opts+=("-E${key}=${settings[${key}]}")
done
# The names only, the values may be secrets
if [ "${#settings[@]}" -gt 0 ]; then
    echo "Settings overridden: ${!settings[*]}"
fi

# The initial passwords are only needed to set up the users
while IFS= read -r -d '' entry; do
    key="${entry%%=*}"
    if [[ "${key}" =~ ^OPENSEARCH_INITIAL_[A-Z0-9_]+_PASSWORD$ ]]; then
        unset "${key}"
    fi
done < <(env -0)

exec "${OPENSEARCH_BIN}"/opensearch "${opensearch_opts[@]}"
